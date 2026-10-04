import 'dart:async';

import 'dart:convert';

import 'dart:io';

/// ================================================================

/// PROCESSO ATUAL DA SINCRONIZAÇÃO DE FASES

/// ================================================================

Process? _edeskFasesProcessoAtual;

Completer<EdeskPythonResult>? _edeskFasesCompleterAtual;

/// ================================================================

/// AMBIENTE PORTÁTIL DA INTEGRAÇÃO E-DESK

///

/// Procura os arquivos primeiro ao lado do executável instalado:

///   <app>\python\Scripts\python.exe

///   <app>\edesk_bot\\<script>

///

/// Durante o desenvolvimento também aceita:

///   <projeto>\\.venv\Scripts\python.exe

///   <projeto>\edesk_bot\\<script>

///

/// Assim a integração não depende de caminhos absolutos da máquina

/// de desenvolvimento.

/// ================================================================

class _EdeskRuntime {
  final String pythonExe;

  final String scriptPath;

  final String workingDirectory;

  const _EdeskRuntime({
    required this.pythonExe,
    required this.scriptPath,
    required this.workingDirectory,
  });
}

Future<_EdeskRuntime?> _resolverEdeskRuntime(String script) async {
  // ================================================================
  // LINUX / MACOS
  // ================================================================

  if (!Platform.isWindows) {
    final currentDirectory = Directory.current.path;

    final scriptPath = '$currentDirectory${Platform.pathSeparator}'
        'edesk_bot${Platform.pathSeparator}$script';

    if (!await File(scriptPath).exists()) {
      return null;
    }

    return _EdeskRuntime(
      pythonExe: 'python3',
      scriptPath: scriptPath,
      workingDirectory: currentDirectory,
    );
  }

  // ================================================================
  // WINDOWS
  // ================================================================
  //
  // O aplicativo pode ser executado:
  //
  // 1. Pelo Flutter durante o desenvolvimento;
  // 2. Pelo executável compilado;
  // 3. Por um atalho do Windows;
  // 4. Com um WorkingDirectory diferente da raiz do projeto.
  //
  // Por isso não podemos depender somente de Directory.current.
  // ================================================================

  final executableDirectory = File(Platform.resolvedExecutable).parent.path;

  final currentDirectory = Directory.current.path;

  // ================================================================
  // RAÍZES POSSÍVEIS
  // ================================================================

  final roots = <String>[];

  void adicionarRoot(String? root) {
    if (root == null) {
      return;
    }

    final valor = root.trim();

    if (valor.isEmpty) {
      return;
    }

    final jaExiste = roots.any(
      (item) => item.toLowerCase() == valor.toLowerCase(),
    );

    if (!jaExiste) {
      roots.add(valor);
    }
  }

  // ---------------------------------------------------------------
  // 1. Diretório do executável
  // ---------------------------------------------------------------

  adicionarRoot(executableDirectory);

  // ---------------------------------------------------------------
  // 2. WorkingDirectory atual
  // ---------------------------------------------------------------

  adicionarRoot(currentDirectory);

  // ---------------------------------------------------------------
  // 3. Pasta pai do executável
  //
  // Útil quando estamos executando algo dentro de:
  // build\windows\x64\runner\Debug
  // ou estruturas semelhantes.
  // ---------------------------------------------------------------

  var pastaExecutavel = Directory(executableDirectory);

  for (var i = 0; i < 8; i++) {
    adicionarRoot(pastaExecutavel.path);

    final parent = pastaExecutavel.parent;

    if (parent.path.toLowerCase() == pastaExecutavel.path.toLowerCase()) {
      break;
    }

    pastaExecutavel = parent;
  }

  // ---------------------------------------------------------------
  // 4. Pastas pai do Directory.current
  // ---------------------------------------------------------------

  var pastaAtual = Directory(currentDirectory);

  for (var i = 0; i < 8; i++) {
    adicionarRoot(pastaAtual.path);

    final parent = pastaAtual.parent;

    if (parent.path.toLowerCase() == pastaAtual.path.toLowerCase()) {
      break;
    }

    pastaAtual = parent;
  }

  // ---------------------------------------------------------------
  // 5. Caminho conhecido do ambiente de desenvolvimento
  //
  // Esse fallback garante o funcionamento no projeto atual.
  // Não interfere na versão instalada/portátil porque ele é
  // consultado somente se necessário.
  // ---------------------------------------------------------------

  adicionarRoot(
    r'D:\APP\gerenciador_horas',
  );

  // ================================================================
  // LOG DAS RAÍZES
  // ================================================================

  print('');
  print(
    '[E-Desk][Runtime] ========================================',
  );

  print(
    '[E-Desk][Runtime] Procurando ambiente para: $script',
  );

  print(
    '[E-Desk][Runtime] Executável Flutter: '
    '${Platform.resolvedExecutable}',
  );

  print(
    '[E-Desk][Runtime] Directory.current: $currentDirectory',
  );

  print(
    '[E-Desk][Runtime] Raízes encontradas:',
  );

  for (final root in roots) {
    print(
      '[E-Desk][Runtime] - $root',
    );
  }

  print(
    '[E-Desk][Runtime] ========================================',
  );

  // ================================================================
  // PROCURA SCRIPT + PYTHON
  // ================================================================

  for (final root in roots) {
    final scriptPath = '$root${Platform.pathSeparator}'
        'edesk_bot${Platform.pathSeparator}$script';

    final scriptFile = File(scriptPath);

    if (!await scriptFile.exists()) {
      continue;
    }

    print(
      '[E-Desk][Runtime] Script encontrado: $scriptPath',
    );

    // ==============================================================
    // POSSÍVEIS PYTHONS
    // ==============================================================

    final pythonCandidates = <String>[
      // ------------------------------------------------------------
      // Distribuição portátil do aplicativo
      // ------------------------------------------------------------

      '$root${Platform.pathSeparator}'
          'python${Platform.pathSeparator}'
          'Scripts${Platform.pathSeparator}'
          'python.exe',

      // ------------------------------------------------------------
      // Distribuição Python direta
      // ------------------------------------------------------------

      '$root${Platform.pathSeparator}'
          'python${Platform.pathSeparator}'
          'python.exe',

      // ------------------------------------------------------------
      // Ambiente virtual de desenvolvimento
      // ------------------------------------------------------------

      '$root${Platform.pathSeparator}'
          '.venv${Platform.pathSeparator}'
          'Scripts${Platform.pathSeparator}'
          'python.exe',
    ];

    for (final pythonExe in pythonCandidates) {
      if (!await File(pythonExe).exists()) {
        continue;
      }

      print(
        '[E-Desk][Runtime] Python encontrado: $pythonExe',
      );

      print(
        '[E-Desk][Runtime] WorkingDirectory: $root',
      );

      print(
        '[E-Desk][Runtime] Ambiente E-Desk encontrado.',
      );

      return _EdeskRuntime(
        pythonExe: pythonExe,
        scriptPath: scriptPath,
        workingDirectory: root,
      );
    }

    print(
      '[E-Desk][Runtime] Script encontrado, '
      'mas Python não encontrado em: $root',
    );
  }

  // ================================================================
  // NÃO ENCONTROU
  // ================================================================

  print('');
  print(
    '[E-Desk][Runtime] ========================================',
  );

  print(
    '[E-Desk][Runtime] AMBIENTE NÃO ENCONTRADO',
  );

  print(
    '[E-Desk][Runtime] Script solicitado: $script',
  );

  print(
    '[E-Desk][Runtime] ========================================',
  );

  return null;
}

