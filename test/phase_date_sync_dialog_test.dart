import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/edesk/phase_date_sync.dart';
import 'package:gerenciador_horas/features/edesk/phase_date_sync_dialog.dart';
import 'received_work_store_test.dart' show ImportAuth, ImportDatabase;

class PhaseSave extends FirebaseService {
  PhaseSave(ImportAuth auth) : super(database: ImportDatabase(), auth: auth);
  int calls = 0;
  String? savedWork;
  DateTime? savedEnd;
  Completer<void>? pending;
  Object? failure;
  @override
  Future<void> applyAuditedPhaseDates(
      {required String ownerUid,
      required String projectId,
      required String request,
      required String work,
      required String phase,
      required String expectedStart,
      required String expectedEnd,
      required DateTime start,
      required DateTime end}) async {
    calls++;
    expect(projectId, '2265173');
    expect(request, '2265173');
    savedWork = work;
    savedEnd = end;
    if (failure != null) throw failure!;
    await pending?.future;
  }
}

void main() {
  late ImportAuth auth;
  late PhaseSave save;
  late ProjectModel project;
  PhaseDateSyncResult? result;
  setUp(() {
    auth = ImportAuth();
    save = PhaseSave(auth);
    result = null;
    project = ProjectModel.fromJson({
      'id': '2265173',
      'client': 'Rimo',
      'subTasks': [
        {
          'subId': '4',
          'stage': 'Treinamento Catalog (OH)',
          'planStart': '2026-10-06T00:00:00.000',
          'planEnd': '2026-10-26T00:00:00.000',
          'status': 'TRAB_FIM',
          'estimatedHours': '32:00'
        }
      ]
    });
  });
  Future<void> open(WidgetTester tester, {String end = '30/10/2026'}) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () async {
                      result = await showDialog<PhaseDateSyncResult>(
                          context: context,
                          builder: (_) => PhaseDateSyncDialog(
                              project: project,
                              task: project.subTasks!.single,
                              request: project.id,
                              phase: 'Treinamento Catalog (OH)',
                              edeskStart: '6/10/2026',
                              edeskEnd: end,
                              auth: auth,
                              firebase: save));
                    },
                    child: const Text('Abrir'))))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.text('Salvar no sistema'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmar ajuste no sistema'), findsOneWidget);
    await tester.tap(find.text('Confirmar alteração'));
    await tester.pumpAndSettle();
  }

  testWidgets('Rimo button confirms and saves only after authorization',
      (tester) async {
    await open(tester);
    expect(save.calls, 0);
    await confirm(tester);
    expect(save.calls, 1);
    expect(save.savedWork, '4');
    expect(save.savedEnd, DateTime(2026, 10, 30));
    expect(result?.toEdesk, false);
    expect(result?.end, DateTime(2026, 10, 30));
  });
  testWidgets('missing dates show a visible error beside save controls',
      (tester) async {
    await open(tester, end: '');
    await tester.tap(find.text('Salvar no sistema'));
    await tester.pumpAndSettle();
    expect(find.text('Informe as duas datas.').hitTestable(), findsOneWidget);
    expect(save.calls, 0);
  });
  testWidgets('changed account produces feedback instead of silent return',
      (tester) async {
    await open(tester);
    auth.user = null;
    await tester.tap(find.text('Salvar no sistema'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Sua sessão mudou').hitTestable(), findsOneWidget);
    expect(save.calls, 0);
  });
  testWidgets('write failure is visible and does not report success',
      (tester) async {
    save.failure = StateError('Falha de confirmação no destino');
    await open(tester);
    await confirm(tester);
    expect(find.text('Falha de confirmação no destino').hitTestable(),
        findsOneWidget);
    expect(find.text('Salvar no sistema'), findsOneWidget);
    expect(result, isNull);
  });
  testWidgets('canceling confirmation never writes', (tester) async {
    await open(tester);
    await tester.tap(find.text('Salvar no sistema'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar').last);
    await tester.pumpAndSettle();
    expect(save.calls, 0);
    expect(result, isNull);
  });
  testWidgets('save stays visibly busy until destination confirms',
      (tester) async {
    save.pending = Completer<void>();
    await open(tester);
    await tester.tap(find.text('Salvar no sistema'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar alteração'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Salvando...'), findsOneWidget);
    expect(result, isNull);
    expect(save.calls, 1);
    save.pending!.complete();
    await tester.pumpAndSettle();
    expect(result?.end, DateTime(2026, 10, 30));
  });
}
