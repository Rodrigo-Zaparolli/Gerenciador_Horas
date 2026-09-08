import 'dart:convert';

import 'package:http/http.dart' as http;

/// ================================================================
/// DADOS DO TRABALHO
/// ================================================================
///
/// Representa os dados que serão preenchidos na tela
/// TrabalhoRetroativo.aspx do E-Desk.
///
/// IMPORTANTE:
/// - solicitacao e idTrabalho identificam o trabalho existente
///   no E-Desk.
/// - Eles permanecem no modelo para a próxima etapa da integração.
/// - Não são enviados arbitrariamente como campos de formulário,
///   pois ainda precisamos preservar exatamente os campos que o
///   próprio E-Desk utiliza na página.
///
class EdeskWorkData {
  final Uri pageUri;

  /// Número/identificador da solicitação no E-Desk.
  final String solicitacao;

  /// Identificador do trabalho existente.
  final String idTrabalho;

  /// Data do trabalho.
  final String data;

  /// Hora inicial.
  final String horaInicio;

  /// Hora final.
  final String horaFim;

  /// Tipo de registro selecionado no E-Desk.
  final String tipoRegistro;

  /// Nome/descrição da tarefa.
  final String tarefa;

  /// Descrição detalhada do trabalho.
  final String descricao;

  /// GTT, quando aplicável.
  final String? gtt;

  /// Equipamento, quando aplicável.
  final String? equipamento;

  /// Atendimento, quando aplicável.
  final String? atendimento;

  /// Motivo, quando aplicável.
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

/// ================================================================
/// RESULTADO DO ENVIO
/// ================================================================
///
/// Retorna informações suficientes para a interface decidir
/// o que fazer depois da tentativa de envio.
///
class EdeskSendResult {
  /// Indica se a resposta foi considerada aceitável.
  final bool confirmed;

  /// Código HTTP retornado.
  final int statusCode;

  /// Mensagem amigável para exibição.
  final String message;

  /// Corpo bruto retornado pelo E-Desk.
  ///
  /// Mantido para diagnóstico e para refinarmos posteriormente
  /// a confirmação da gravação.
  final String responseBody;

  const EdeskSendResult({
    required this.confirmed,
    required this.statusCode,
    required this.message,
    required this.responseBody,
  });
}

/// ================================================================
/// SERVIÇO E-DESK
/// ================================================================
///
/// Responsável exclusivamente pela comunicação HTTP com o E-Desk.
///
/// A interface gráfica NÃO deve conhecer:
/// - cookies;
/// - VIEWSTATE;
/// - EVENTVALIDATION;
/// - UpdatePanel;
/// - __ASYNCPOST;
/// - detalhes do POST.
///
/// Tudo isso fica concentrado neste serviço.
///
class EdeskService {
  EdeskService({
    http.Client? client,
  }) : _client = client ?? http.Client();

  final http.Client _client;

  /// ==============================================================
  /// SESSÃO
  /// ==============================================================

  /// Cookies da sessão atualmente autenticada.
  final Map<String, String> _cookies = {};

  /// Retorna os cookies atuais somente para leitura.
  ///
  /// Não permite que código externo altere diretamente o mapa.
  Map<String, String> get cookies {
    return Map.unmodifiable(_cookies);
  }

  /// Define os cookies de uma sessão já autenticada.
  ///
  /// Não armazena credenciais permanentemente.
  /// Apenas mantém os cookies em memória durante a utilização
  /// deste serviço.
  void setSessionCookies(
    Map<String, String> cookies,
  ) {
    _cookies
      ..clear()
      ..addAll(cookies);
  }

  /// Remove a sessão atual.
  void clearSession() {
    _cookies.clear();
  }

  /// Indica se existe alguma informação de sessão armazenada.
  bool get hasSession {
    return _cookies.isNotEmpty;
  }

  /// ==============================================================
  /// ENVIO DO TRABALHO
  /// ==============================================================

