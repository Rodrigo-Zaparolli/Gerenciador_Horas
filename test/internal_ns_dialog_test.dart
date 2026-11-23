import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/edesk/internal_ns_dialog.dart';

void main() {
  testWidgets(
      'Documentation fields stay editable and require attachment before sending',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sent = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: InternalNsDialog(
                documentation: true,
                authorized: () => true,
                sender: (data) async {
                  sent.add(data);
                  return {
                    'confirmed': true,
                    'message': 'Documentação confirmada'
                  };
                }))));
    expect(find.text('Documentação de plugin'), findsOneWidget);
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(7));
    await tester.enterText(fields.at(2), 'Documentação Plugins');
    await tester.enterText(fields.at(5), 'Documentação Plugin Router');
    await tester.enterText(
        fields.at(6), 'Extensão: nc. Características: Furos');
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Criar solicitação no E-Desk'));
    await tester.pumpAndSettle();
    expect(sent, isEmpty);
    expect(find.text('Selecione o arquivo que deseja anexar.'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Criar solicitação no E-Desk'));
    await tester.pumpAndSettle();
    expect(sent.single['kind'], 'plugin-documentation');
    expect(sent.single['process'], 'Documentação Plugins');
    expect(sent.single['group'], 'Documentação');
    expect(sent.single['classification'], '');
    expect(sent.single['urgency'], 'Normal');
    expect(sent.single['subject'], 'Documentação Plugin Router');
    expect(sent.single['url'], internalNsEntryUrl);
    await tester.pumpWidget(const SizedBox());
  });
  test(
      'Internal NS request carries the official URL required by Python startup',
      () {
    final request = internalNsRequest(
        operationId: 'a' * 32,
        subject: ' NS interno ',
        description: ' Pedido revisado ');
    expect(request['url'], 'https://promob.e-desk.com.br/');
    expect(Uri.parse(request['url'] as String).host, 'promob.e-desk.com.br');
    expect(request['operationId'], 'a' * 32);
    expect(request['subject'], 'NS interno');
    expect(request['description'], 'Pedido revisado');
    expect(request['confirmed'], true);
  });
  testWidgets(
      'Internal NS requires reviewed editable text and creates only once',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final receipt = Completer<Map<String, dynamic>>();
    var sends = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: InternalNsDialog(
                authorized: () => true,
                sender: (data) async {
                  sends++;
                  expect(data['url'], internalNsEntryUrl);
                  expect(data['subject'], 'NS para uso interno - Router');
                  expect(data['description'],
                      'Solicito NS Plugin Router para uso interno.');
                  expect(data['confirmed'], true);
                  expect(
                      data['operationId'], matches(RegExp(r'^[0-9a-f]{32}$')));
                  return receipt.future;
                }))));
    expect(find.textContaining('Grupo de Serviço: Sales OPS'), findsOneWidget);
    await tester.tap(find.text('Criar solicitação no E-Desk'));
    await tester.pumpAndSettle();
    expect(sends, 0);
    expect(find.text('Informe o detalhamento.'), findsOneWidget);
    await tester.enterText(
        find.byType(TextFormField).first, 'NS para uso interno - Router');
    await tester.enterText(find.byType(TextFormField).last,
        'Solicito NS Plugin Router para uso interno.');
    await tester.tap(find.text('Criar solicitação no E-Desk'));
    await tester.pump();
    expect(sends, 1);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    receipt.complete(
        {'confirmed': true, 'message': 'Solicitação 2267999 confirmada.'});
    await tester.pumpAndSettle();
    expect(find.text('Solicitação 2267999 confirmada.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
