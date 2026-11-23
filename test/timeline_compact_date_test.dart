import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/projects/dialogs/project_documents_dialog.dart';

void main() {
  testWidgets(
      'Compact table stages date edits in C without writing on calendar selection',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(
        home: ProjectDocumentsDialog(
            project: ProjectModel.fromJson(
                {'id': '2267266', 'client': 'Rennova', 'excelLink': 'local'}),
            uidProvider: () => 'owner',
            transport: (args) async {
              requests.add(args);
              return {
                'revision': 'r1',
                'columns': [
                  for (var c = 0; c < 8; c++)
                    {
                      'letter': String.fromCharCode(65 + c),
                      'label': 'Coluna',
                      'width': 400
                    }
                ],
                'rows': [
                  {
                    'row': 19,
                    'date': '2026-11-16',
                    'cells': [
                      1,
                      'Contrato',
                      '16/11/2026 seg',
                      'Descrição',
                      'Ambos',
                      '',
                      '',
                      1
                    ]
                  },
                  {
                    'row': 20,
                    'date': '2026-11-17',
                    'cells': [
                      2,
                      'Contato',
                      '17/11/2026 ter',
                      'Descrição',
                      'Promob',
                      'Contato',
                      '',
                      2
                    ]
                  }
                ],
                'fields': [
                  {
                    'sheet': 'Implantação - Linha do Tempo',
                    'cell': 'H19',
                    'kind': 'number',
                    'timelineDays': true,
                    'readOnly': false,
                    'value': 1
                  },
                  {
                    'sheet': 'Implantação - Linha do Tempo',
                    'cell': 'C20',
                    'kind': 'date',
                    'readOnly': true,
                    'timelineDateEditable': true,
                    'value': '2026-11-17',
                    'dateDriver': {
                      'sheet': 'Implantação - Linha do Tempo',
                      'cell': 'H19',
                      'previousDate': 'C19'
                    }
                  }
                ]
              };
            })));
    await tester.pumpAndSettle();
    final table = tester.widget<DataTable>(find.byType(DataTable));
    expect(table.dataRowMaxHeight, 80);
    expect(table.columnSpacing, 8);
    expect(table.columns, hasLength(9));
    expect(find.text('Outlook'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextFormField, '17/11/2026'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('18').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, '18/11/2026'), findsOneWidget);
    expect(requests.every((r) => r['operation'] == 'timeline-read'), isTrue);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Salvar na planilha'))
            .onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
