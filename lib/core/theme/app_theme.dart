import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  // ============================================================
  // IMAGEM DE FUNDO
  // ============================================================

  static const String caminhoFundo = 'assets/images/fundo.png';

  // ============================================================
  // OPACIDADE DA CAMADA SOBRE A IMAGEM
  // ============================================================

  static const double opacidadeFundo = 0.35;

  // ============================================================
  // TEMA ESCURO
  // ============================================================

  static ThemeData get dark {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF1E1E2C),
      useMaterial3: true,
    );
  }
}
