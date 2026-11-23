import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/dialogs/project_spreadsheet_dialog.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';

void main() {
  for (final failFirst in [false, true]) {
    testWidgets(
        'Professional saves exact source cells before phase synchronization: retry=$failFirst',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var start = '2026-09-10';
      var end = '2026-12-04', revision = 'r1', writes = 0, syncs = 0;
      final order = <String>[];
      final project = ProjectModel.fromJson({
        'id': '2263850',
        'serviceType': 'Promob Professional',
        'excelLink': 'book-$failFirst',
        'subTasks': [
          {
            'subId': '2',
            'stage': 'Implantação',
            'planStart': '2026-09-10',
            'planEnd': '2026-12-04',
            'estimatedHours': '40:00'
          }
        ]
      });
      Map<String, dynamic> snapshot() => {
            'revision': revision,
            'entrySheet': 'Informações de entrada',
            'checklistSheet': 'Maker Checklist-Processo',
            'filename': 'Impacto.xlsm',
            'tasks': [],
            'fields': [
              {
                'sheet': 'Maker Checklist-Processo',
                'cell': 'AF7',
                'kind': 'date',
                'stagePeriod': 'Implantação',
                'endpoint': 'start',
                'label': 'Início',
                'group': 'Datas',
                'value': start
              },
              {
                'sheet': 'Maker Checklist-Processo',
                'cell': 'AG7',
                'kind': 'date',
                'stagePeriod': 'Implantação',
                'endpoint': 'end',
                'label': 'Fim',
                'group': 'Datas',
                'value': end
              },
            ],
            'statusPreview': {
              'total': .559375,
              'rows': [
                {
                  'label': 'Implantação',
                  'percentage': .6875,
                  'weight': .45,
                  'start': start,
                  'end': end
                }
              ]
            },
          };
      Widget editor() => MaterialApp(
          home: ProjectSpreadsheetDialog(
        project: project,
        uidProvider: () => 'impacto-$failFirst',
        emailProvider: () => 'rodrigozaparolli79@gmail.com',
        phaseDatesSaver: (jobs) async {
          syncs++;
          order.add('phase');
          expect(writes, 1);
          expect(jobs.single['work'], '2');
          expect(jobs.single['end'], '2026-12-05');
          if (failFirst && syncs == 1) throw StateError('offline');
        },
        transport: (args) async {
          order.add(args['action']);
          if (args['action'] == 'excel-editor-write') {
            writes++;
            final changes = args['changes'] as List;
            expect(changes, hasLength(2));
            start = changes.singleWhere((c) => c['cell'] == 'AF7')['value'];
            end = changes.singleWhere((c) => c['cell'] == 'AG7')['value'];
            expect(start, '2026-09-11');
            expect(end, '2026-12-05');
            revision = 'r2';
            return {...snapshot(), 'saved': true, 'backup': 'backup.xlsm'};
          }
          return {
            ...snapshot(),
            if (args['action'] == 'excel-editor-preview') 'preview': true
          };
        },
      ));
      await tester.pumpWidget(editor());
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Tab).at(1));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds:800));
      await tester.pumpAndSettle();
      final previewsBefore = order.where((a) => a == 'excel-editor-preview').length;
      await tester.tap(find.text('04/12/2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Início: 10/09/2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('11').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(order.where((a) => a == 'excel-editor-preview').length, previewsBefore);
      await tester.tap(find.text('Fim: 04/12/2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aplicar datas'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(order.where((a) => a == 'excel-editor-preview').length, previewsBefore);
      expect(writes, 0);
      await tester.tap(find.text('Aplicar ajustes de datas'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(order.where((a) => a == 'excel-editor-preview').length, previewsBefore + 1);
      await tester.tap(find.text('Salvar na planilha'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(syncs, 1);
      expect(order.indexOf('excel-editor-write'),
          lessThan(order.indexOf('phase')));
      if (failFirst) {
        expect(
            find.textContaining(
                'A planilha foi salva, mas as fases ainda não foram atualizadas.'),
            findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(editor());
        await tester.pumpAndSettle();
        expect(find.text('Sincronizar datas das fases'), findsOneWidget);
        await tester.tap(find.text('Sincronizar datas das fases'));
        await tester.pumpAndSettle();
        expect(syncs, 2);
        expect(writes, 1);
      }
      expect(project.subTasks!.single.planEnd, DateTime(2026, 12, 5));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
