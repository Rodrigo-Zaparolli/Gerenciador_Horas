import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:gerenciador_horas/app/main_navigation_screen.dart';
import 'package:gerenciador_horas/features/auth/screens/login_screen.dart';
import 'package:gerenciador_horas/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ============================================================
  // INICIALIZAÇÃO DO FIREBASE
  // ============================================================

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ============================================================
  // INICIA O APLICATIVO
  // ============================================================

  runApp(const MyApp());
}

// ================================================================
// APLICATIVO PRINCIPAL
// ================================================================

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gerenciador de Horas',

      debugShowCheckedModeBanner: false,

      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF12121B),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyan,
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1C1C29),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),

      // ==========================================================
      // CONTROLE DE AUTENTICAÇÃO
      // ==========================================================

      home: const AuthGate(),
    );
  }
}

// ================================================================
// AUTH GATE
// ================================================================
//
// Esta tela observa o FirebaseAuth.
//
// Usuário autenticado:
//     -> MainNavigationScreen
//
// Usuário não autenticado:
//     -> LoginScreen
//
// Quando o usuário clicar em "Sair" no Cabecalho:
//
//     FirebaseAuth.instance.signOut();
//
// O authStateChanges() detectará automaticamente a alteração
// e o aplicativo voltará para o LoginScreen.
// ================================================================

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // ========================================================
        // AGUARDANDO FIREBASE
        // ========================================================

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        // ========================================================
        // ERRO
        // ========================================================

        if (snapshot.hasError) {
          return _ErrorScreen(
            error: snapshot.error.toString(),
          );
        }

        // ========================================================
        // USUÁRIO LOGADO
        // ========================================================

        if (snapshot.hasData) {
          return const MainNavigationScreen();
        }

        // ========================================================
        // USUÁRIO NÃO LOGADO
        // ========================================================

        return LoginScreen(
          onLoginSuccess: () {
            // Não é necessário navegar manualmente.
            //
            // Quando o LoginScreen executar:
            //
            // FirebaseAuth.instance.signIn...
            //
            // o authStateChanges() será atualizado
            // automaticamente.
          },
        );
      },
    );
  }
}

// ================================================================
// TELA DE CARREGAMENTO
// ================================================================

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12121B),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 420,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 32,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ==================================================
                // ÍCONE
                // ==================================================

                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C29),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.08),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.35),
                        blurRadius: 25,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.access_time_rounded,
                    size: 48,
                    color: Colors.cyanAccent,
                  ),
                ),

                const SizedBox(height: 28),

                // ==================================================
                // NOME
                // ==================================================

                const Text(
                  'Gerenciador de Horas',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: Colors.white,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  'Gerenciamento de horas e projetos',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.55),
                  ),
                ),

                const SizedBox(height: 38),

                // ==================================================
                // PROGRESSO
                // ==================================================

                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.cyanAccent,
                  ),
                ),

                const SizedBox(height: 18),

                Text(
                  'Inicializando aplicativo...',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.55),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ================================================================
// TELA DE ERRO
// ================================================================

class _ErrorScreen extends StatelessWidget {
  final String error;

  const _ErrorScreen({
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12121B),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 500,
          ),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ==================================================
                // ÍCONE DE ERRO
                // ==================================================

                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.error_outline_rounded,
                    size: 42,
                    color: Colors.redAccent,
                  ),
                ),

                const SizedBox(height: 24),

                // ==================================================
                // TÍTULO
                // ==================================================

                const Text(
                  'Não foi possível iniciar o aplicativo',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  'Ocorreu um problema ao inicializar o Firebase.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.60),
                  ),
                ),

                const SizedBox(height: 24),

                // ==================================================
                // ERRO TÉCNICO
                // ==================================================

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.20),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.06),
                    ),
                  ),
                  child: Text(
                    error,
                    textAlign: TextAlign.center,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withOpacity(0.35),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
