// ignore_for_file: depend_on_referenced_packages
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' show Firebase;
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:gerenciador_horas/core/platform/local_user_state.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_background.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'package:gerenciador_horas/data/services/time_log_store.dart';
import 'package:gerenciador_horas/data/services/user_cache.dart';
import 'package:gerenciador_horas/features/work_formats/work_formats_screen.dart';
import 'package:gerenciador_horas/features/checklist_formats/checklist_formats_screen.dart';
import 'package:gerenciador_horas/features/orientations/orientacao_screen.dart';
import 'package:gerenciador_horas/features/completed_projects/completed_projects_screen.dart';
import 'package:gerenciador_horas/features/solicitacoes/solicitacoes_screen.dart';
import 'package:gerenciador_horas/features/tasks/tarefas_executadas_screen.dart';
import 'package:gerenciador_horas/features/metrics/metrics_screen.dart';
import 'package:gerenciador_horas/features/dashboard/dashboard_screen.dart';
import 'support/redesign_firebase.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late VisualFirestore database;
  setUpAll(() async {
    FirebasePlatform.instance = VisualCore();
    FirebaseAuthPlatform.instance = VisualAuth();
    database = VisualFirestore()..seed();
    if (Platform.environment['REDESIGN_CAPTURE'] != null) database.seedGallery();
    FirebaseFirestorePlatform.instance = database;
    await Firebase.initializeApp();
    {
      for (final name in ['Segoe UI', 'Roboto', 'Ahem']) {
        final loader = FontLoader(name)
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
        await loader.load();
      }
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
    }
  });
  setUp(() {
    LocalUserState.memory = {};
    UserCache()
      ..carregado = true
      ..userName = 'Consultor de teste';
    AppAppearance.instance.value = AppVisualTheme.ocean;
    database.writes = 0;
  });
  tearDown(() {
    UserCache().limparCache();
    LocalUserState.memory = null;
    AppAppearance.instance.value = AppVisualTheme.light;
  });
  for (final screen in [
    'Cadastro',
    'Checklist',
    'Orientacoes',
    'Finalizados',
    'Solicitacoes',
    'Tarefas',
    'Metricas',
    'Dashboard'
  ]) {
    for (final mode in [
      AppVisualTheme.light,
      AppVisualTheme.dark,
      AppVisualTheme.intermediate,
      AppVisualTheme.black,
      AppVisualTheme.petroleum,
      AppVisualTheme.ocean
    ]) {
      for (final width in [1093.0, 1366.0, 1600.0, 1920.0]) {
        testWidgets(
            'real screen $screen / ${mode.preference} at $width with in-memory Firebase, no writes',
            (tester) async {
          tester.view.physicalSize = Size(width, width == 1093 ? 560 : 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          AppAppearance.instance.value = mode;
          final store = TimeLogStore();
          Widget page;
          switch (screen) {
            case 'Cadastro':
              page = WorkFormatsScreen(
                  selectedIndex: 1, onSelectTab: (_) {}, userName: 'Teste');
              break;
            case 'Checklist':
              page = ChecklistFormatsScreen(
                  selectedIndex: 6,
                  onSelectTab: (_) {},
                  userName: 'Teste',
                  timeLogStore: store);
              break;
            case 'Orientacoes':
              page = OrientacaoScreen(
                  selectedIndex: 4, onSelectTab: (_) {}, userName: 'Teste');
              break;
            case 'Finalizados':
              page = CompletedProjectsScreen(
                  firebaseService: FirebaseService(),
                  selectedIndex: 3,
                  onSelectTab: (_) {},
                  userName: 'Teste');
              break;
            case 'Solicitacoes':
              page = SolicitacoesScreen(
                  selectedIndex: 7, onSelectTab: (_) {}, userName: 'Teste');
              break;
            case 'Tarefas':
              page = TarefasScreen(
                  selectedIndex: 5,
                  onSelectTab: (_) {},
                  userName: 'Teste',
                  timeLogStore: store);
              break;
            case 'Metricas':
              page = MetricsScreen(
                  selectedIndex: 2,
                  onSelectTab: (_) {},
                  userName: 'Teste',
                  timeLogStore: store);
              break;
            default:
              page = DashboardScreen(
                  selectedIndex: 0,
                  onSelectTab: (_) {},
                  workFormats: const [],
                  timeLogStore: store);
          }
          final key = GlobalKey();
          await tester.pumpWidget(MaterialApp(
              debugShowCheckedModeBanner: false,
              theme:
                  mode.mode == ThemeMode.dark ? AppTheme.dark : AppTheme.light,
              home: RepaintBoundary(
                  key: key, child: AppBackground(child: page))));
          for (var i = 0; i < 15; i++) {
            await tester.pump(const Duration(milliseconds: 150));
          }
          expect(tester.takeException(), isNull);
          expect(database.writes, 0,
              reason: 'Visual validation may not save data');
          final destination = Platform.environment['REDESIGN_CAPTURE'];
          if (destination != null && width == 1600) {
            await tester.runAsync(() async {
              final boundary = key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
              final image = await boundary.toImage();
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              final file = File('$destination/${mode.preference}/$screen.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
          store.dispose();
        });
      }
    }
  }
}

