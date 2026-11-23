const edeskEntryUrl = 'https://promob.e-desk.com.br/';

/// Shared contract for workflows that start a new request/work browser session.
Map<String, dynamic> edeskCreationRequest(Map<String, dynamic> data) {
  final raw = data['url'];
  if (raw != null && raw is! String) {
    throw const FormatException('O endereço de abertura do E-Desk é inválido.');
  }
  final text = (raw as String?)?.trim() ?? '';
  final url = text.isEmpty ? edeskEntryUrl : text;
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'promob.e-desk.com.br' ||
      uri.port != 443 ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException(
        'Use o endereço oficial do E-Desk para criar solicitações e trabalhos.');
  }
  return {...data, 'url': url};
}

Map<String, dynamic>? edeskCreationBody(
    String path, Map<String, dynamic>? body) {
  if (!const {'/api/edesk/adv', '/api/edesk/ns-interno'}.contains(path))
    return body;
  final request = body?['request'];
  if (request is! Map<String, dynamic>) {
    throw const FormatException(
        'Os dados da solicitação não foram preparados.');
  }
  return {...body!, 'request': edeskCreationRequest(request)};
}