  Future<EdeskSendResult> sendWork(
    EdeskWorkData work,
  ) async {
    // ============================================================
    // 1. VALIDAR DADOS BÁSICOS
    // ============================================================

    _validateWorkData(work);

    // ============================================================
    // 2. ABRIR A PÁGINA DO TRABALHO
    // ============================================================
    //
    // O GET é importante porque o E-Desk utiliza estado dinâmico
    // do ASP.NET WebForms.
    //
    // Não podemos reutilizar um VIEWSTATE antigo.
    //

    late final http.Response getResponse;

    try {
      getResponse = await _client.get(
        work.pageUri,
        headers: _headers(),
      );
    } on Exception catch (e) {
      throw EdeskException(
        'Erro ao conectar ao E-Desk: $e',
      );
    }

    // Atualiza cookies caso o servidor tenha enviado novos cookies.
    _storeCookies(getResponse);

    // ============================================================
    // 3. VERIFICAR RESPOSTA DO GET
    // ============================================================

    if (_isRedirectToLogin(getResponse)) {
      throw const EdeskAuthenticationException(
        'A sessão do E-Desk não está autenticada ou expirou.',
      );
    }

    if (getResponse.statusCode != 200) {
      throw EdeskException(
        'Não foi possível abrir a página do E-Desk. '
        'HTTP ${getResponse.statusCode}.',
      );
    }

    final html = _decodeResponse(getResponse);

    // ============================================================
    // 4. VERIFICAR SE RECEBEMOS UMA PÁGINA VÁLIDA
    // ============================================================

    if (_looksLikeLoginPage(html)) {
      throw const EdeskAuthenticationException(
        'O E-Desk retornou a tela de login. '
        'A sessão atual não está autenticada.',
      );
    }

    // ============================================================
    // 5. EXTRAIR CAMPOS HIDDEN
    // ============================================================
    //
    // ASP.NET WebForms utiliza campos como:
    //
    // __VIEWSTATE
    // __VIEWSTATEGENERATOR
    // __EVENTVALIDATION
    // __EVENTTARGET
    // __EVENTARGUMENT
    //
    // Esses valores podem mudar a cada carregamento.
    //

    final hiddenFields = _extractHiddenFields(html);

    if (hiddenFields.isEmpty) {
      throw const EdeskAuthenticationException(
        'A página do E-Desk não retornou os campos '
        'de estado do formulário. '
        'A sessão pode não estar autenticada ou a página '
        'retornada não é o formulário esperado.',
      );
    }

    // ============================================================
    // 6. PREPARAR FORMULÁRIO
    // ============================================================

    final form = <String, String>{
      ...hiddenFields,
    };

    // ============================================================
    // 7. PREENCHER CAMPOS DO TRABALHO
    // ============================================================

    form[r'ctl00$cph1$txtDatTem'] = work.data;

    form[r'ctl00$cph1$txtHorIni'] = work.horaInicio;

    form[r'ctl00$cph1$txtHorFin'] = work.horaFim;

    form[r'ctl00$cph1$ddlTipReg'] = work.tipoRegistro;

    form[r'ctl00$cph1$txlTtr$txtDes'] = work.tarefa;

    form[r'ctl00$cph1$txtDet'] = work.descricao;

    // ============================================================
    // 8. CAMPOS OPCIONAIS
    // ============================================================

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

    // ============================================================
    // 9. CONFIGURAR ASP.NET AJAX / UPDATEPANEL
    // ============================================================

    form[r'ctl00$scmF'] = r'ctl00$cph1$uppG|ctl00$cph1$BtAtu';

    form['__EVENTTARGET'] = '';

    form['__EVENTARGUMENT'] = '';

    form['__ASYNCPOST'] = 'true';

    // Botão responsável pelo salvamento.
    form[r'ctl00$cph1$BtAtu'] = 'Salvar';

    // ============================================================
    // 10. ENVIAR POST
    // ============================================================

    late final http.Response postResponse;

    try {
      postResponse = await _client.post(
        work.pageUri,
        headers: {
          ..._headers(),
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'Referer': work.pageUri.toString(),
          'X-Requested-With': 'XMLHttpRequest',
        },
        body: form,
      );
    } on Exception catch (e) {
      throw EdeskException(
        'Erro ao enviar os dados para o E-Desk: $e',
      );
    }

    // O servidor pode atualizar cookies durante o POST.
    _storeCookies(postResponse);

    // ============================================================
    // 11. DECODIFICAR RESPOSTA
    // ============================================================

    final body = _decodeResponse(postResponse);

    // ============================================================
    // 12. VERIFICAR AUTENTICAÇÃO
    // ============================================================

    if (_looksLikeLoginPage(body)) {
      throw const EdeskAuthenticationException(
        'O E-Desk retornou a tela de login durante o envio. '
        'A sessão pode ter expirado.',
      );
    }

    // ============================================================
    // 13. VERIFICAR ERROS CONHECIDOS
    // ============================================================

    if (_containsServerError(body)) {
      return EdeskSendResult(
        confirmed: false,
        statusCode: postResponse.statusCode,
        message: 'O E-Desk retornou uma mensagem de erro durante o salvamento.',
        responseBody: body,
      );
    }

    // ============================================================
    // 14. VERIFICAR STATUS HTTP
    // ============================================================

    if (postResponse.statusCode < 200 || postResponse.statusCode >= 300) {
      return EdeskSendResult(
        confirmed: false,
        statusCode: postResponse.statusCode,
        message: 'O E-Desk retornou HTTP ${postResponse.statusCode}. '
            'O salvamento não pôde ser confirmado.',
        responseBody: body,
      );
    }

    // ============================================================
    // 15. ANALISAR RESPOSTA AJAX
    // ============================================================
    //
    // O E-Desk utiliza ASP.NET AJAX.
    //
    // Uma resposta HTTP 200 não significa necessariamente que
    // o registro foi salvo.
    //
    // Por isso mantemos uma análise específica da resposta.
    //

    final ajaxAnalysis = _analyzeAjaxResponse(body);

    if (ajaxAnalysis.isError) {
      return EdeskSendResult(
        confirmed: false,
        statusCode: postResponse.statusCode,
        message: ajaxAnalysis.message,
        responseBody: body,
      );
    }

    // ============================================================
    // 16. RESULTADO
    // ============================================================
    //
    // Neste momento consideramos a solicitação HTTP aceita pelo
    // servidor, mas mantemos a mensagem explícita para não confundir
    // "HTTP aceito" com "registro definitivamente confirmado".
    //
    // Na próxima etapa podemos implementar uma confirmação real,
    // por exemplo:
    //
    // POST -> GET novamente -> verificar se o registro apareceu
    // no Retroativo.
    //

    return EdeskSendResult(
      confirmed: true,
      statusCode: postResponse.statusCode,
      message: 'O E-Desk aceitou a solicitação de salvamento.',
      responseBody: body,
    );
  }

