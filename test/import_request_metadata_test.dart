import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/edesk/received_work_dialog.dart';
import 'received_work_store_test.dart' show ImportAuth;
import 'package:gerenciador_horas/features/edesk/received_work.dart';
import 'package:gerenciador_horas/domain/models/work_format_model.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';

void main() {
  testWidgets('2266963 selects configured plugin service from work 3', (tester) async {
    tester.view.physicalSize = const Size(1300, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final plugin = WorkFormat(id: 'plugin', name: 'Implantação Plugin (OH)',
        steps: ['Implantação Plugin']);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ReceivedWorkReview(
      auth: ImportAuth(),
      existing: ProjectModel(id: '2266963', id2: '', client: 'PROMAD COMERCIO LTDA',
          serviceType: 'Tipo antigo', leader: 'Flavia Martinelli', stage: '',
          task: '', status: 'INI_PRO', startDate: DateTime(2026, 11, 9),
          estimatedHours: '00:00', hourType: 'Hs Cobradas'),
      summary: const {'solicitacao': '2266963'},
      details: const [{
        'solicitacao': '2266963', 'idTrabalho': '3',
        'values': {'name': 'Implantação Plugin (OH)', 'estimatedHours': '07:30',
          'requestClient': 'PROMAD COMERCIO LTDA', 'requestLeader': 'Flavia Martinelli'},
      }],
      types: [plugin.name], formats: [plugin,
        WorkFormat(id: 'alternative', name: 'Implantação de Plugins',
            steps: ['Implantação Plugin'])],
    ))));
    await tester.pumpAndSettle();
    final field = tester.widget<DropdownButtonFormField<WorkFormat>>(
        find.byKey(const ValueKey('import-service-type')));
    expect(field.initialValue, same(plugin));
    expect(find.text('3 · Implantação Plugin (OH)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test('service matches work types and unique stage sets without using title', () {
    final plugin = WorkFormat(id: 'p', name: 'Implantação de Plugins');
    expect(receivedFormatForWorks(['Implantação Plugin (OH)'], [plugin]), same(plugin));
    final professional = WorkFormat(id: 'pro', name: 'Professional',
        steps: ['Contato Inicial', 'Implantação', 'Pós-Implantação']);
    expect(receivedFormatForWorks(['Contato Inicial (OH)', 'Implantação (OH)',
        'Pós-Implantação (OH)'], [professional]), same(professional));
    final enterprise = WorkFormat(id: 'ent', name: 'Enterprise',
        steps: ['Contato Inicial', 'Implantação', 'Pós-Implantação', 'Desenvolvimento']);
    expect(receivedFormatForWorks(['Contato Inicial', 'Implantação',
        'Pós-Implantação'], [professional, enterprise]), isNull);
    expect(receivedFormatForWorks(['Desconhecido'], [plugin, professional]), isNull);
  });
  testWidgets('request company and responsible prefill the editable import fields', (tester) async {
    tester.view.physicalSize = const Size(1300, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ReceivedWorkReview(
      auth: ImportAuth(),
      summary: const {'solicitacao': '2266963', 'client': 'Old summary', 'leader': 'Work attendant'},
      details: const [{
        'solicitacao': '2266963', 'idTrabalho': '3',
        'values': {
          'requestClient': 'PROMAD COMERCIO LTDA', 'requestLeader': 'Flavia Martinelli',
          'client': 'Other client', 'leader': 'Rodrigo Zaparolli',
          'name': 'Implantação Plugin (OH)', 'estimatedHours': '07:30',
          'serviceType': 'Enterprise',
        },
      }],
      types: const ['Implantação Plugin'],
    ))));
    await tester.pumpAndSettle();
    final client = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Cliente *');
    final leader = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Líder *');
    expect(tester.widget<TextField>(client).controller!.text, 'PROMAD COMERCIO LTDA');
    expect(tester.widget<TextField>(leader).controller!.text, 'Flavia Martinelli');
    final service = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Tipo de serviço *');
    expect(tester.widget<TextField>(service).controller!.text, 'Implantação Plugin');
    await tester.enterText(client, 'Cliente revisado');
    await tester.enterText(leader, 'Responsável revisado');
    expect(tester.widget<TextField>(client).controller!.text, 'Cliente revisado');
    expect(tester.widget<TextField>(leader).controller!.text, 'Responsável revisado');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
