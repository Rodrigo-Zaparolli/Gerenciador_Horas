import 'package:gerenciador_horas/data/services/edesk_service.dart';

/// ================================================================
/// TESTE TEMPORÁRIO DO E-DESK
/// ================================================================
///
/// Este arquivo serve apenas para verificar:
///
/// 1. conexão com o E-Desk;
/// 2. autenticação da sessão;
/// 3. carregamento da página Retroativo;
/// 4. existência dos campos hidden do ASP.NET;
/// 5. envio de um único registro.
///
/// NÃO colocar cookies reais neste arquivo.
///
/// Os cookies devem ser informados temporariamente pelo código
/// de chamada, ou por outro mecanismo seguro de sessão.
///
class TesteEdesk {
  static Future<void> executar({
    required Map<String, String> cookies,
    required Uri pageUri,
  }) async {
    print('');
    print('================================================');
    print('          TESTE DE COMUNICAÇÃO E-DESK');
    print('================================================');
    print('');

    final service = EdeskService();

    try {
      // ==========================================================
      // 1. CONFIGURAR SESSÃO
      // ==========================================================

      service.setSessionCookies(cookies);

      print('1. Sessão');
      print('   Cookies configurados: ${service.hasSession}');
      print('');

      // ==========================================================
      // 2. DADOS DE TESTE
      // ==========================================================
      //
      // IMPORTANTE:
      // Os valores abaixo são apenas um exemplo.
      //
      // Depois vamos substituir pelos dados reais do trabalho
      // selecionado na TarefasScreen.
      //

      final work = EdeskWorkData(
        pageUri: pageUri,

        // Não colocar IDs reais aqui permanentemente.
        solicitacao: 'TESTE',

        idTrabalho: 'TESTE',

        data: '07/09/2026',

        horaInicio: '08:00',

        horaFim: '09:00',

        tipoRegistro: 'TESTE',

        tarefa: 'Teste de integração E-Desk',

        descricao: 'Registro temporário utilizado para testar '
            'a comunicação entre o Gerenciador de Horas '
            'e o E-Desk.',
      );

      // ==========================================================
      // 3. ENVIAR
      // ==========================================================

      print('2. Abrindo página do Retroativo...');
      print('   URL configurada: SIM');
      print('');

      print('3. Enviando solicitação...');
      print('');

      final result = await service.sendWork(work);

      // ==========================================================
      // 4. RESULTADO
      // ==========================================================

      print('================================================');
      print('                 RESULTADO');
      print('================================================');
      print('');

      print('HTTP: ${result.statusCode}');

      print(
        'Confirmado pelo serviço: ${result.confirmed}',
      );

      print(
        'Mensagem: ${result.message}',
      );

      print('');

      if (result.confirmed) {
        print('-----------------------------------------------');
        print('SUCESSO NA COMUNICAÇÃO');
        print('-----------------------------------------------');
        print('');
        print(
          'O servidor respondeu sem indicar erro explícito.',
        );
        print('');
        print(
          'ATENÇÃO: isso ainda não significa que o registro '
          'foi definitivamente confirmado no E-Desk.',
        );
      } else {
        print('-----------------------------------------------');
        print('ENVIO NÃO CONFIRMADO');
        print('-----------------------------------------------');
        print('');
        print(result.message);
      }

      print('');
      print('================================================');
      print('              FIM DO TESTE');
      print('================================================');
      print('');
    } on EdeskAuthenticationException catch (e) {
      print('');
      print('================================================');
      print('             ERRO DE AUTENTICAÇÃO');
      print('================================================');
      print('');
      print(e.message);
      print('');
      print(
        'O aplicativo conseguiu chegar ao E-Desk, '
        'mas a sessão não foi reconhecida como autenticada.',
      );
      print('');
    } on EdeskException catch (e) {
      print('');
      print('================================================');
      print('                 ERRO E-DESK');
      print('================================================');
      print('');
      print(e.message);
      print('');
    } catch (e) {
      print('');
      print('================================================');
      print('                 ERRO INESPERADO');
      print('================================================');
      print('');
      print(e);
      print('');
    } finally {
      service.dispose();
    }
  }
}
