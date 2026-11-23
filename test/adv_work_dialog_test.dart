import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/edesk/adv_work_dialog.dart';

void main() {
  testWidgets(
      'Plugin NS keeps all reviewed data editable and requires confirmation',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? sent;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AdvWorkDialog(
      project: ProjectModel.fromJson(
          {'id': '2265123', 'client': 'Cliente original'}),
      pluginNs: true,
      authorized: () => true,
      sender: (data) async {
        sent = data;
        return {'confirmed': true, 'message': 'Trabalho 13 confirmado.'};
      },
    ))));
    expect(find.text('Solicitar NS de plugin'), findsOneWidget);
    expect(
        find.textContaining('Tipo de Trabalho: Programação'), findsOneWidget);
    expect(find.textContaining('Equipe: Go Live'), findsOneWidget);
    expect(sent, isNull);
    await tester.tap(find.text('Criar no E-Desk'));
    await tester.pumpAndSettle();
    expect(sent, isNull);
    expect(find.text('Informe o plugin.'), findsOneWidget);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Cliente revisado');
    await tester.enterText(fields.at(1), 'Plugin Router');
    await tester.enterText(fields.at(2), 'Solicitar NS - Router');
    await tester.enterText(fields.at(3), 'Liberar o NS para o cliente.');
    expect(sent, isNull);
    await tester.tap(find.text('Criar no E-Desk'));
    await tester.pumpAndSettle();
    expect(sent!['solicitacao'], '2265123');
    expect(sent!['url'], 'https://promob.e-desk.com.br/');
    expect(sent!['subject'], 'Solicitar NS - Router');
    expect(sent!['description'],
        'Cliente: Cliente revisado\nPlugin / produto: Plugin Router\n\nLiberar o NS para o cliente.');
    expect(sent!['confirmed'], true);
    expect(find.text('Trabalho 13 confirmado.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'ADV reviews project and description, sends once and shows receipt',
      (tester) async {
    final receipt = Completer<Map<String, dynamic>>();
    var sends = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AdvWorkDialog(
      project: ProjectModel.fromJson({'id': '2263800', 'client': 'Cliente'}),
      authorized: () => true,
      sender: (data) async {
        sends++;
        expect(data['url'], 'https://promob.e-desk.com.br/');
        expect(data['solicitacao'], '2263800');
        expect(data['subject'], 'Implantação Finalizada');
        expect(data['description'], 'Implantação concluída.');
        expect(data['confirmed'], true);
        return receipt.future;
      },
    ))));
    await tester.tap(find.text('Criar no E-Desk'));
    await tester.pumpAndSettle();
    expect(sends, 0);
    expect(find.text('Informe o detalhamento.'), findsOneWidget);
    await tester.enterText(
        find.byType(TextFormField).last, 'Implantação concluída.');
    await tester.tap(find.text('Criar no E-Desk'));
    await tester.pump();
    expect(sends, 1);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    receipt.complete(
        {'confirmed': true, 'message': 'Trabalho ADV 12 confirmado.'});
    await tester.pumpAndSettle();
    expect(find.text('Trabalho ADV 12 confirmado.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