/// ================================================================

/// EXECUTA PYTHON E-DESK

///

/// Mantém o comportamento atual:

/// - inicia o Python

/// - captura stdout/stderr

/// - aguarda o término

/// - retorna o resultado final

///

/// Usado pelas integrações que precisam do resultado do Python.

/// ================================================================

Future<EdeskPythonResult> executarPythonEdesk({
  required String requestJson,
  required bool enviar,

  // Mantém main.py como padrão para não quebrar

  // a integração atual de comentários.

  String script = 'edesk_comentario.py',
}) async {
  Directory? tempDirectory;

  try {
    final runtime = await _resolverEdeskRuntime(script);

    if (runtime == null) {
      return EdeskPythonResult(
        confirmed: false,
        statusCode: 0,
        message: 'Ambiente da integração E-Desk não encontrado. '
            'Verifique as pastas python e edesk_bot junto ao aplicativo.',
        responseBody: 'Script solicitado: $script',
      );
    }

    final pythonExe = runtime.pythonExe;

    final scriptPath = runtime.scriptPath;

    final workingDirectory = runtime.workingDirectory;

    // ============================================================

    // ARQUIVO TEMPORÁRIO DO REQUEST

    // ============================================================

    tempDirectory = await Directory.systemTemp.createTemp(
      'edesk_request_',
    );

    final requestFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}request.json',
    );

    await requestFile.writeAsString(
      requestJson,
      encoding: utf8,
    );

    print('');

    print(
      '[E-Desk] ============================================',
    );

    print('[E-Desk] Executando Python.');

    print(
      '[E-Desk] Modo: ${enviar ? 'ENVIO' : 'TESTE'}',
    );

    print('[E-Desk] Python: $pythonExe');

    print('[E-Desk] Script: $scriptPath');

    print('[E-Desk] Request: ${requestFile.path}');

    print(
      '[E-Desk] ============================================',
    );

    // ============================================================

    // INICIA PYTHON

    // ============================================================

    final processo = await Process.start(
      pythonExe,
      [
        '-X',
        'utf8',
        scriptPath,
        requestFile.path,
      ],
      workingDirectory: workingDirectory,
      runInShell: false,
      environment: {
        ...Platform.environment,
        'PYTHONIOENCODING': 'utf-8',
        'PYTHONUTF8': '1',
      },
    );

    print(
      '[E-Desk] Python iniciado. PID=${processo.pid}',
    );

    // ============================================================

    // CAPTURA STDOUT EM TEMPO REAL

    // ============================================================

    final stdoutBuffer = StringBuffer();

    processo.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (linha) {
        stdoutBuffer.writeln(linha);

        final linhaLimpa = linha.trimRight();

        if (linhaLimpa.isNotEmpty) {
          print(
            '[E-Desk][Python] $linhaLimpa',
          );
        }
      },
      onError: (Object erro) {
        print(
          '[E-Desk][Python][ERRO STDOUT] $erro',
        );
      },
    );

    // ============================================================

    // CAPTURA STDERR EM TEMPO REAL

    // ============================================================

    final stderrBuffer = StringBuffer();

    processo.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (linha) {
        stderrBuffer.writeln(linha);

        final linhaLimpa = linha.trimRight();

        if (linhaLimpa.isNotEmpty) {
          print(
            '[E-Desk][Python][ERRO] $linhaLimpa',
          );
        }
      },
      onError: (Object erro) {
        print(
          '[E-Desk][Python][ERRO STREAM] $erro',
        );
      },
    );

    // ============================================================

    // AGUARDA SOMENTE O PROCESSO PYTHON

    //

    // IMPORTANTE:

    // Não aguardamos stdout/stderr com asFuture().

    //

    // Com Playwright/navegador no Windows, os streams podem

    // permanecer abertos mesmo depois de o processo Python ter

    // terminado. Isso fazia o Future ficar preso e o modal

    // permanecia em "Enviando horas...".

    // ============================================================

    print(
      '[E-Desk] Aguardando encerramento do Python...',
    );

    final exitCode = await processo.exitCode;

    // Pequeno intervalo para permitir que as últimas linhas

    // do stdout/stderr sejam recebidas pelos listeners.

    await Future<void>.delayed(
      const Duration(milliseconds: 150),
    );

    final stdout = stdoutBuffer.toString();

    final stderr = stderrBuffer.toString();

    print('');

    print(
      '[E-Desk] Python finalizado. exitCode=$exitCode',
    );

    // ============================================================

    // PYTHON RETORNOU ERRO

    // ============================================================

    if (exitCode != 0) {
      final diagnostico =
          stderr.trim().isNotEmpty ? stderr.trim() : stdout.trim();

      print('');

      print(
        '[E-Desk] ============================================',
      );

      print(
        '[E-Desk] PYTHON RETORNOU ERRO',
      );

      print(
        '[E-Desk] ExitCode: $exitCode',
      );

      print(
        '[E-Desk] Diagnóstico:',
      );

      print(diagnostico);

      print(
        '[E-Desk] ============================================',
      );

      return EdeskPythonResult(
        confirmed: false,
        statusCode: exitCode,
        message: 'O Python retornou erro.',
        responseBody: diagnostico,
      );
    }

    // ============================================================

    // SUCESSO

    // ============================================================

    print('');

    print(
      '[E-Desk] ============================================',
    );

    print(
      '[E-Desk] OPERAÇÃO CONCLUÍDA COM SUCESSO',
    );

    print(
      '[E-Desk] O Flutter recebeu o término do Python.',
    );

    print(
      '[E-Desk] ============================================',
    );

    return EdeskPythonResult(
      confirmed: true,
      statusCode: 200,
      message: enviar
          ? 'Operação enviada para o E-Desk.'
          : 'Operação preenchida para teste. Não foi salva.',
      responseBody: stdout,
    );
  } catch (e, stackTrace) {
    print('');

    print(
      '[E-Desk] ============================================',
    );

    print(
      '[E-Desk] ERRO AO EXECUTAR PYTHON',
    );

    print(
      '[E-Desk] $e',
    );

    print(stackTrace);

    print(
      '[E-Desk] ============================================',
    );

    return EdeskPythonResult(
      confirmed: false,
      statusCode: 0,
      message: 'Erro ao executar integração E-Desk: $e',
      responseBody: stackTrace.toString(),
    );
  } finally {
    // ============================================================

    // LIMPA REQUEST TEMPORÁRIO

    // ============================================================

    try {
      if (tempDirectory != null && await tempDirectory.exists()) {
        await tempDirectory.delete(
          recursive: true,
        );
      }
    } catch (_) {}
  }
}

