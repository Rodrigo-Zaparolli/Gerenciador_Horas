import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/projects/dialogs/project_documents_dialog.dart';

void main() {
  testWidgets('Desktop table uses full modal width and PDF is a separate tab',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: ProjectDocumentsDialog(
            project: ProjectModel.fromJson(
                {'id': '2263800', 'client': 'W de Ouro', 'excelLink': 'local'}),
            uidProvider: () => 'owner',
            transport: (args) async => {
                  'revision': 'r1',
                  'columns': [
                    for (var i = 0; i < 8; i++)
                      {
                        'letter': String.fromCharCode(65 + i),
                        'label': 'Coluna',
                        'width': 170
                      }
                  ],
                  'rows': [
                    {
                      'row': 19,
                      'cells': [1, 'Contrato', '02/07/2026', '', '', '', '', 6]
                    }
                  ],
                  'fields': [
                    {
                      'sheet': 'Implantação - Linha do Tempo',
                      'cell': 'H19',
                      'value': 6,
                      'timelineDays': true
                    }
                  ]
                })));
    await tester.pumpAndSettle();
    expect(
        tester
            .getSize(find.byKey(const ValueKey('timeline-full-width-scroll')))
            .width,
        greaterThan(1400));
    expect(find.text('Conferir documento / PDF'), findsOneWidget);
    await tester.drag(find.byKey(const ValueKey('timeline-full-width-scroll')),
        const Offset(-700, 0));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '13');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conferir documento / PDF'));
    await tester.pumpAndSettle();
    expect(find.text('Aplique os ajustes para conferir o documento original.'),
        findsOneWidget);
    expect(find.byType(DataTable), findsNothing);
    await tester.tap(find.text('Tabela do cronograma'));
    await tester.pumpAndSettle();
    expect(find.text('13'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Busy document read waits and loads without a second click',
      (tester) async {
    var reads = 0;
    await tester.pumpWidget(MaterialApp(
        home: ProjectDocumentsDialog(
            project: ProjectModel.fromJson(
                {'id': '2263800', 'client': 'W de Ouro', 'excelLink': 'local'}),
            uidProvider: () => 'owner',
            transport: (args) async {
              reads++;
              if (reads == 1)
                throw StateError(
                    'Aguarde a leitura ou gravação da planilha em andamento.');
              return {
                'revision': 'r1',
                'columns': [],
                'rows': [],
                'fields': []
              };
            })));
    await tester.pump();
    expect(reads, 1);
    expect(find.textContaining('Aguardando a liberação'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.textContaining('Aguardando a liberação'), findsNothing);
    expect(find.textContaining('Carregue o documento'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Changing account during busy read cancels the retry',
      (tester) async {
    var reads = 0;
    var owner = 'owner';
    await tester.pumpWidget(MaterialApp(
        home: ProjectDocumentsDialog(
            project: ProjectModel.fromJson(
                {'id': '2263800', 'client': 'W de Ouro', 'excelLink': 'local'}),
            uidProvider: () => owner,
            transport: (args) async {
              reads++;
              throw StateError(
                  'Aguarde a leitura ou gravação da planilha em andamento.');
            })));
    await tester.pump();
    owner = 'other';
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(reads, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'Day edits remain pending until explicit save and require confirmation',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var writes = 0;
    final calls = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(
        home: ProjectDocumentsDialog(
            project: ProjectModel.fromJson({
              'id': '2265001',
              'client': 'Cliente',
              'excelLink': 'local',
              'serviceType': 'Enterprise'
            }),
            uidProvider: () => 'owner',
            transport: (args) async {
              calls.add(args);
              if (args['operation'] == 'timeline-save') {
                writes++;
                return {'saved': true};
              }
              return {
                'revision': 'r1',
                'columns': [
                  for (var i = 0; i < 8; i++)
                    {
                      'letter': String.fromCharCode(65 + i),
                      'label': 'Coluna',
                      'width': 70
                    }
                ],
                'rows': [
                  {
                    'row': 19,
                    'cells': [1, 'Assinatura', '02/07/2026', '', '', '', '', 6]
                  }
                ],
                'fields': [
                  {
                    'sheet': 'Implantação - Linha do Tempo',
                    'cell': 'H19',
                    'value': 6,
                    'timelineDays': true,
                    'readOnly': false
                  }
                ]
              };
            })));
    await tester.pumpAndSettle();
    expect(writes, 0);
    await tester.enterText(find.byType(TextFormField).first, '13');
    await tester.pumpAndSettle();
    expect(writes, 0);
    final save = find.widgetWithText(FilledButton, 'Salvar na planilha');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Salvar na planilha original?'), findsOneWidget);
    expect(writes, 0);
    await tester
        .tap(find.widgetWithText(FilledButton, 'Salvar na planilha').last);
    await tester.pumpAndSettle();
    expect(writes, 1);
    final args = calls.firstWhere((c) => c['operation'] == 'timeline-save');
    expect((args['changes'] as List).single, {
      'sheet': 'Implantação - Linha do Tempo',
      'cell': 'H19',
      'before': 6,
      'value': 13
    });
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Account change hides document data and disables operations',
      (tester) async {
    var uid = 'owner';
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: ProjectDocumentsDialog(
            project: ProjectModel.fromJson(
                {'id': '2265001', 'client': 'Cliente', 'excelLink': 'local'}),
            uidProvider: () => uid,
            transport: (args) async {
              calls++;
              return {
                'revision': 'r1',
                'columns': [],
                'rows': [],
                'fields': []
              };
            })));
    await tester.pumpAndSettle();
    uid = 'other';
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('A conta mudou. Feche e abra esta janela novamente.'),
        findsOneWidget);
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Excel save precedes verified phase synchronization',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var saved = false;
    List<Map<String, dynamic>>? jobs;
    final project = ProjectModel.fromJson({
      'id': '2265002',
      'client': 'Cliente',
      'excelLink': 'local',
      'subTasks': [
        {
          'subId': '3',
          'stage': 'Contato Inicial',
          'planStart': '2026-07-08',
          'planEnd': '2026-07-09'
        }
      ]
    });
    await tester.pumpWidget(MaterialApp(
        home: ProjectDocumentsDialog(
            project: project,
            uidProvider: () => 'owner',
            phaseDatesSaver: (value) async {
              expect(saved, true);
              jobs = value;
            },
            transport: (args) async {
              if (args['operation'] == 'timeline-save') {
                saved = true;
                return {'saved': true};
              }
              return {
                'revision': saved ? 'r2' : 'r1',
                'columns': [
                  for (var i = 0; i < 8; i++)
                    {
                      'letter': String.fromCharCode(65 + i),
                      'label': 'Coluna',
                      'width': 70
                    }
                ],
                'rows': [
                  {
                    'row': 19,
                    'cells': [1, 'Contrato', '', '', '', '', '', saved ? 13 : 6]
                  }
                ],
                'fields': [
                  {
                    'sheet': 'Implantação - Linha do Tempo',
                    'cell': 'H19',
                    'value': saved ? 13 : 6,
                    'timelineDays': true
                  }
                ],
                'periods': [
                  {
                    'label': 'Contato Inicial',
                    'start': saved ? '2026-07-15' : '2026-07-08',
                    'end': saved ? '2026-07-16' : '2026-07-09'
                  }
                ]
              };
            })));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '13');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar na planilha'));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(FilledButton, 'Salvar na planilha').last);
    await tester.pumpAndSettle();
    expect(jobs, hasLength(1));
    expect(jobs!.single['start'], '2026-07-15');
    expect(project.subTasks!.single.planEnd, DateTime(2026, 7, 16));
    await tester.pumpWidget(const SizedBox());
  });
}
