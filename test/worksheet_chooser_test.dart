import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/dialogs/workbook_sheet_dialog.dart';
import 'package:gerenciador_horas/features/projects/dialogs/spreadsheet_sheet_settings.dart';

void main() {
  testWidgets(
      'chooser lists the workbook first instead of opening a default tab',
      (tester) async {
    final calls = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(
        home: WorkbookSheetDialog(
      projectId: 'test',
      chooser: true,
      initialWorksheet: 'Consultorias',
      allowed: () => true,
      mappedWorksheets: const {'Entrada real'},
      onMappedWorksheet: (_) async {},
      call: (args) async {
        calls.add(args);
        if (args['action'] == 'excel-editor-sheets')
          return {
            'sheetNames': ['Entrada real', 'Notas']
          };
        return {...args, 'revision': 'r', 'fields': <Map<String, dynamic>>[]};
      },
    )));
    await tester.pumpAndSettle();
    expect(calls.map((c) => c['action']), ['excel-editor-sheets']);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('Consultorias'), findsNothing);
    await tester.tap(find.text('Notas').last);
    await tester.pumpAndSettle();
    expect(calls.last['worksheet'], 'Notas');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'model settings show only role candidates present in this workbook',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                    body: TextButton(
                  child: const Text('Open'),
                  onPressed: () => selectSpreadsheetSheets(
                      context,
                      ['Entrada real', 'Maker real', 'Notas'],
                      {
                        'entry': 'Outra planilha',
                        'checklist': 'Professional inexistente'
                      },
                      candidates: {
                        'entry': ['Entrada real', 'Aba fantasma'],
                        'checklist': ['Maker real']
                      },
                      filename: 'Impacto.xlsm'),
                )))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Arquivo: Impacto.xlsm'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    expect(find.text('Maker real'), findsOneWidget);
    for (final absent in [
      'Notas',
      'Entrada real',
      'Aba fantasma',
      'Professional inexistente'
    ]) {
      expect(find.text(absent), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });
}
