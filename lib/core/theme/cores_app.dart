import 'package:flutter/material.dart';

/// ===============================================================
/// CORES GERAIS DO APLICATIVO (MIDNIGHT EXECUTIVE TECH)
/// ===============================================================
class CoresApp {
  CoresApp._();

  // =============================================================
  // FUNDOS (Tons profundos de azul-marinho e slate)
  // =============================================================

  static const Color fundo =
      Color(0xFF0B0F19); // Fundo principal ultra-profundo
  static const Color fundoSecundario =
      Color(0xFF111827); // Fundo secundário sutil
  static const Color superficie =
      Color(0xFF1E293B); // Superfície de cartões padrão
  static const Color superficieClara = Color(0xFF334155); // Superfície elevada
  static const Color superficieEscura =
      Color(0xFF0F172A); // Superfície de destaque escuro

  // =============================================================
  // CORES PRINCIPAIS
  // =============================================================

  static const Color primaria =
      Color(0xFF0EA5E9); // Azul Ciano moderno e vibrante
  static const Color secundaria = Color(0xFF38BDF8); // Azul claro complementar
  static const Color destaque =
      Color(0xFF00F2FE); // Destaque tecnológico neon suave

  // =============================================================
  // TEXTOS
  // =============================================================

  static const Color textoPrincipal =
      Color(0xFFF8FAFC); // Branco quase puro para máxima leitura
  static const Color textoSecundario =
      Color(0xFF94A3B8); // Cinza slate elegante
  static const Color textoFraco =
      Color(0xFF64748B); // Cinza sutil para detalhes
  static const Color textoDesabilitado = Color(0xFF475569);

  // =============================================================
  // ESTADOS
  // =============================================================

  static const Color sucesso = Color(0xFF10B981); // Verde esmeralda moderno
  static const Color erro = Color(0xFFEF4444); // Vermelho vivo refinado
  static const Color aviso = Color(0xFFF59E0B); // Âmbar elegante
  static const Color informacao = Color(0xFF0EA5E9); // Azul informativo

  // =============================================================
  // DESTAQUES
  // =============================================================

  static const Color destaqueAmarelo = Color(0xFFFBBF24);
  static const Color destaqueVermelho = Color(0xFFF87171);
  static const Color destaqueVerde = Color(0xFF34D399);
  static const Color destaqueAzul = Color(0xFF38BDF8);

  // =============================================================
  // BORDAS
  // =============================================================

  static const Color borda = Color(0xFF334155); // Linhas de contorno discretas
  static const Color bordaSuave = Color(0xFF1E293B);

  // =============================================================
  // SOMBRAS / OVERLAYS
  // =============================================================

  static const Color overlay = Color(0x80000000);

  /// Compatibilidade com telas que utilizem fundoEscuro.
  static const Color fundoEscuro = Color(0xFF0B0F19);
}

/// ===============================================================
/// CORES ESPECÍFICAS DO DASHBOARD
/// ===============================================================
class CoresDashboard {
  CoresDashboard._();

  // =============================================================
  // ESTRUTURA
  // =============================================================

  static const Color fundo = Color(0xFF0B0F19);
  static const Color fundoSecundario = Color(0xFF111827);
  static const Color card = Color(0xFF1E293B);
  static const Color cardHover = Color(0xFF273548);
  static const Color cabecalhoTabela = Color(0xFF0F172A);

  // =============================================================
  // GRÁFICOS
  // =============================================================

  static const Color graficoHoras = Color(0xFF00F2FE);
  static const Color graficoProjetos = Color(0xFF0EA5E9);
  static const Color graficoConcluidos = Color(0xFF10B981);
  static const Color graficoAtrasados = Color(0xFFEF4444);
  static const Color graficoAndamento = Color(0xFFF59E0B);

  // =============================================================
  // STATUS
  // =============================================================

  static const Color statusInicial = Color(0xFFF59E0B);
  static const Color statusTrabalhando = Color(0xFF34D399);
  static const Color statusAndamento = Color(0xFF38BDF8);
  static const Color statusFinalizado = Color(0xFF60A5FA);

  // =============================================================
  // TABELA DE PROJETOS
  // =============================================================

  static const Color tabelaFundo = Color(0xFF111827);
  static const Color tabelaCabecalho = Color(0xFF0F172A);
  static const Color tabelaLinhaSelecionada = Color(0x330EA5E9);
  static const Color tabelaLinhaExpandida = Color(0x1A0EA5E9);
  static const Color tabelaLinhaEtapa = Color(0x140EA5E9);
  static const Color tabelaLinhaExecucao = Color(0x991E293B);
  static const Color tabelaLinhaRegistrada = Color(0x1A10B981);
  static const Color tabelaBorda = Color(0x14FFFFFF);
  static const Color tabelaDivisor = Color(0x1A334155);
  static const Color tabelaHover = Color(0x0DFFFFFF);

  // =============================================================
  // ALERTAS
  // =============================================================

  static const Color alerta = Color(0xFFF59E0B);
  static const Color atrasado = Color(0xFFEF4444);
  static const Color proximoVencimento = Color(0xFFF59E0B);
  static const Color dentroPrazo = Color(0xFF10B981);
}

/// ===============================================================
/// CORES ESPECÍFICAS DAS TELAS
/// ===============================================================
class CoresTelas {
  CoresTelas._();

  // =============================================================
  // LOGIN / AUTENTICAÇÃO
  // =============================================================

  static const Color fundoLogin = Color(0xFF0B0F19);
  static const Color painelLogin = Color(0xFF1E293B);

  // =============================================================
  // FORMULÁRIOS
  // =============================================================

  static const Color campoFormulario = Color(0xFF334155);
  static const Color campoFormularioFoco = Color(0xFF475569);

  // =============================================================
  // MODAIS
  // =============================================================

  static const Color fundoModal = Color(0xFF1E293B);
  static const Color fundoModalSecundario = Color(0xFF111827);

  // =============================================================
  // SUPORTE / ATALHOS DE TELA
  // =============================================================

  static const Color fundoSuperficie = Color(0xFF1E293B);
  static const Color fundoCard = Color(0xFF1E293B);
  static const Color cabecalhoTabela = Color(0xFF111827);
  static const Color fundoPrincipal = Color(0xFF0B0F19);
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
