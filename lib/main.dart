import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gerenciador_horas/features/auth/screens/login_screen.dart';
import 'package:gerenciador_horas/app/main_navigation_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'AIzaSyCfpnLQ4-npn_S1d9g62Eg32eYfj9wu7M8',
      authDomain: 'gerenciador-horas.firebaseapp.com',
      projectId: 'gerenciador-horas',
      storageBucket: 'gerenciador-horas.firebasestorage.app',
      messagingSenderId: '318491809401',
      appId: '1:318491809401:web:6e512fe183f7a4f4fe66a8',
      measurementId: 'G-Q9CH5TKYG3',
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gerenciador de Horas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF12121B),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: Colors.cyanAccent),
              ),
            );
          }

          // Se o usuário está logado, vai direto para a navegação principal do app
          if (snapshot.hasData) {
            return const MainNavigationScreen();
          }

          // Caso contrário, exibe a tela de login
          return LoginScreen(
            onLoginSuccess: () {},
          );
        },
      ),
    );
  }
}
