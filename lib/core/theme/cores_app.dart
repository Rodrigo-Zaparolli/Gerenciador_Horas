import 'package:flutter/material.dart';

/// ===============================================================
/// CORES GERAIS DO APLICATIVO
/// ===============================================================
class CoresApp {
  CoresApp._();

  // =============================================================
  // FUNDOS
  // =============================================================

  static const Color fundo = Color(0xFF121212);

  static const Color fundoSecundario = Color(0xFF181824);

  static const Color superficie = Color(0xFF1E1E2E);

  static const Color superficieClara = Color(0xFF2D2D44);

  static const Color superficieEscura = Color(0xFF161622);

  // =============================================================
  // CORES PRINCIPAIS
  // =============================================================

  static const Color primaria = Color(0xFF2196F3);

  static const Color secundaria = Color(0xFF03DAC6);

  static const Color destaque = Color(0xFF00FFCC);

  // =============================================================
  // TEXTOS
  // =============================================================

  static const Color textoPrincipal = Color(0xFFE0E0E0);

  static const Color textoSecundario = Color(0xFFA0A0A0);

  static const Color textoFraco = Color(0xFF666666);

  static const Color textoDesabilitado = Color(0xFF555555);

  // =============================================================
  // ESTADOS
  // =============================================================

  static const Color sucesso = Color(0xFF4CAF50);

  static const Color erro = Color(0xFFCF6679);

  static const Color aviso = Color(0xFFFFC107);

  static const Color informacao = Color(0xFF2196F3);

  // =============================================================
  // DESTAQUES
  // =============================================================

  static const Color destaqueAmarelo = Color(0xFFFFD740);

  static const Color destaqueVermelho = Color(0xFFFF5252);

  static const Color destaqueVerde = Color(0xFF69F0AE);

  static const Color destaqueAzul = Color(0xFF40C4FF);

  // =============================================================
  // BORDAS
  // =============================================================

  static const Color borda = Color(0xFF303040);

  static const Color bordaSuave = Color(0xFF252535);

  // =============================================================
  // SOMBRAS / OVERLAYS
  // =============================================================

  static const Color overlay = Color(0x66000000);

  /// Compatibilidade com telas que utilizem fundoEscuro.
  static const Color fundoEscuro = Color(0xFF10101A);
}

/// ===============================================================
/// CORES ESPECÍFICAS DO DASHBOARD
/// ===============================================================
class CoresDashboard {
  CoresDashboard._();

  // =============================================================
  // ESTRUTURA
  // =============================================================

  static const Color fundo = Color(0xFF10101A);

  static const Color fundoSecundario = Color(0xFF161622);

  static const Color card = Color(0xFF1E1E2E);

  static const Color cardHover = Color(0xFF25253A);

  static const Color cabecalhoTabela = Color(0xFF10101A);

  // =============================================================
  // GRÁFICOS
  // =============================================================

  static const Color graficoHoras = Color(0xFF00FFCC);

  static const Color graficoProjetos = Color(0xFF2196F3);

  static const Color graficoConcluidos = Color(0xFF4CAF50);

  static const Color graficoAtrasados = Color(0xFFFF5252);

  static const Color graficoAndamento = Color(0xFFFFC107);

  // =============================================================
  // STATUS
  // =============================================================

  static const Color statusInicial = Color(0xFFFFA726);

  static const Color statusTrabalhando = Color(0xFF69F0AE);

  static const Color statusAndamento = Color(0xFF40C4FF);

  static const Color statusFinalizado = Color(0xFF90CAF9);

  // =============================================================
  // TABELA DE PROJETOS
  // =============================================================

  static const Color tabelaFundo = Color(0xFF161622);

  static const Color tabelaCabecalho = Color(0xFF10101A);

  static const Color tabelaLinhaSelecionada = Color(0x2600FFCC);

  static const Color tabelaLinhaExpandida = Color(0x0D00FFCC);

  static const Color tabelaLinhaEtapa = Color(0x081FFFFF);

  static const Color tabelaLinhaExecucao = Color(0x990D2137);

  static const Color tabelaLinhaRegistrada = Color(0x0D4CAF50);

  static const Color tabelaBorda = Color(0x0FFFFFFF);

  static const Color tabelaDivisor = Color(0x14252535);

  static const Color tabelaHover = Color(0x0DFFFFFF);

  // =============================================================
  // ALERTAS
  // =============================================================

  static const Color alerta = Color(0xFFFFC107);

  static const Color atrasado = Color(0xFFFF5252);

  static const Color proximoVencimento = Color(0xFFFFA726);

  static const Color dentroPrazo = Color(0xFF4CAF50);
}

/// ===============================================================
/// CORES ESPECÍFICAS DAS TELAS
/// ===============================================================
class CoresTelas {
  CoresTelas._();

  // =============================================================
  // LOGIN / AUTENTICAÇÃO
  // =============================================================

  static const Color fundoLogin = Color(0xFF10101A);

  static const Color painelLogin = Color(0xFF1E1E2E);

  // =============================================================
  // FORMULÁRIOS
  // =============================================================

  static const Color campoFormulario = Color(0xFF2D2D44);

  static const Color campoFormularioFoco = Color(0xFF353550);

  // =============================================================
  // MODAIS
  // =============================================================

  static const Color fundoModal = Color(0xFF1E1E2F);

  static const Color fundoModalSecundario = Color(0xFF161622);

  // =============================================================
  // SUPORTE / ATALHOS DE TELA
  // =============================================================

  static const Color fundoSuperficie = Color(0xFF1E1E2E);

  static const Color fundoCard = Color(0xFF1E1E2E);

  static const Color cabecalhoTabela = Color(0xFF161622);

  static const Color fundoPrincipal = Color(0xFF121212);
}

/// ===============================================================
/// DIMENSÕES E TIPOGRAFIA DO APLICATIVO
/// ===============================================================
class TamanhosApp {
  TamanhosApp._();

  // =============================================================
  // TABELAS
  // =============================================================

  static const double tabelaFonteCabecalho = 10;

  static const double tabelaFonte = 10;

  static const double tabelaFonteSecundaria = 9.5;

  static const double tabelaFonteStatus = 9.5;

  static const double tabelaFonteAcao = 9.5;

  static const double tabelaEspacamentoColunas = 8;

  static const double tabelaMargemHorizontal = 8;

  static const double tabelaAlturaMinima = 350;

  // =============================================================
  // ÍCONES
  // =============================================================

  static const double iconeTabela = 17;

  static const double iconeAcao = 18;

  static const double iconeStatus = 14;

  // =============================================================
  // BORDAS
  // =============================================================

  static const double raioTabela = 12;

  static const double raioBadge = 5;

  static const double raioBotao = 6;

  static const double espessuraBorda = 0.8;

  // =============================================================
  // ESPAÇAMENTOS
  // =============================================================

  static const double espacamentoPequeno = 4;

  static const double espacamentoMedio = 8;

  static const double espacamentoGrande = 12;
}
