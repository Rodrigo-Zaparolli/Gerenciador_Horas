import 'package:flutter/material.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'package:gerenciador_horas/features/auth/screens/login_screen.dart';
import 'main_navigation_screen.dart';

class GerenciadorHorasApp extends StatelessWidget {
  const GerenciadorHorasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gestão de Horas e Projetos',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      // Inicia na tela de login
      home: LoginScreen(
        onLoginSuccess: () {
          // Navega para a tela principal substituindo a tela de login
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => const MainNavigationScreen(),
            ),
          );
        },
      ),
    );
  }
}
