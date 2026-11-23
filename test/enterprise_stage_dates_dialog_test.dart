import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/dialogs/project_spreadsheet_dialog.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';

void main() {
  testWidgets(
      'Plugin date edit saves timeline cells and synchronizes the dependent post stage after Excel',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var start = '2026-10-08', end = '2026-11-13', revision = 'r1', writes = 0;
    List<Map<String, dynamic>>? synchronized;
    final project = ProjectModel.fromJson({
      'id': '2263800',
      'serviceType': 'Desenvolvimento Plugin',
      'excelLink': 'plugin-timeline',
      'subTasks': [
        {
          'subId': '3',
          'stage': 'Desenvolvimento Plugin',
          'planStart': start,
          'planEnd': end,
          'estimatedHours': '40:00'
        },
        {
          'subId': '5',
          'stage': 'Pós-Implantação',
          'planStart': '2026-11-14',
          'planEnd': '2026-12-20',
          'estimatedHours': '02:00'
        },
      ]
    });
    Map<String, dynamic> snapshot(
        {String? proposedStart, String? proposedEnd}) {
      final a = proposedStart ?? start, b = proposedEnd ?? end;
      final post = DateTime.parse(b)
          .add(const Duration(days: 1))
          .toIso8601String()
          .substring(0, 10);
      return {
        'revision': revision,
        'entrySheet': 'Informações de entrada',
        'checklistSheet': 'Checklist-Processo',
        'stageDatesVersion': 2,
        'filename': 'Orquinare.xlsm',
        'tasks': [],
        'fields': [
          for (final stage in ['Implantação', 'Pós-Implantação'])
            for (final endpoint in ['start', 'end'])
              {
                'sheet': 'Implantação - Linha do Tempo',
                'cell':
                    '${endpoint == 'start' ? 'H' : 'I'}${stage == 'Implantação' ? 6 : 7}',
                'kind': 'date',
                'stagePeriod': stage,
                'endpoint': endpoint,
                'dateMode': 'summary-adjusted',
                'value': stage == 'Implantação'
                    ? (endpoint == 'start' ? a : b)
                    : (endpoint == 'start' ? post : '2026-12-20')
              },
        ],
        'statusPreview': {
          'total': .824,
          'rows': [
            {
              'label': 'Implantação',
              'percentage': .697,
              'start': a,
              'end': b,
              'weight': .25
            },
            {
              'label': 'Pós-Implantação',
              'percentage': 0,
              'start': post,
              'end': '2026-12-20',
              'weight': .1
            },
          ]
        },
      };
    }

    await tester.pumpWidget(MaterialApp(
        home: ProjectSpreadsheetDialog(
      project: project,
      uidProvider: () => 'plugin-dates',
      emailProvider: () => 'user@example.com',
      phaseDatesSaver: (jobs) async {
        expect(writes, 1);
        synchronized = jobs;
      },
      transport: (args) async {
        if (args['action'] == 'excel-editor-write') {
          writes++;
          final changes = args['changes'] as List;
          expect(changes.map((c) => c['cell']).toSet(), {'H6', 'I6'});
          start = changes.singleWhere((c) => c['cell'] == 'H6')['value'];
          end = changes.singleWhere((c) => c['cell'] == 'I6')['value'];
          revision = 'r2';
          return {...snapshot(), 'saved': true, 'backup': 'test-backup.xlsm'};
        }
        if (args['action'] == 'excel-editor-preview') {
          final changes = args['changes'] as List? ?? [];
          String? changed(String cell) {
            final found = changes.where((c) => c['cell'] == cell).toList();
            return found.isEmpty ? null : found.single['value'];
          }

          return {
            ...snapshot(
                proposedStart: changed('H6'), proposedEnd: changed('I6')),
            'preview': true
          };
        }
        return snapshot();
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Tab).at(1));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    await tester.tap(find.text('13/11/2026'));
    await tester.pumpAndSettle();
    expect(find.textContaining('atividades detalhadas não são reprogramadas'),
        findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 — Desenvolvimento Plugin').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Início: 08/10/2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('9').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fim: 13/11/2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('14').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    await tester.tap(find.text('Aplicar datas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar ajustes de datas'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('15/11/2026'), findsOneWidget);
    await tester.tap(find.text('Salvar na planilha'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(synchronized, hasLength(2));
    expect(synchronized!.singleWhere((j) => j['work'] == '3')['end'],
        '2026-11-14');
    expect(synchronized!.singleWhere((j) => j['work'] == '5')['start'],
        '2026-11-15');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
