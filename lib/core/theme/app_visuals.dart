import 'package:flutter/material.dart';
import 'app_palette.dart';
import 'luminous_decoration.dart';

/// Shared presentation only; never changes data or action callbacks.
class AppVisuals {
  AppVisuals._();
  static const cardRadius = 14.0;
  static const buttonRadius = 10.0;
  static const buttonHeight = 40.0;
  static const cardPadding = EdgeInsets.all(12);
  static Color get violet =>
      AppPalette.dark ? const Color(0xFFC18AFF) : const Color(0xFF7745AE);
  static Color get edge => AppPalette.dark
      ? AppPalette.accent.withValues(alpha: .72)
      : AppPalette.primary.withValues(alpha: .38);
  static BoxDecoration panel(
      {Color? accent,
      double radius = 16,
      bool prominent = false,
      bool waves = false}) {
    final color = accent ?? AppPalette.accent;
    return LuminousDecoration(
      accent: color,
      waves: waves && AppPalette.dark,
      gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
                color.withValues(alpha: AppPalette.dark ? .10 : .045),
                AppPalette.surface),
            AppPalette.field,
            Color.alphaBlend(
                color.withValues(alpha: AppPalette.dark ? .06 : .045),
                AppPalette.background),
          ]),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
          color: accent == null
              ? edge
              : color.withValues(alpha: AppPalette.dark ? .75 : .45)),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withValues(alpha: AppPalette.dark ? .16 : .045),
            blurRadius: 12,
            offset: const Offset(0, 4)),
        if (AppPalette.dark && prominent)
          BoxShadow(
              color: color.withValues(alpha: .45),
              blurRadius: 10,
              spreadRadius: .5),
      ],
    );
  }

  static BoxDecoration iconTile({Color? accent, double radius = 12}) {
    final color = accent ?? AppPalette.accent;
    return BoxDecoration(
      gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: AppPalette.dark ? .25 : .15),
            color.withValues(alpha: .045)
          ]),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: color.withValues(alpha: .35)),
      boxShadow: AppPalette.dark
          ? [
              BoxShadow(
                  color: color.withValues(alpha: .22),
                  blurRadius: 10,
                  spreadRadius: 1)
            ]
          : null,
    );
  }

  static Color get divider => AppPalette.border.withValues(alpha: 0.55);
  static List<BoxShadow> get shadows => [
        BoxShadow(
          color: Colors.black.withValues(alpha: AppPalette.dark ? 0.14 : 0.045),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ];
  static BoxDecoration get card => panel(radius: cardRadius);
}
