import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/projects/dialogs/project_spreadsheet_dialog.dart';
import 'package:gerenciador_horas/features/projects/dialogs/project_worksheet_preference.dart';
import 'package:gerenciador_horas/features/projects/dialogs/catalog_worksheet_roles.dart';
import 'catalog_checklist_tasks_test.dart' as catalog;
import 'project_spreadsheet_dialog_test.dart' as primary;
import 'spreadsheet_sheet_settings_test.dart' show MemorySettings;

void main() {
  test('Catalog guide returns to the existing checklist without creating tabs',
      () {
    expect(mappedWorksheetTab('Cronograma Treinamento Catalog'), 1);
    expect(mappedWorksheetTab('Checklist-Catalog'), 1);
    const settings = {
      'catalogEnabled': 'true',
      'catalogSource': 'main',
      'catalogSheet': 'Cronograma Treinamento Catalog'
    };
    expect(configuredCatalogGuides(settings),
        containsAll(['Checklist-Catalog', 'Cronograma Treinamento Catalog']));
    expect(configuredCatalogGuides({...settings, 'catalogSource': 'external'}),
        isEmpty);
  });

  testWidgets(
      'combined checklist fixes legacy schedule mapping and shows both task sources',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = MemorySettings();
    settings.values['owner/project'] = {
      'entry': 'Informações de entrada',
      'checklist': 'Checklist-Processo',
      'catalogEnabled': 'true',
      'catalogSource': 'main',
      'catalogSheet': 'Cronograma Treinamento Catalog',
      'catalogChecklistSheet': 'Cronograma Treinamento Catalog',
      'catalogRange': 'B34:I38',
    };
    final project = ProjectModel.fromJson({
      'id': 'project',
      'serviceType': 'Enterprise',
      'excelLink': 'enterprise.xlsm'
    });
    final requests = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(
        home: ProjectSpreadsheetDialog(
      project: project,
      initialTab: 1,
      uidProvider: () => 'owner',
      emailProvider: () => 'rodrigozaparolli79@gmail.com',
      sheetSettingsStore: settings,
      transport: (args) async {
        requests.add(args);
        if (args['action'] == 'preview')
          return {
            'renderer': 'excel',
            'imagemBase64':
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII='
          };
        if (args['action'] == 'excel-editor-sheets')
          return {
            'sheetNames': [
              'Informações de entrada',
              'Checklist-Processo',
              'Cronograma Treinamento Catalog',
              'Checklist-Catalog'
            ]
          };
        if (args['serviceType'] == 'catalog-checklist') {
          expect((args['sheetNames'] as Map)['checklist'], 'Checklist-Catalog');
          return catalog.catalogSnapshot();
        }
        return {
          ...primary.snapshot(),
          'entrySheet': 'Informações de entrada',
          'checklistSheet': 'Checklist-Processo',
          if (args['action'] == 'excel-editor-preview') 'preview': true,
          'statusPreview': {'total': .5, 'rows': <Map<String, dynamic>>[]}
        };
      },
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('checklist-stage-Implantação')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('catalog-stage-Treinamento Catalog')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('catalog-stage-Acompanhamento')),
        findsOneWidget);
    expect(tester.widget<TabBar>(find.byType(TabBar)).tabs.length, 3);
    expect(project.excelLink, 'enterprise.xlsm');
    await tester.tap(find.text('Escolher guia'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cronograma Treinamento Catalog').last);
    await tester.pumpAndSettle();
    expect(
        requests
            .where((r) => r['worksheet'] == 'Cronograma Treinamento Catalog'),
        isEmpty);
    expect(find.text('Guia do Excel'), findsNothing);
    expect(
        find.byKey(const ValueKey('catalog-checklist-tasks')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