  // ==============================================================
  // VALIDAÇÃO
  // ==============================================================

  void _validateWorkData(
    EdeskWorkData work,
  ) {
    if (work.pageUri.toString().trim().isEmpty) {
      throw const EdeskException(
        'A URL do trabalho no E-Desk não foi informada.',
      );
    }

    if (work.data.trim().isEmpty) {
      throw const EdeskException(
        'A data do trabalho não foi informada.',
      );
    }

    if (work.horaInicio.trim().isEmpty) {
      throw const EdeskException(
        'A hora inicial não foi informada.',
      );
    }

    if (work.horaFim.trim().isEmpty) {
      throw const EdeskException(
        'A hora final não foi informada.',
      );
    }

    if (work.tipoRegistro.trim().isEmpty) {
      throw const EdeskException(
        'O tipo de registro não foi informado.',
      );
    }

    if (work.tarefa.trim().isEmpty) {
      throw const EdeskException(
        'A tarefa não foi informada.',
      );
    }
  }

  // ==============================================================
  // HEADERS
  // ==============================================================

  Map<String, String> _headers() {
    return {
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,'
          '*/*;q=0.8',
      'Accept-Language': 'pt-BR,pt;q=0.9,en;q=0.8',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 '
          '(KHTML, like Gecko) '
          'Chrome/140.0.0.0 Safari/537.36',
      if (_cookies.isNotEmpty) 'Cookie': _cookieHeader(),
    };
  }

  // ==============================================================
  // COOKIE HEADER
  // ==============================================================

  String _cookieHeader() {
    return _cookies.entries
        .map(
          (entry) => '${entry.key}=${entry.value}',
        )
        .join('; ');
  }

  // ==============================================================
  // ARMAZENAR COOKIES
  // ==============================================================

  void _storeCookies(
    http.Response response,
  ) {
    final values = response.headers['set-cookie'];

    if (values == null || values.isEmpty) {
      return;
    }

    // Alguns servidores retornam múltiplos cookies no mesmo header.
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

      if (name.isEmpty) {
        continue;
      }

      // Cookies expirados podem vir vazios.
      //
      // Não removemos automaticamente aqui porque alguns ambientes
      // utilizam cookies especiais durante a navegação.
      _cookies[name] = value;
    }
  }

  // ==============================================================
  // DECODIFICAR RESPONSE
  // ==============================================================

  String _decodeResponse(
    http.Response response,
  ) {
    return utf8.decode(
      response.bodyBytes,
      allowMalformed: true,
    );
  }

