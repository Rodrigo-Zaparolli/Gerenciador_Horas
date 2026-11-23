import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/edesk_credentials_service.dart';
import 'package:gerenciador_horas/shared/widgets/header_edesk_credentials_dialog.dart';

class _Credentials extends EdeskCredentialsService {
  Map<String, String>? stored;
  Completer<void>? acknowledgment;
  Completer<Map<String, String>?>? loading;
  bool failRead = false;
  @override
  Future<Map<String, String>?> ler() async {
    if (failRead) throw StateError('fixture offline');
    return loading == null ? stored : loading!.future;
  }

  @override
  Future<void> salvar({required String email, required String senha}) async {
    if (acknowledgment != null) await acknowledgment!.future;
    stored = {'email': email, 'senha': senha};
  }

  @override
  Future<void> apagar() async => stored = null;
}

Future<void> _open(WidgetTester tester, _Credentials credentials,
    {bool Function()? mounted}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester
      .pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) {
    return TextButton(
        onPressed: () => HeaderEdeskCredentialsDialog(
              context: context,
              credentials: credentials,
              isOriginMounted: mounted ?? () => context.mounted,
            ).show(),
        child: const Text('Open'));
  }))));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('waits for save acknowledgment and preserves password whitespace',
      (tester) async {
    final credentials = _Credentials()..acknowledgment = Completer<void>();
    await _open(tester, credentials);
    await tester.enterText(find.byType(TextField).at(0), ' user@example.test ');
    await tester.enterText(find.byType(TextField).at(1), ' secret ');
    await tester.tap(find.text('Salvar'));
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Salvando...'), findsOneWidget);
    expect(credentials.stored, isNull);
    credentials.acknowledgment!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(credentials.stored,
        {'email': 'user@example.test', 'senha': ' secret '});
    expect(tester.takeException(), isNull);
  });

  testWidgets('loads, reveals and removes saved credentials', (tester) async {
    final credentials = _Credentials()
      ..stored = {'email': 'user@example.test', 'senha': 'fixture'};
    await _open(tester, credentials);
    expect(find.text('Credenciais cadastradas'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField).at(1)).obscureText,
        isTrue);
    await tester.tap(find.byTooltip('Mostrar senha'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField).at(1)).obscureText,
        isFalse);
    await tester.tap(find.text('Remover'));
    await tester.pumpAndSettle();
    expect(credentials.stored, isNull);
    expect(find.text('Credenciais cadastradas'), findsNothing);
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed read remains visible and allows cancellation',
      (tester) async {
    await _open(tester, _Credentials()..failRead = true);
    expect(find.textContaining('Não foi possível recuperar'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not open after its origin is disposed during loading',
      (tester) async {
    final credentials = _Credentials()
      ..loading = Completer<Map<String, String>?>();
    await _open(tester, credentials);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    credentials.loading!.complete(null);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
