import 'dart:convert';
import 'package:http/http.dart' as http;

/// Dados necessários para registrar um trabalho no E-Desk.
class EdeskWorkData {
  final Uri pageUri;
  final String solicitacao;
  final String idTrabalho;
  final String data;
  final String horaInicio;
  final String horaFim;
  final String tipoRegistro;
  final String tarefa;
  final String descricao;
  final String? gtt;
  final String? equipamento;
  final String? atendimento;
  final String? motivo;

  const EdeskWorkData({
    required this.pageUri,
    required this.solicitacao,
    required this.idTrabalho,
    required this.data,
    required this.horaInicio,
    required this.horaFim,
    required this.tipoRegistro,
    required this.tarefa,
    required this.descricao,
    this.gtt,
    this.equipamento,
    this.atendimento,
    this.motivo,
  });
}

/// Resultado da tentativa de envio para o E-Desk.
class EdeskSendResult {
  final bool confirmed;
  final int statusCode;
  final String message;
  final String responseBody;

  const EdeskSendResult({
    required this.confirmed,
    required this.statusCode,
    required this.message,
    required this.responseBody,
  });
}

/// Serviço de comunicação com o E-Desk.
class EdeskService {
  EdeskService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Cookies da sessão atual.
  final Map<String, String> _cookies = {};

  /// Retorna os cookies atuais sem permitir alteração externa.
  Map<String, String> get cookies => Map.unmodifiable(_cookies);

  /// Define os cookies de uma sessão já autenticada.
  void setSessionCookies(
    Map<String, String> cookies,
  ) {
    _cookies
      ..clear()
      ..addAll(cookies);
  }

  /// Limpa a sessão atual.
  void clearSession() {
    _cookies.clear();
  }

  /// Envia um trabalho para o E-Desk.
  Future<EdeskSendResult> sendWork(
    EdeskWorkData work,
  ) async {
    // ==========================================================
    // 1. ABRIR A PÁGINA DO TRABALHO
    // ==========================================================

    final getResponse = await _client.get(
      work.pageUri,
      headers: _headers(),
    );

    _storeCookies(getResponse);

    if (getResponse.statusCode != 200) {
      throw EdeskException(
        'Não foi possível abrir a página do E-Desk. '
        'HTTP ${getResponse.statusCode}.',
      );
    }

    final html = utf8.decode(
      getResponse.bodyBytes,
      allowMalformed: true,
    );

    // ==========================================================
    // 2. EXTRAIR CAMPOS HIDDEN DO ASP.NET WEB FORMS
    // ==========================================================

    final hiddenFields = _extractHiddenFields(html);

    if (hiddenFields.isEmpty) {
      throw const EdeskAuthenticationException(
        'A página do E-Desk não retornou os campos '
        'de estado. A sessão pode não estar autenticada.',
      );
    }

    final form = <String, String>{
      ...hiddenFields,
    };

    // ==========================================================
    // 3. CAMPOS DO TRABALHO
    // ==========================================================

    form[r'ctl00$cph1$txtDatTem'] = work.data;
    form[r'ctl00$cph1$txtHorIni'] = work.horaInicio;
    form[r'ctl00$cph1$txtHorFin'] = work.horaFim;
    form[r'ctl00$cph1$ddlTipReg'] = work.tipoRegistro;
    form[r'ctl00$cph1$txlTtr$txtDes'] = work.tarefa;
    form[r'ctl00$cph1$txtDet'] = work.descricao;

    if (work.gtt != null) {
      form[r'ctl00$cph1$txlGtt$txtDes'] = work.gtt!;
    }

    if (work.equipamento != null) {
      form[r'ctl00$cph1$txlEqt$txtDes'] = work.equipamento!;
    }

    if (work.atendimento != null) {
      form[r'ctl00$cph1$txlAte$txtDes'] = work.atendimento!;
    }

    if (work.motivo != null) {
      form[r'ctl00$cph1$txtRea'] = work.motivo!;
    }

    // ==========================================================
    // 4. CONFIGURAÇÃO DO ASP.NET AJAX / UPDATEPANEL
    // ==========================================================

    form[r'ctl00$scmF'] = r'ctl00$cph1$uppG|ctl00$cph1$BtAtu';
    form['__EVENTTARGET'] = '';
    form['__EVENTARGUMENT'] = '';
    form['__ASYNCPOST'] = 'true';

    // Configurando o disparador do evento de clique do UpdatePanel
    form[r'ctl00$cph1$BtAtu'] = 'Salvar';

    // ==========================================================
    // 5. ENVIAR POST
    // ==========================================================

    final postResponse = await _client.post(
      work.pageUri,
      headers: {
        ..._headers(),
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'Referer': work.pageUri.toString(),
        'X-Requested-With': 'XMLHttpRequest',
      },
      body: form,
    );

    _storeCookies(postResponse);

    // ==========================================================
    // 6. ANALISAR RESPOSTA
    // ==========================================================

    final body = utf8.decode(
      postResponse.bodyBytes,
      allowMalformed: true,
    );

    final confirmed = postResponse.statusCode >= 200 &&
        postResponse.statusCode < 300 &&
        !_containsError(body);

    return EdeskSendResult(
      confirmed: confirmed,
      statusCode: postResponse.statusCode,
      message: confirmed
          ? 'O E-Desk aceitou a solicitação HTTP.'
          : 'O E-Desk retornou uma resposta que não pôde ser confirmada como gravação.',
      responseBody: body,
    );
  }