/// ================================================================

/// CANCELAR PYTHON E-DESK

///

/// Encerra:

/// - Python

/// - Playwright

/// - navegador filho criado pelo Playwright

///

/// No Windows usamos TASKKILL /T /F para encerrar toda a árvore.

/// ================================================================

Future<bool> cancelarPythonEdeskBackground() async {
  final processo = _edeskFasesProcessoAtual;

  final completer = _edeskFasesCompleterAtual;

  if (processo == null) {
    print(
      '[E-Desk][Background] Nenhuma sincronização ativa.',
    );

    return false;
  }

  print('');

  print(
    '[E-Desk][Background] ========================================',
  );

  print(
    '[E-Desk][Background] INTERROMPENDO SINCRONIZAÇÃO',
  );

  print(
    '[E-Desk][Background] PID=${processo.pid}',
  );

  print(
    '[E-Desk][Background] ========================================',
  );

  bool interrompido = false;

  try {
    if (Platform.isWindows) {
      // ==========================================================

      // FINALIZA TODA A ÁRVORE DE PROCESSOS

      //

      // Inclui o navegador iniciado pelo Playwright.

      // ==========================================================

      final resultado = await Process.run(
        'taskkill',
        [
          '/PID',
          processo.pid.toString(),
          '/T',
          '/F',
        ],
        runInShell: false,
      );

      interrompido = resultado.exitCode == 0;

      print(
        '[E-Desk][Background] taskkill exitCode=${resultado.exitCode}',
      );

      if (resultado.stdout.toString().trim().isNotEmpty) {
        print(
          '[E-Desk][Background] ${resultado.stdout}',
        );
      }

      if (resultado.stderr.toString().trim().isNotEmpty) {
        print(
          '[E-Desk][Background][ERRO] ${resultado.stderr}',
        );
      }
    } else {
      interrompido = processo.kill();
    }
  } catch (e) {
    print(
      '[E-Desk][Background] Erro ao interromper processo: $e',
    );

    // ==========================================================

    // FALLBACK

    // ==========================================================

    try {
      interrompido = processo.kill();
    } catch (_) {
      interrompido = false;
    }
  }

  // =============================================================

  // LIBERA O AWAIT DO FLUTTER IMEDIATAMENTE

  // =============================================================

  if (interrompido && completer != null && !completer.isCompleted) {
    completer.complete(
      const EdeskPythonResult(
        confirmed: false,
        statusCode: 499,
        message: 'Sincronização com o E-Desk interrompida pelo usuário.',
        responseBody: '',
      ),
    );
  }

  if (interrompido) {
    print(
      '[E-Desk][Background] Sincronização interrompida.',
    );
  } else {
    print(
      '[E-Desk][Background] Não foi possível interromper o processo.',
    );
  }

  return interrompido;
}

