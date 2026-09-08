import 'dart:convert';
<<<<<<< HEAD

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
=======
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
>>>>>>> ebaf51457bb314e8e72fbbbf8d3d3ad90d7e33b5
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

<<<<<<< HEAD
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
=======
/// Resultado da tentativa de envio para o E-Desk.
class EdeskSendResult {
  final bool confirmed;
  final int statusCode;
  final String message;
>>>>>>> ebaf51457bb314e8e72fbbbf8d3d3ad90d7e33b5
  final String responseBody;

  const EdeskSendResult({
    required this.confirmed,
    required this.statusCode,
    required this.message,
    required this.responseBody,
  });
}

<<<<<<< HEAD
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
=======
/// Serviço de comunicação com o E-Desk.
class EdeskService {
  EdeskService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Cookies da sessão atual.
  final Map<String, String> _cookies = {};

  /// Retorna os cookies atuais sem permitir alteração externa.
  Map<String, String> get cookies => Map.unmodifiable(_cookies);

  /// Define os cookies de uma sessão já autenticada.
>>>>>>> ebaf51457bb314e8e72fbbbf8d3d3ad90d7e33b5
  void setSessionCookies(
    Map<String, String> cookies,
  ) {
    _cookies
      ..clear()
      ..addAll(cookies);
  }

<<<<<<< HEAD
  /// Remove a sessão atual.
=======
  /// Limpa a sessão atual.
>>>>>>> ebaf51457bb314e8e72fbbbf8d3d3ad90d7e33b5
  void clearSession() {
    _cookies.clear();
  }

<<<<<<< HEAD
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

=======
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

>>>>>>> ebaf51457bb314e8e72fbbbf8d3d3ad90d7e33b5
    if (getResponse.statusCode != 200) {
      throw EdeskException(
        'Não foi possível abrir a página do E-Desk. '
        'HTTP ${getResponse.statusCode}.',
      );
    }

<<<<<<< HEAD
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
=======
    final html = utf8.decode(
      getResponse.bodyBytes,
      allowMalformed: true,
    );

    // ==========================================================
    // 2. EXTRAIR CAMPOS HIDDEN DO ASP.NET WEB FORMS
    // ==========================================================
>>>>>>> ebaf51457bb314e8e72fbbbf8d3d3ad90d7e33b5

    final hiddenFields = _extractHiddenFields(html);

    if (hiddenFields.isEmpty) {
      throw const EdeskAuthenticationException(
        'A página do E-Desk não retornou os campos '
<<<<<<< HEAD
        'de estado do formulário. '
        'A sessão pode não estar autenticada ou a página '
        'retornada não é o formulário esperado.',
      );
    }

    // ============================================================
    // 6. PREPARAR FORMULÁRIO
    // ============================================================

=======
        'de estado. A sessão pode não estar autenticada.',
      );
    }

>>>>>>> ebaf51457bb314e8e72fbbbf8d3d3ad90d7e33b5
    final form = <String, String>{
      ...hiddenFields,
    };

<<<<<<< HEAD
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

=======
    // ==========================================================
    // 3. CAMPOS DO TRABALHO
    // ==========================================================

    form[r'ctl00$cph1$txtDatTem'] = work.data;
    form[r'ctl00$cph1$txtHorIni'] = work.horaInicio;
    form[r'ctl00$cph1$txtHorFin'] = work.horaFim;
    form[r'ctl00$cph1$ddlTipReg'] = work.tipoRegistro;
    form[r'ctl00$cph1$txlTtr$txtDes'] = work.tarefa;
    form[r'ctl00$cph1$txtDet'] = work.descricao;

>>>>>>> ebaf51457bb314e8e72fbbbf8d3d3ad90d7e33b5
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

<<<<<<< HEAD
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
=======
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
>>>>>>> ebaf51457bb314e8e72fbbbf8d3d3ad90d7e33b5
      responseBody: body,
    );
  }

