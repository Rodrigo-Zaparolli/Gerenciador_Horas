import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/edesk/received_work_comparison.dart';
import 'package:gerenciador_horas/features/edesk/received_work_dialog.dart';
import 'received_work_store_test.dart' show ImportAuth;

ProjectModel project(String request, List<String> works) =>
    ProjectModel.fromJson({
      'id': request,
      'id2': '0',
      'client': 'Cliente',
      'subTasks': [
        for (final work in works)
          {'subId': work, 'stage': 'Etapa', 'estimatedHours': '01:00'},
      ]
    });

void main() {
  testWidgets(
      'Sol. request-only grid distinguishes an existing request from an absent project',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ReceivedWorkDialog(
      auth: ImportAuth(),
      loadInventory: () async => ReceivedInventory(active: [
        project('2261345', ['3'])
      ]),
      query: (_, __) async => {
        'complete': true,
        'referenceLevel': 'request',
        'rows': [
          {'solicitacao': '2261345', 'client': 'Cliente A'},
          {'solicitacao': '2246969', 'client': 'Cliente B'},
        ]
      },
    ))));
    await tester.tap(find.text('Buscar na Minha Grid'));
    await tester.pumpAndSettle();
    expect(find.text('Solicitação cadastrada'), findsOneWidget);
    expect(find.text('Falta no sistema'), findsOneWidget);
    expect(find.text('Já cadastrado'), findsNothing);
    expect(find.textContaining('Busca parcial:'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test(
      'matches both request and work, and identifies a missing step in an existing project',
      () {
    final inventory = ReceivedInventory(active: [
      project('2266963', ['3']),
      project('2266488', ['4'])
    ]);
    expect(
        compareReceivedWork(
                {'solicitacao': '2266963', 'idTrabalho': '3'}, inventory)
            .state,
        'registered');
    expect(
        compareReceivedWork(
                {'solicitacao': '2266963', 'idTrabalho': '4'}, inventory)
            .state,
        'missingWork');
    expect(
        compareReceivedWork(
                {'solicitacao': '9999999', 'idTrabalho': '3'}, inventory)
            .state,
        'missingProject');
  });
  test('includes completed projects and never calls an unknown link registered',
      () {
    final inventory = ReceivedInventory(active: [
      project('2266963', [])
    ], completed: [
      project('2266488', ['4'])
    ]);
    expect(
        compareReceivedWork(
                {'solicitacao': '2266488', 'idTrabalho': '4'}, inventory)
            .state,
        'completed');
    expect(
        compareReceivedWork(
                {'solicitacao': '2266488', 'idTrabalho': '5'}, inventory)
            .state,
        'review');
    expect(
        compareReceivedWork(
                {'solicitacao': '2266963', 'idTrabalho': '3'}, inventory)
            .state,
        'review');
    expect(compareReceivedWork({'solicitacao': '2266963'}, inventory).state,
        'requestRegistered');
  });
  test('uses each task request and legacy real work ID instead of stage names',
      () {
    final p = project('2266963', []);
    p.subTasks = [
      TaskModel.fromJson({
        'subId': 'old-key',
        'edeskIdTrabalho': '9',
        'edeskSolicitacao': '2266488'
      })
    ];
    final inventory = ReceivedInventory(active: [p]);
    expect(
        compareReceivedWork(
                {'solicitacao': '2266488', 'idTrabalho': '9'}, inventory)
            .state,
        'registered');
    expect(
        compareReceivedWork(
                {'solicitacao': '2266963', 'idTrabalho': '9'}, inventory)
            .state,
        'review');
  });
  testWidgets(
      'lists every grid work separately, marks missing and registered, and filters missing only',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var imports = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ReceivedWorkDialog(
      auth: ImportAuth(),
      loadInventory: () async => ReceivedInventory(active: [
        project('2266963', ['3'])
      ]),
      importProject: (_) async {
        imports++;
        return 1;
      },
      query: (script, data) async => {
        'complete': true,
        'rows': [
          {
            'solicitacao': '2266963',
            'idTrabalho': '3',
            'client': 'Cliente',
            'name': 'Implantação'
          },
          {
            'solicitacao': '2266963',
            'idTrabalho': '4',
            'client': 'Cliente',
            'name': 'Pós-Implantação'
          },
        ]
      },
    ))));
    await tester.tap(find.text('Buscar na Minha Grid'));
    await tester.pumpAndSettle();
    expect(find.text('2266963 / 3'), findsOneWidget);
    expect(find.text('2266963 / 4'), findsOneWidget);
    expect(find.text('Já cadastrado'), findsOneWidget);
    expect(find.text('Falta no sistema'), findsOneWidget);
    await tester.tap(find.text('Faltam no sistema (1)'));
    await tester.pumpAndSettle();
    expect(find.text('2266963 / 3'), findsNothing);
    expect(find.text('2266963 / 4'), findsOneWidget);
    expect(imports, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('inventory failure never reports existing works as missing',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ReceivedWorkDialog(
      auth: ImportAuth(),
      loadInventory: () async => throw StateError('offline'),
      query: (_, __) async => {
        'complete': true,
        'rows': [
          {'solicitacao': '2266963', 'idTrabalho': '3'}
        ]
      },
    ))));
    await tester.tap(find.text('Buscar na Minha Grid'));
    await tester.pumpAndSettle();
    expect(find.text('Falta no sistema'), findsNothing);
    expect(find.text('Precisa conferir'), findsOneWidget);
    expect(
        find.textContaining('A comparação não foi concluída.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
