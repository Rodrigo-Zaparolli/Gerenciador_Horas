import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'package:gerenciador_horas/features/auth/screens/login_screen.dart';

import 'main_navigation_screen.dart';

class GerenciadorHorasApp extends StatelessWidget {
  const GerenciadorHorasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // ==========================================================
      // CONFIGURAÇÕES GERAIS
      // ==========================================================

      title: 'Gestão de Horas e Projetos',

      debugShowCheckedModeBanner: false,

      // ==========================================================
      // LOCALIZAÇÃO
      // ==========================================================
      //
      // IMPORTANTE:
      //
      // O DatePicker, TimePicker e outros componentes Material
      // precisam de MaterialLocalizations.
      //
      // Sem essa configuração, ao abrir o DatePicker o Flutter
      // pode gerar:
      //
      // "No MaterialLocalizations found"
      //
      // e apresentar a tela vermelha.
      // ==========================================================

      locale: const Locale('pt', 'BR'),

      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      supportedLocales: const [
        Locale('pt', 'BR'),
        Locale('en', 'US'),
      ],

      // ==========================================================
      // TEMA
      // ==========================================================

      theme: AppTheme.dark,

      // ==========================================================
      // CONTROLE AUTOMÁTICO DE AUTENTICAÇÃO
      // ==========================================================

      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // ======================================================
          // AGUARDANDO FIREBASE
          // ======================================================

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          // ======================================================
          // ERRO
          // ======================================================

          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Erro ao verificar autenticação:\n\n'
                    '${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            );
          }

          // ======================================================
          // USUÁRIO LOGADO
          // ======================================================

          if (snapshot.hasData && snapshot.data != null) {
            return const MainNavigationScreen();
          }

          // ======================================================
          // USUÁRIO NÃO LOGADO
          // ======================================================

          return LoginScreen(
            onLoginSuccess: () {
              // ==================================================
              // NÃO É NECESSÁRIO NAVEGAR MANUALMENTE.
              //
              // O FirebaseAuth.authStateChanges() detectará
              // automaticamente o login e reconstruirá esta tela.
              // ==================================================
            },
          );
        },
      ),
    );
  }
}