<<<<<<< HEAD
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
=======
  // ============================================================
  // HEADERS
  // ============================================================

  Map<String, String> _headers() {
    return {
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
>>>>>>> ebaf51457bb314e8e72fbbbf8d3d3ad90d7e33b5
      if (_cookies.isNotEmpty) 'Cookie': _cookieHeader(),
    };
  }

<<<<<<< HEAD
  // ==============================================================
  // COOKIE HEADER
  // ==============================================================
=======
  // ============================================================
  // COOKIE HEADER
  // ============================================================
>>>>>>> ebaf51457bb314e8e72fbbbf8d3d3ad90d7e33b5

  String _cookieHeader() {
    return _cookies.entries
        .map(
          (entry) => '${entry.key}=${entry.value}',
        )
        .join('; ');
  }

<<<<<<< HEAD
  // ==============================================================
  // ARMAZENAR COOKIES
  // ==============================================================
=======
  // ============================================================
  // ARMAZENAR COOKIES
  // ============================================================
>>>>>>> ebaf51457bb314e8e72fbbbf8d3d3ad90d7e33b5

  void _storeCookies(
    http.Response response,
  ) {
    final values = response.headers['set-cookie'];

    if (values == null || values.isEmpty) {
      return;
    }

<<<<<<< HEAD
    // Alguns servidores retornam múltiplos cookies no mesmo header.
=======
>>>>>>> ebaf51457bb314e8e72fbbbf8d3d3ad90d7e33b5
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

<<<<<<< HEAD
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
=======
      if (name.isNotEmpty) {
        _cookies[name] = value;
      }
    }
  }

  // ============================================================
// EXTRAIR CAMPOS HIDDEN
// ============================================================
>>>>>>> ebaf51457bb314e8e72fbbbf8d3d3ad90d7e33b5

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

<<<<<<< HEAD
      final name = _attribute(
        tag,
        'name',
      );
=======
      final name = _attribute(tag, 'name');
>>>>>>> ebaf51457bb314e8e72fbbbf8d3d3ad90d7e33b5

      if (name == null || name.isEmpty) {
        continue;
      }

<<<<<<< HEAD
      final value = _attribute(
            tag,
            'value',
          ) ??
          '';

      fields[name] = value;
=======
      fields[name] = _attribute(tag, 'value') ?? '';
>>>>>>> ebaf51457bb314e8e72fbbbf8d3d3ad90d7e33b5
    }

    return fields;
  }

<<<<<<< HEAD
  // ==============================================================
  // LER ATRIBUTO HTML
  // ==============================================================
=======
// ============================================================
// LER ATRIBUTO HTML
// ============================================================
>>>>>>> ebaf51457bb314e8e72fbbbf8d3d3ad90d7e33b5

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

<<<<<<< HEAD
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
=======
  // ============================================================
  // VERIFICAR ERROS NA RESPOSTA
  // ============================================================

  bool _containsError(
>>>>>>> ebaf51457bb314e8e72fbbbf8d3d3ad90d7e33b5
    String body,
  ) {
    final normalized = body.toLowerCase();

    const markers = [
<<<<<<< HEAD
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
=======
      'exception',
      'server error',
      'erro ao salvar',
      'não foi possível salvar',
      'nao foi possivel salvar',
      'alert(',
>>>>>>> ebaf51457bb314e8e72fbbbf8d3d3ad90d7e33b5
    ];

    return markers.any(
      normalized.contains,
    );
  }

<<<<<<< HEAD
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
=======
  // ============================================================
  // DISPOSE
  // ============================================================
>>>>>>> ebaf51457bb314e8e72fbbbf8d3d3ad90d7e33b5

  void dispose() {
    _client.close();
  }
}

// ================================================================
<<<<<<< HEAD
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
=======
>>>>>>> ebaf51457bb314e8e72fbbbf8d3d3ad90d7e33b5
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
