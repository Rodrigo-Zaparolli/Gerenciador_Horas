import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gerenciador_horas/data/services/edesk_integration.dart';
import 'package:gerenciador_horas/data/services/edesk_creation_request.dart';

void main() {
  test('Creation adds official URL without mutating the reviewed fields', () {
    final input = <String, dynamic>{'confirmed': true, 'subject': 'Revisado'};
    expect(edeskCreationRequest(input)['url'], edeskEntryUrl);
    expect(input.containsKey('url'), isFalse);
    final link =
        'https://promob.e-desk.com.br/Portal/Default.aspx?GUID=session';
    expect(edeskCreationRequest({...input, 'url': link})['url'], link);
    expect(edeskCreationRequest({...input, 'url': ' '})['url'], edeskEntryUrl);
  });
  test('Invalid or foreign URLs are refused before sending', () {
    for (final value in [
      'http://promob.e-desk.com.br/',
      'https://other.test/',
      'https://user:pass@promob.e-desk.com.br/',
      'https://promob.e-desk.com.br:8080/',
      123
    ]) {
      expect(() => edeskCreationRequest({'url': value}), throwsFormatException);
    }
  });
  test(
      'Actual HTTP payload supplies URL for ADV, plugin and internal NS routes',
      () async {
    final factory = EdeskIntegrationApi.clientFactory,
        token = EdeskIntegrationApi.tokenProvider;
    addTearDown(() {
      EdeskIntegrationApi.clientFactory = factory;
      EdeskIntegrationApi.tokenProvider = token;
    });
    EdeskIntegrationApi.tokenProvider = () async => 'fixture-token';
    var sends = 0;
    EdeskIntegrationApi.clientFactory = () => MockClient((request) async {
          sends++;
          final body = jsonDecode(request.body) as Map;
          expect(body['request']['url'], edeskEntryUrl);
          expect(body['request']['subject'], 'Revisado');
          expect(body['enviar'], true);
          return http.Response(jsonEncode({'confirmed': true}), 200);
        });
    for (final path in ['/api/edesk/adv', '/api/edesk/ns-interno']) {
      await EdeskIntegrationApi.call(path,
          baseUrl: 'http://127.0.0.1:8765',
          body: {
            'request': {'confirmed': true, 'subject': 'Revisado'},
            'enviar': true
          });
    }
    expect(sends, 2);
    await expectLater(
        EdeskIntegrationApi.call('/api/edesk/adv',
            baseUrl: 'http://127.0.0.1:8765',
            body: {
              'request': {'url': 'https://other.test/'}
            }),
        throwsFormatException);
    expect(sends, 2);
  });
  test('Status and other non-creation requests stay untouched', () {
    final body = {'key': 'value'};
    expect(identical(edeskCreationBody('/api/edesk/status', body), body), true);
    expect(edeskCreationBody('/healthz', null), null);
  });
}