  // ============================================================
  // HEADERS
  // ============================================================

  Map<String, String> _headers() {
    return {
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      if (_cookies.isNotEmpty) 'Cookie': _cookieHeader(),
    };
  }

  // ============================================================
  // COOKIE HEADER
  // ============================================================

  String _cookieHeader() {
    return _cookies.entries
        .map(
          (entry) => '${entry.key}=${entry.value}',
        )
        .join('; ');
  }

  // ============================================================
  // ARMAZENAR COOKIES
  // ============================================================

  void _storeCookies(
    http.Response response,
  ) {
    final values = response.headers['set-cookie'];

    if (values == null || values.isEmpty) {
      return;
    }

    final cookies = values.split(
      RegExp(
        r',(?=\s*[^;,=]+\s*=)',
      ),
    );

    for (final cookie in cookies) {
      final firstPart = cookie.split(';').first.trim();

      final separator = firstPart.indexOf('=');

      if (separator <= 0) {
        continue;
      }

      final name = firstPart.substring(0, separator).trim();

      final value = firstPart.substring(separator + 1).trim();

      if (name.isNotEmpty) {
        _cookies[name] = value;
      }
    }
  }

  // ============================================================
// EXTRAIR CAMPOS HIDDEN
// ============================================================

  Map<String, String> _extractHiddenFields(
    String html,
  ) {
    final fields = <String, String>{};

    final inputPattern = RegExp(
      r'''<input[^>]*type\s*=\s*["']hidden["'][^>]*>''',
      caseSensitive: false,
      dotAll: true,
    );

    for (final match in inputPattern.allMatches(html)) {
      final tag = match.group(0);

      if (tag == null) {
        continue;
      }

      final name = _attribute(tag, 'name');

      if (name == null || name.isEmpty) {
        continue;
      }

      fields[name] = _attribute(tag, 'value') ?? '';
    }

    return fields;
  }

// ============================================================
// LER ATRIBUTO HTML
// ============================================================

  String? _attribute(
    String tag,
    String attributeName,
  ) {
    final pattern = RegExp(
      '''$attributeName\\s*=\\s*["']([^"']*)["']''',
      caseSensitive: false,
    );

    final match = pattern.firstMatch(tag);

    return match?.group(1);
  }

  // ============================================================
  // VERIFICAR ERROS NA RESPOSTA
  // ============================================================

  bool _containsError(
    String body,
  ) {
    final normalized = body.toLowerCase();

    const markers = [
      'exception',
      'server error',
      'erro ao salvar',
      'não foi possível salvar',
      'nao foi possivel salvar',
      'alert(',
    ];

    return markers.any(
      normalized.contains,
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  void dispose() {
    _client.close();
  }
}

// ================================================================
// EXCEÇÃO GERAL DO E-DESK
// ================================================================

class EdeskException implements Exception {
  final String message;

  const EdeskException(
    this.message,
  );

  @override
  String toString() => message;
}

// ================================================================
// EXCEÇÃO DE AUTENTICAÇÃO
// ================================================================

class EdeskAuthenticationException extends EdeskException {
  const EdeskAuthenticationException(
    String message,
  ) : super(message);
}
