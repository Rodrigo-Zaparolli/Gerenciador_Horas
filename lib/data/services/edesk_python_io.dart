import 'dart:convert';
import 'dart:io';

Future<EdeskPythonResult> executarPythonEdesk({
  required String requestJson,
  required bool enviar,

  // Mantém main.py como padrão para não quebrar
  // a integração atual de comentários.
  String script = 'edesk_comentario.py',
}) async {
  Directory? tempDirectory;

  try {
    final pythonExe = Platform.isWindows
        ? r'D:\APP\gerenciador_horas\.venv\Scripts\python.exe'
        : 'python3';

    final scriptPath = Platform.isWindows
        ? 'D:\\APP\\gerenciador_horas\\edesk_bot\\$script'
        : 'edesk_bot/$script';

    final pythonFile = File(pythonExe);

    if (!await pythonFile.exists()) {
      return const EdeskPythonResult(
        confirmed: false,
        statusCode: 0,
        message: 'Python não encontrado em D:\\APP\\gerenciador_horas\\.venv.',
        responseBody: '',
      );
    }

    final scriptFile = File(scriptPath);

    if (!await scriptFile.exists()) {
      return EdeskPythonResult(
        confirmed: false,
        statusCode: 0,
        message: 'O arquivo edesk_bot/$script não foi encontrado.',
        responseBody: '',
      );
    }

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
    print('[E-Desk] ============================================');
    print('[E-Desk] Executando Python.');
    print(
      '[E-Desk] Modo: ${enviar ? 'ENVIO' : 'TESTE'}',
    );
    print('[E-Desk] Python: $pythonExe');
    print('[E-Desk] Script: $scriptPath');
    print('[E-Desk] Request: ${requestFile.path}');
    print('[E-Desk] ============================================');

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
      workingDirectory: r'D:\APP\gerenciador_horas',
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

    final stdoutDone = processo.stdout
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

    final stderrDone = processo.stderr
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
    // AGUARDA PYTHON
    // ============================================================

    final exitCode = await processo.exitCode;

    await stdoutDone.asFuture<void>();
    await stderrDone.asFuture<void>();

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
