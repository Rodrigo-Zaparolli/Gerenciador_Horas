import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/dialogs/catalog_panel_settings.dart';
import 'package:gerenciador_horas/features/projects/dialogs/catalog_training_panel.dart';
import 'package:gerenciador_horas/features/projects/dialogs/spreadsheet_sheet_settings.dart';
import 'package:gerenciador_horas/features/projects/dialogs/catalog_worksheet_roles.dart';

void main() {
  test('schedule cannot be mistaken for the Catalog task worksheet', () {
    expect(
        catalogChecklistSheet({
          'catalogSheet': 'Cronograma Treinamento Catalog',
          'catalogChecklistSheet': 'Cronograma Treinamento Catalog'
        }),
        'Checklist-Catalog');
    expect(
        catalogChecklistOptions([
          'Cronograma Treinamento Catalog',
          'Checklist-Processo',
          'Checklist-Catalog'
        ]),
        ['Checklist-Catalog']);
    expect(
        catalogChecklistSheet(
            {'catalogChecklistSheet': 'Checklist Catalog Cliente'}),
        'Checklist Catalog Cliente');
  });
  test('catalog range rejects reversed, excessive and invalid ranges', () {
    expect(validCatalogRange('B34:I38'), isTrue);
    for (final value in ['I38:B34', 'A0:B4', 'A1:XFD100', 'A1', 'XFE1:XFE2']) {
      expect(validCatalogRange(value), isFalse);
    }
  });
  testWidgets(
      'external workbook lists its own sheets and preserves main selections',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, String>? saved;
    final references = <String?>[];
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () async {
                  saved = await selectSpreadsheetSheets(
                      context,
                      ['Entrada', 'Checklist'],
                      {
                        'entry': 'Entrada',
                        'checklist': 'Checklist',
                        'catalogEnabled': 'true',
                        'catalogSource': 'external',
                        'catalogReference': 'catalog.xlsm',
                        'catalogSheet': 'Cronograma Treinamento Catalog',
                        'catalogChecklistSheet':
                            'Cronograma Treinamento Catalog',
                        'catalogRange': 'B34:I38',
                      },
                      mainReference: 'enterprise.xlsm',
                      catalogRequest: (action, {reference}) async {
                    references.add(reference);
                    return {
                      'sheetNames': [
                        'Cronograma Treinamento Catalog',
                        'Checklist-Catalog'
                      ]
                    };
                  });
                },
                child: const Text('Abrir')))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(references, ['catalog.xlsm']);
    await tester.ensureVisible(find.text('Usar estas abas'));
    await tester.tap(find.text('Usar estas abas'));
    await tester.pumpAndSettle();
    expect(saved?['entry'], 'Entrada');
    expect(saved?['checklist'], 'Checklist');
    expect(saved?['catalogReference'], 'catalog.xlsm');
    expect(saved?['catalogSheet'], 'Cronograma Treinamento Catalog');
    expect(saved?['catalogChecklistSheet'], 'Checklist-Catalog');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'catalog panel requests original range from separate workbook without writes',
      (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CatalogTrainingPanel(
      reference: 'training.xlsm',
      sheet: 'Cronograma Treinamento Catalog',
      range: 'B34:I38',
      request: (action, {reference, name, range}) async {
        calls.add('$action|$reference|$range');
        return {
          'renderer': 'excel',
          'imagemBase64': base64Encode(base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII='))
        };
      },
    ))));
    await tester.pumpAndSettle();
    expect(calls,
        ["preview|training.xlsm|'Cronograma Treinamento Catalog'!B34:I38"]);
    expect(find.text('Treinamento Catalog'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
