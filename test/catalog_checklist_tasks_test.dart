import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/dialogs/catalog_checklist_tasks.dart';
import 'package:gerenciador_horas/features/projects/dialogs/checklist_percentage_field.dart';

Map<String, dynamic> catalogSnapshot({double value = 0}) => {
      'revision': value == 0 ? 'catalog-v1' : 'catalog-v2',
      'catalogChecklistVersion': 1,
      'checklistSheet': 'Checklist-Catalog',
      'tasks': [
        {
          'sheet': 'Checklist-Catalog',
          'cell': 'E13',
          'label': 'Preparar treinamento',
          'group': 'Treinamento Catalog',
          'kind': 'percent',
          'value': value,
          'estimated': '01:00',
          'note': ''
        },
        {
          'sheet': 'Checklist-Catalog',
          'cell': 'E30',
          'label': 'Conferir acompanhamento',
          'group': 'Acompanhamento',
          'kind': 'percent',
          'value': 1.0,
          'estimated': '01:00',
          'note': ''
        },
      ],
    };

void main() {
  testWidgets('read failure is not displayed as zero tasks', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CatalogChecklistTasks(
      call: (action, {revision, changes}) async =>
          throw StateError('Falha de leitura'),
      allowed: () => true,
      sourceIdentity: 'catalog.xlsm',
      sheet: 'Checklist-Catalog',
      search: '',
      filter: 'Pendentes',
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Treinamento Catalog'), findsOneWidget);
    expect(find.text('Treinamento Catalog · 0 tarefas'), findsNothing);
    expect(find.textContaining('Falha de leitura'), findsOneWidget);
  });
  testWidgets('Catalog respects shared pending/completed filters',
      (tester) async {
    Widget view(String filter) => MaterialApp(
            home: Scaffold(
                body: CatalogChecklistTasks(
          call: (action, {revision, changes}) async => catalogSnapshot(),
          allowed: () => true,
          sourceIdentity: 'training.xlsm',
          sheet: 'Checklist-Catalog',
          search: '',
          filter: filter,
        )));
    await tester.pumpWidget(view('Pendentes'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('catalog-stage-Treinamento Catalog')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('catalog-stage-Acompanhamento')),
        findsNothing);
    await tester.pumpWidget(view('Concluídas'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('catalog-stage-Treinamento Catalog')),
        findsNothing);
    expect(find.byKey(const ValueKey('catalog-stage-Acompanhamento')),
        findsOneWidget);
  });

  testWidgets('Catalog save confirms revision and sends only Catalog task cell',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final writes = <List<Map<String, dynamic>>>[];
    String? savedRevision;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CatalogChecklistTasks(
      call: (action, {revision, changes}) async {
        if (action == 'excel-editor-write') {
          writes.add(changes!);
          savedRevision = revision;
          return {...catalogSnapshot(value: 1), 'saved': true};
        }
        return catalogSnapshot();
      },
      allowed: () => true,
      sourceIdentity: 'catalog-only.xlsm',
      sheet: 'Checklist-Catalog',
      search: '',
      filter: 'Pendentes',
    ))));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('catalog-stage-Treinamento Catalog')));
    await tester.pumpAndSettle();
    final input = find.descendant(
        of: find.byType(ChecklistPercentageInput).first,
        matching: find.byType(TextFormField));
    await tester.enterText(input, '100');
    await tester.tap(find.text('Aplicar ajustes'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    await tester.tap(find.text('Salvar na planilha'));
    await tester.pumpAndSettle();
    expect(savedRevision, 'catalog-v1');
    expect(writes.single, [
      {'sheet': 'Checklist-Catalog', 'cell': 'E13', 'before': 0, 'value': 1.0}
    ]);
    expect(find.byKey(const ValueKey('catalog-stage-Treinamento Catalog')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });
}
