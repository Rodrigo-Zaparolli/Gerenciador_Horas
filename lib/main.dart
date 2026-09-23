import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'package:gerenciador_horas/app/app.dart';
import 'package:gerenciador_horas/firebase_options.dart';
import 'package:gerenciador_horas/core/platform/platform_init.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await initializePlatform();

  runApp(const GerenciadorHorasApp());
}
