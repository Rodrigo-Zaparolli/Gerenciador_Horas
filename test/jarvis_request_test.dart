import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/jarvis/jarvis_request.dart';

void main() {
  final now=DateTime.utc(2026,10,29,12);
  Map<String,dynamic> valid() => {'version':1,'id':'a'*32,'created':now.toIso8601String(),'action':'hours','project':'Café','body':'Revisão','start':'09:00','end':'11:00','date':'29/10/2026'};
  test('preserves accents and structured fields',() {
    final request=JarvisRequest.parse(jsonEncode(valid()),now:now);
    expect(request.project,'Café');expect(request.body,'Revisão');expect(request.start,'09:00');
  });
  test('rejects expired and future requests',() {
    for(final created in [now.subtract(const Duration(minutes:12)),now.add(const Duration(minutes:3))]) {
      expect(() => JarvisRequest.parse(jsonEncode({...valid(),'created':created.toIso8601String()}),now:now),throwsFormatException);
    }
  });
  test('rejects arbitrary actions, identifiers, types and oversized bodies',() {
    for(final change in [{'action':'delete'},{'id':'../../outside'},{'project':123},{'body':'x'*3001},{'version':2}]) {
      expect(() => JarvisRequest.parse(jsonEncode({...valid(),...change}),now:now),throwsFormatException);
    }
  });
}
