import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/zendesk/zendesk_dialog.dart';

const png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
Map<String, dynamic> metadata() => {
      'agent': {'id': 7, 'name': 'Consultor'},
      'brands': [
        {'id': 1, 'name': 'Promob'}
      ],
      'forms': [
        {'id': 2, 'name': 'Support Promob Manufacturing', 'fieldIds': []}
      ],
      'groups': [],
      'fields': [],
      'customStatuses': [{'id': 22, 'name': 'On-hold · R&D', 'category': 'hold'}]
    };

void main() {
  testWidgets(
      'Official capture precedes explicit ticket confirmation; changed answers invalidate print',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <String>[];
    var creates = 0, saves = 0;
    await tester.pumpWidget(MaterialApp(
        home: ZendeskDialog(
            project: ProjectModel.fromJson({'id': '123', 'client': 'Cliente'}),
            authorized: () => true,
            receiptSaver: (_) async {
              saves++;
            },
            transport: (action, data) async {
              calls.add(action);
              if (action == 'connect') return metadata();
              if (action == 'capture')
                return {
                  'draftId': 'a' * 32,
                  'priority': 'P3',
                  'points': 24,
                  'forecast': '',
                  'imageBase64': png
                };
              if (action == 'create') {
                creates++;
                expect(data['confirmed'], true);
                expect(data['agentId'], 7);
                expect(data['status'], 22);
                expect(data['sla']['answers'], [3, 1, 3, 3, 3]);
                return {
                  'state': 'confirmed',
                  'ticketId': 456,
                  'url':
                      'https://compusoftgrouphelp.zendesk.com/agent/tickets/456',
                  'draftId': 'a' * 32,
                  'priority': 'P3',
                  'slaRegistered': false
                };
              }
              throw StateError('Unexpected $action');
            })));
    await tester.tap(find.text('Conectar Zendesk'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      tester
          .widget<DropdownButtonFormField<int>>(
              find.byKey(ValueKey('sla-answer-$i')))
          .onChanged!([3, 1, 3, 3, 3][i]);
      await tester.pump();
    }
    await tester.ensureVisible(find.text('Capturar priorização'));
    await tester.tap(find.text('Capturar priorização'));
    await tester.pumpAndSettle();
    expect(calls, ['connect', 'capture']);
    expect(creates, 0);
    expect(find.byType(Image), findsOneWidget);
    tester
        .widget<DropdownButtonFormField<int>>(
            find.byKey(const ValueKey('sla-answer-0')))
        .onChanged!(4);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    tester
        .widget<DropdownButtonFormField<int>>(
            find.byKey(const ValueKey('sla-answer-0')))
        .onChanged!(3);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Capturar priorização'));
    await tester.tap(find.text('Capturar priorização'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conferir e criar chamado'));
    await tester.pumpAndSettle();
    expect(creates, 0);
    await tester.tap(find.text('Confirmar criação'));
    await tester.pumpAndSettle();
    expect(creates, 1);
    expect(saves, 1);
    expect(find.text('Chamado 456 criado e conferido'), findsOneWidget);
    expect(find.text('Conferir e criar chamado'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Account change after capture prevents further operations',
      (tester) async {
    var allowed = true;
    var captures = 0;
    await tester.pumpWidget(MaterialApp(
        home: ZendeskDialog(
            project: ProjectModel.fromJson({'id': '1', 'client': 'C'}),
            authorized: () => allowed,
            transport: (action, data) async {
              captures++;
              allowed = false;
              return metadata();
            })));
    await tester.tap(find.text('Conectar Zendesk'));
    await tester.pumpAndSettle();
    expect(captures, 1);
    expect(find.text('A conta mudou. Feche e abra esta janela novamente.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