  // ==============================================================
  // EXTRAIR CAMPOS HIDDEN
  // ==============================================================

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

      final name = _attribute(
        tag,
        'name',
      );

      if (name == null || name.isEmpty) {
        continue;
      }

      final value = _attribute(
            tag,
            'value',
          ) ??
          '';

      fields[name] = value;
    }

    return fields;
  }

  // ==============================================================
  // LER ATRIBUTO HTML
  // ==============================================================

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

  // ==============================================================
  // VERIFICAR REDIRECIONAMENTO
  // ==============================================================

  bool _isRedirectToLogin(
    http.Response response,
  ) {
    if (response.statusCode < 300 || response.statusCode >= 400) {
      return false;
    }

    final location = response.headers['location'];

    if (location == null) {
      return false;
    }

    return _looksLikeLoginUrl(location);
  }

  // ==============================================================
  // VERIFICAR PÁGINA DE LOGIN
  // ==============================================================

  bool _looksLikeLoginPage(
    String body,
  ) {
    final normalized = body.toLowerCase();

    const markers = [
      'login',
      'entrar',
      'senha',
      'usuário',
      'usuario',
      'promob identity',
    ];

    // Não basta encontrar uma palavra isolada como "login",
    // pois páginas normais podem conter esse texto.
    //
    // Procuramos combinações mais características.
    final hasLoginMarker = normalized.contains('promob identity') ||
        normalized.contains('login.aspx') ||
        normalized.contains('signin') ||
        normalized.contains('entrar');

    final hasPasswordField = normalized.contains('type="password"') ||
        normalized.contains("type='password'");

    final hasUserField = normalized.contains('usuário') ||
        normalized.contains('usuario') ||
        normalized.contains('username');

    if (hasLoginMarker && hasPasswordField) {
      return true;
    }

    if (hasUserField && hasPasswordField) {
      return true;
    }

    return false;
  }

  // ==============================================================
  // VERIFICAR URL DE LOGIN
  // ==============================================================

  bool _looksLikeLoginUrl(
    String url,
  ) {
    final normalized = url.toLowerCase();

    return normalized.contains('login') ||
        normalized.contains('signin') ||
        normalized.contains('identity');
  }

  // ==============================================================
  // VERIFICAR ERROS DO SERVIDOR
  // ==============================================================

  bool _containsServerError(
    String body,
  ) {
    final normalized = body.toLowerCase();

    const markers = [
      'server error',
      'http error 500',
      'exception details',
      'stack trace',
      'erro ao salvar',
      'erro ao gravar',
      'não foi possível salvar',
      'nao foi possivel salvar',
      'não foi possível gravar',
      'nao foi possivel gravar',
    ];

    return markers.any(
      normalized.contains,
    );
  }

  // ==============================================================
  // ANALISAR RESPOSTA ASP.NET AJAX
  // ==============================================================

  _AjaxResponseAnalysis _analyzeAjaxResponse(
    String body,
  ) {
    final normalized = body.toLowerCase();

    // ------------------------------------------------------------
    // Erros explícitos conhecidos.
    // ------------------------------------------------------------

    const errorMarkers = [
      'server error',
      'exception',
      'erro ao salvar',
      'erro ao gravar',
      'não foi possível salvar',
      'nao foi possivel salvar',
      'não foi possível gravar',
      'nao foi possivel gravar',
    ];

    for (final marker in errorMarkers) {
      if (normalized.contains(marker)) {
        return const _AjaxResponseAnalysis(
          isError: true,
          message: 'O E-Desk retornou um erro durante o processamento.',
        );
      }
    }

    // ------------------------------------------------------------
    // ASP.NET AJAX normalmente retorna uma resposta contendo
    // informações delimitadas pelo mecanismo de PageRequestManager.
    //
    // Não exigimos uma palavra específica de sucesso aqui porque
    // ainda precisamos observar a resposta real do E-Desk durante
    // o primeiro teste.
    // ------------------------------------------------------------

    return const _AjaxResponseAnalysis(
      isError: false,
      message: 'Resposta processada sem erro explícito.',
    );
  }

  // ==============================================================
  // DISPOSE
  // ==============================================================

  void dispose() {
    _client.close();
  }
}

// ================================================================
// ANÁLISE DA RESPOSTA AJAX
// ================================================================

class _AjaxResponseAnalysis {
  final bool isError;
  final String message;

  const _AjaxResponseAnalysis({
    required this.isError,
    required this.message,
  });
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
