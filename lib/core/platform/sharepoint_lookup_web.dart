import 'dart:convert';
import 'dart:js_interop';

@JS('sharePointResolveNames')
external JSPromise<JSString> _resolve(JSString config);

Future<Map<String, dynamic>> sharePointLookup(
        Map<String, dynamic> config) async =>
    Map<String, dynamic>.from(
        jsonDecode((await _resolve(jsonEncode(config).toJS).toDart).toDart));
