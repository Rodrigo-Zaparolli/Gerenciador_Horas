import 'dart:typed_data';

Future<EdeskPythonResult> executarPythonEdesk({
  required String requestJson,
  required bool enviar,
}) async {
  return EdeskPythonResult(
    confirmed: false,
    statusCode: 0,
    message:
        'A integração Python/E-Desk está disponível somente no aplicativo Windows.',
    responseBody: '',
  );
}

class EdeskPythonResult {
  final bool confirmed;
  final int statusCode;
  final String message;
  final String responseBody;

  const EdeskPythonResult({
    required this.confirmed,
    required this.statusCode,
    required this.message,
    required this.responseBody,
  });
}
