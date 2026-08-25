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
      title: 'Gestão de Horas e Projetos',
      debugShowCheckedModeBanner: false,

      // ==========================================================
      // LOCALIZAÇÃO DO FLUTTER
      // ==========================================================
      //
      // Necessário para componentes como:
      // - DatePicker
      // - TimePicker
      // - AlertDialog
      // - mensagens e textos internos do Material
      //
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
          // ------------------------------------------------------
          // ENQUANTO O FIREBASE ESTÁ VERIFICANDO O USUÁRIO
          // ------------------------------------------------------

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          // ------------------------------------------------------
          // USUÁRIO LOGADO
          // ------------------------------------------------------

          if (snapshot.hasData && snapshot.data != null) {
            return const MainNavigationScreen();
          }

          // ------------------------------------------------------
          // USUÁRIO NÃO LOGADO
          // ------------------------------------------------------

          return LoginScreen(
            onLoginSuccess: () {
              // --------------------------------------------------
              // NÃO PRECISAMOS MAIS FAZER pushReplacement AQUI.
              //
              // O authStateChanges() detectará automaticamente
              // quando o usuário estiver autenticado.
              // --------------------------------------------------
            },
          );
        },
      ),
    );
  }
}
