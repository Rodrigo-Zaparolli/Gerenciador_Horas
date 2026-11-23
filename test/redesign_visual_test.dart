import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/platform/local_user_state.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_background.dart';
import 'package:gerenciador_horas/core/theme/background_decoration.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'package:gerenciador_horas/core/theme/app_visuals.dart';
import 'package:gerenciador_horas/shared/widgets/redesign_components.dart';

const themes = [
  AppVisualTheme.light,
  AppVisualTheme.dark,
  AppVisualTheme.intermediate,
  AppVisualTheme.black,
  AppVisualTheme.petroleum,
  AppVisualTheme.ocean
];

class _StatefulContent extends StatefulWidget {
  const _StatefulContent();
  @override
  State<_StatefulContent> createState() => _StatefulContentState();
}

class _StatefulContentState extends State<_StatefulContent> {
  int count = 0;
  @override
  Widget build(BuildContext context) => TextButton(
      onPressed: () => setState(() => count++), child: Text('Estado: $count'));
}

void main() {
  tearDown(() {
    AppAppearance.instance.value = AppVisualTheme.light;
    BackgroundDecoration.instance.value = true;
    LocalUserState.memory = null;
  });
  test('six original backgrounds map uniquely, decoration preference is local',
      () {
    expect(themes.map(backgroundAsset).toSet().length, 6);
    LocalUserState.memory = {};
    BackgroundDecoration.instance.select(false);
    BackgroundDecoration.instance.value = true;
    BackgroundDecoration.instance.restore();
    expect(BackgroundDecoration.instance.value, false);
    BackgroundDecoration.instance.select(true);
    BackgroundDecoration.instance.restore();
    expect(BackgroundDecoration.instance.value, true);
  });
  testWidgets(
      'theme chooses its background and ignores legacy decoration opt-out',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: AppBackground(
            child: Scaffold(
                backgroundColor: Colors.transparent,
                body: _StatefulContent()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Estado: 0'));
    await tester.pump();
    for (final theme in themes) {
      AppAppearance.instance.value = theme;
      await tester.pumpAndSettle();
      expect(find.text('Estado: 1'), findsOneWidget);
      expect(tester.widget<Image>(find.byType(Image)).image,
          AssetImage(backgroundAsset(theme)));
    }
    BackgroundDecoration.instance.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Estado: 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'theme menu applies complete theme without a separate background switch',
      (tester) async {
    LocalUserState.memory = {};
    AppAppearance.instance.value = AppVisualTheme.ocean;
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ThemeToggleButton())));
    await tester.tap(find.byTooltip('Escolher tema'));
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsNothing);
    expect(find.text('Fundo decorativo'), findsNothing);
    await tester.tap(find.text('Black'));
    await tester.pumpAndSettle();
    expect(AppAppearance.instance.value, AppVisualTheme.black);
    expect(backgroundAsset(AppAppearance.instance.value),
        endsWith('theme_black.png'));
    expect(tester.takeException(), isNull);
  });
  test('panel surfaces change with each of the six themes', () {
    final gradients = <String>{};
    for (final theme in themes) {
      AppAppearance.instance.value = theme;
      gradients.add(
          (AppVisuals.panel().gradient! as LinearGradient).colors.toString());
      expect(AppTheme.light.colorScheme.surface, isNotNull);
    }
    expect(gradients.length, themes.length);
  });
  for (final theme in themes) {
    for (final width in [1093.0, 1366.0, 1600.0, 1920.0, 390.0]) {
      testWidgets(
          'shared redesign $theme at $width preserves callbacks and contrast',
          (tester) async {
        tester.view.physicalSize = Size(width, 768);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        AppAppearance.instance.value = theme;
        var calls = 0;
        await tester.pumpWidget(MaterialApp(
            theme:
                theme.mode == ThemeMode.dark ? AppTheme.dark : AppTheme.light,
            home: AppBackground(
                child: Scaffold(
                    backgroundColor: Colors.transparent,
                    body: SingleChildScrollView(
                        padding: const EdgeInsets.all(14),
                        child: Column(children: [
                          AppPageHero(
                              title: 'Projetos e trabalho',
                              subtitle: 'Dados preservados',
                              icon: Icons.work_outline,
                              trailing: SizedBox(
                                  width: 310,
                                  child: AppMetricCard(
                                      icon: Icons.schedule,
                                      label: 'Horas',
                                      value: '361:46',
                                      description: 'Apontamentos',
                                      onTap: () => calls++))),
                          const SizedBox(height: 12),
                          AppMetricCard(
                              icon: Icons.check,
                              label: 'Concluídos',
                              value: '21',
                              accent: AppPalette.success,
                              onTap: () => calls++),
                        ]))))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('361:46'));
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(AppPalette.contrast(AppPalette.text, AppPalette.surface),
            greaterThanOrEqualTo(4.5));
      });
    }
  }
}