/// ================================================================

/// EXECUTA PYTHON E-DESK EM SEGUNDO PLANO

///

/// - Aguarda o marcador de conclusão.

/// - Não depende do exitCode para concluir a tela.

/// - Permite cancelamento.

/// - O navegador pode permanecer aberto após uma conclusão normal.

/// ================================================================

Future<EdeskPythonResult> executarPythonEdeskBackground({
  required String requestJson,
  required bool enviar,
  String script = 'edesk_fases.py',
}) async {
  Directory? tempDirectory;

  try {
    // =============================================================

    // EVITA DUAS SINCRONIZAÇÕES SIMULTÂNEAS

    // =============================================================

    if (_edeskFasesProcessoAtual != null) {
      return const EdeskPythonResult(
        confirmed: false,
        statusCode: 409,
        message: 'Já existe uma sincronização com o E-Desk em andamento.',
        responseBody: '',
      );
    }

    final runtime = await _resolverEdeskRuntime(script);

    if (runtime == null) {
      return EdeskPythonResult(
        confirmed: false,
        statusCode: 0,
        message: 'Ambiente da integração E-Desk não encontrado. '
            'Verifique as pastas python e edesk_bot junto ao aplicativo.',
        responseBody: 'Script solicitado: $script',
      );
    }

    final pythonExe = runtime.pythonExe;

    final scriptPath = runtime.scriptPath;

    final workingDirectory = runtime.workingDirectory;

    // =============================================================

    // ARQUIVO TEMPORÁRIO

    // =============================================================

    tempDirectory = await Directory.systemTemp.createTemp(
      'edesk_request_bg_',
    );

    final requestFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}request.json',
    );

    await requestFile.writeAsString(
      requestJson,
      encoding: utf8,
    );

    print('');

    print(
      '[E-Desk][Background] ========================================',
    );

    print(
      '[E-Desk][Background] Iniciando Python.',
    );

    print(
      '[E-Desk][Background] Modo: ${enviar ? 'ENVIO' : 'TESTE'}',
    );

    print(
      '[E-Desk][Background] Script: $scriptPath',
    );

    print(
      '[E-Desk][Background] ========================================',
    );

    // =============================================================

    // INICIA PYTHON

    // =============================================================

    final processo = await Process.start(
      pythonExe,
      [
        '-X',
        'utf8',
        scriptPath,
        requestFile.path,
      ],
      workingDirectory: workingDirectory,
      runInShell: false,
      environment: {
        ...Platform.environment,
        'PYTHONIOENCODING': 'utf-8',
        'PYTHONUTF8': '1',
      },
    );

    // =============================================================

    // REGISTRA O PROCESSO ATUAL

    // =============================================================

    _edeskFasesProcessoAtual = processo;

    print(
      '[E-Desk][Background] Python iniciado. PID=${processo.pid}',
    );

    // =============================================================

    // COMPLETER

    // =============================================================

    final completer = Completer<EdeskPythonResult>();

    _edeskFasesCompleterAtual = completer;

    final stdoutBuffer = StringBuffer();

    final stderrBuffer = StringBuffer();

    void concluir(
      EdeskPythonResult resultado,
    ) {
      if (!completer.isCompleted) {
        completer.complete(resultado);
      }
    }

    // =============================================================

    // STDOUT

    // =============================================================

    processo.stdout
        .transform(
          utf8.decoder,
        )
        .transform(
          const LineSplitter(),
        )
        .listen(
      (linha) {
        stdoutBuffer.writeln(linha);

        final linhaLimpa = linha.trim();

        if (linhaLimpa.isNotEmpty) {
          print(
            '[E-Desk][Python] $linhaLimpa',
          );
        }

        // ========================================================

        // CONCLUSÃO REAL

        // ========================================================

        if (linhaLimpa.contains(
          '__EDESK_FASES_CONCLUIDAS__',
        )) {
          concluir(
            EdeskPythonResult(
              confirmed: true,
              statusCode: 200,
              message: 'Datas das fases atualizadas no E-Desk com sucesso.',
              responseBody: stdoutBuffer.toString(),
            ),
          );

          return;
        }

        // ========================================================

        // ERRO REAL

        // ========================================================

        if (linhaLimpa.contains(
          '__EDESK_FASES_ERRO__',
        )) {
          concluir(
            EdeskPythonResult(
              confirmed: false,
              statusCode: 500,
              message: 'Não foi possível atualizar as fases no E-Desk.',
              responseBody: stdoutBuffer.toString(),
            ),
          );
        }
      },
      onError: (Object erro) {
        concluir(
          EdeskPythonResult(
            confirmed: false,
            statusCode: 500,
            message: 'Erro ao receber retorno do Python: $erro',
            responseBody: stdoutBuffer.toString(),
          ),
        );
      },
    );

    // =============================================================

    // STDERR

    // =============================================================

    processo.stderr
        .transform(
          utf8.decoder,
        )
        .transform(
          const LineSplitter(),
        )
        .listen(
      (linha) {
        stderrBuffer.writeln(linha);

        final linhaLimpa = linha.trim();

        if (linhaLimpa.isNotEmpty) {
          print(
            '[E-Desk][Python][ERRO] $linhaLimpa',
          );
        }
      },
      onError: (Object erro) {
        print(
          '[E-Desk][Python][ERRO STREAM] $erro',
        );
      },
    );

    // =============================================================

    // MONITORA O ENCERRAMENTO DO PROCESSO

    //

    // NÃO é o que decide uma conclusão normal.

    //

    // Serve para:

    // - detectar fechamento inesperado;

    // - limpar arquivos;

    // - liberar referências;

    // - desbloquear caso o Python termine sem marcador.

    // =============================================================

    processo.exitCode.then(
      (exitCode) async {
        final stdout = stdoutBuffer.toString().trim();

        final stderr = stderrBuffer.toString().trim();

        print('');

        print(
          '[E-Desk][Background] ========================================',
        );

        print(
          '[E-Desk][Background] Python encerrado.',
        );

        print(
          '[E-Desk][Background] PID=${processo.pid}',
        );

        print(
          '[E-Desk][Background] ExitCode=$exitCode',
        );

        print(
          '[E-Desk][Background] ========================================',
        );

        // =========================================================

        // SE AINDA NÃO TERMINOU O FUTURE

        // =========================================================

        if (!completer.isCompleted) {
          final diagnostico = stderr.isNotEmpty
              ? stderr
              : stdout.isNotEmpty
                  ? stdout
                  : 'O Python encerrou sem informar o resultado.';

          if (exitCode == 0) {
            concluir(
              EdeskPythonResult(
                confirmed: true,
                statusCode: 200,
                message: 'Atualização das fases concluída no E-Desk.',
                responseBody: stdoutBuffer.toString(),
              ),
            );
          } else {
            concluir(
              EdeskPythonResult(
                confirmed: false,
                statusCode: exitCode,
                message: 'O Python retornou erro durante a atualização.',
                responseBody: diagnostico,
              ),
            );
          }
        }

        // =========================================================

        // LIMPA REFERÊNCIAS DO PROCESSO

        // =========================================================

        if (identical(
          _edeskFasesProcessoAtual,
          processo,
        )) {
          _edeskFasesProcessoAtual = null;
        }

        if (identical(
          _edeskFasesCompleterAtual,
          completer,
        )) {
          _edeskFasesCompleterAtual = null;
        }

        // =========================================================

        // REMOVE REQUEST TEMPORÁRIO

        // =========================================================

        try {
          if (tempDirectory != null && await tempDirectory!.exists()) {
            await tempDirectory!.delete(
              recursive: true,
            );
          }
        } catch (e) {
          print(
            '[E-Desk][Background] '
            'Erro ao remover arquivo temporário: $e',
          );
        }
      },
      onError: (Object erro) {
        print(
          '[E-Desk][Background] '
          'Erro monitorando processo: $erro',
        );

        if (!completer.isCompleted) {
          concluir(
            EdeskPythonResult(
              confirmed: false,
              statusCode: 500,
              message: 'Erro monitorando o processo Python: $erro',
              responseBody: stderrBuffer.toString(),
            ),
          );
        }
      },
    );

    // =============================================================

    // AGUARDA:

    //

    // 1. conclusão do Python;

    // 2. erro;

    // 3. cancelamento pelo usuário.

    //

    // A interface Flutter continua responsiva.

    // =============================================================

    return completer.future;
  } catch (e, stackTrace) {
    if (identical(
      _edeskFasesProcessoAtual,
      null,
    )) {
      _edeskFasesProcessoAtual = null;
    }

    _edeskFasesCompleterAtual = null;

    try {
      if (tempDirectory != null && await tempDirectory!.exists()) {
        await tempDirectory!.delete(
          recursive: true,
        );
      }
    } catch (_) {}

    return EdeskPythonResult(
      confirmed: false,
      statusCode: 0,
      message: 'Erro ao iniciar integração E-Desk: $e',
      responseBody: stackTrace.toString(),
    );
  }
}

/// ================================================================

/// RESULTADO DA EXECUÇÃO PYTHON

/// ================================================================

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
