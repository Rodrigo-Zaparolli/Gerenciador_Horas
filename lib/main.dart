import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'package:gerenciador_horas/app/app.dart';
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

  runApp(const GerenciadorHorasApp());
}
