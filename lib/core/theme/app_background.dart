import 'package:flutter/material.dart';
import 'app_appearance.dart';
import 'app_palette.dart';

String backgroundAsset(AppVisualTheme theme) =>
    'assets/backgrounds/theme_${switch (theme) {
      AppVisualTheme.light => 'claro',
      AppVisualTheme.intermediate => 'intermediario',
      AppVisualTheme.black => 'black',
      AppVisualTheme.petroleum => 'petroleo',
      AppVisualTheme.ocean => 'oceano',
      _ => 'escuro',
    }}.png';

class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppVisualTheme>(
        valueListenable: AppAppearance.instance,
        child: child,
        builder: (context, theme, content) =>
            Stack(fit: StackFit.expand, children: [
          ColoredBox(color: AppPalette.background),
          Positioned.fill(
            child: ExcludeSemantics(
                child: IgnorePointer(
                    child: Image.asset(
              backgroundAsset(theme),
              fit: BoxFit.cover,
              alignment: Alignment.bottomCenter,
              filterQuality: FilterQuality.low,
              errorBuilder: (_, error, stack) => const SizedBox.shrink(),
            ))),
          ),
          Positioned.fill(
              child: IgnorePointer(
                  child: ColoredBox(
                      color: AppPalette.background
                          .withValues(alpha: AppPalette.dark ? .16 : .10)))),
          content!,
        ]),
      );
}
