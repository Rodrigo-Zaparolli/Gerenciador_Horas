import 'package:flutter/material.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_visuals.dart';

/// Reusable presentation receiving the existing values and actions.
class AppMetricCard extends StatelessWidget {
  const AppMetricCard(
      {super.key,
      required this.icon,
      required this.label,
      required this.value,
      this.description,
      this.accent,
      this.emphasizeValue = false,
      this.compact = false,
      this.onTap});
  final bool emphasizeValue;
  final bool compact;
  final IconData icon;
  final String label, value;
  final String? description;
  final Color? accent;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppPalette.accent;
    return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
              decoration:
                  AppVisuals.panel(accent: color, prominent: true, radius: 14),
              padding: EdgeInsets.symmetric(
                  horizontal: compact ? 14 : 18, vertical: compact ? 8 : 12),
              child: Row(children: [
                Container(
                    width: compact ? 42 : 58,
                    height: compact ? 42 : 58,
                    decoration: AppVisuals.iconTile(accent: color),
                    child: Icon(icon,
                        color: color,
                        size: 32,
                        shadows: AppPalette.dark
                            ? [
                                Shadow(
                                    color: color.withValues(alpha: .6),
                                    blurRadius: 9)
                              ]
                            : null)),
                const SizedBox(width: 11),
                Expanded(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppPalette.secondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: emphasizeValue ? color : AppPalette.text,
                              fontSize: compact ? 24 : 28,
                              height: 1.1,
                              fontWeight: FontWeight.w800)),
                      if (description != null)
                        Text(description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppPalette.secondary, fontSize: 12)),
                    ])),
                if (onTap != null)
                  Icon(Icons.open_in_new, size: 14, color: color),
              ])),
        ));
  }
}

class AppPageHero extends StatelessWidget {
  const AppPageHero(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.icon,
      this.trailing});
  final String title, subtitle;
  final IconData icon;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: AppVisuals.panel(prominent: true, waves: true),
        child: LayoutBuilder(builder: (context, box) {
          final heading = Row(children: [
            Container(
                width: 64,
                height: 64,
                decoration: AppVisuals.iconTile(),
                child: Icon(icon, color: AppPalette.accent, size: 38)),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  Text(title,
                      style: TextStyle(
                          color: AppPalette.text,
                          fontSize: 30,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style:
                          TextStyle(color: AppPalette.secondary, fontSize: 14)),
                ])),
          ]);
          if (trailing == null) return heading;
          if (box.maxWidth < 900)
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [heading, const SizedBox(height: 12), trailing!]);
          return Row(children: [
            Expanded(child: heading),
            const SizedBox(width: 18),
            trailing!
          ]);
        }),
      );
}

/// Informational footer from the visual reference, without decorative buttons.
class AppSuggestionsBanner extends StatelessWidget {
  const AppSuggestionsBanner({super.key, required this.items});
  final List<(IconData, String, String)> items;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final title = Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lightbulb_outline, color: AppPalette.accent, size: 32),
          const SizedBox(width: 12),
          Text('Sugestões de melhoria',
              style: TextStyle(
                  color: AppPalette.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
        ]);
        final entries = items
            .map((item) => Row(children: [
                  Container(
                      width: 48,
                      height: 48,
                      decoration: AppVisuals.iconTile(),
                      child: Icon(item.$1, color: AppPalette.accent, size: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        Text(item.$2,
                            style: TextStyle(
                                color: AppPalette.text,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(item.$3,
                            style: TextStyle(
                                color: AppPalette.secondary, fontSize: 11)),
                      ])),
                ]))
            .toList();
        return Container(
            padding: const EdgeInsets.all(16),
            decoration: AppVisuals.panel(prominent: true),
            child: box.maxWidth >= 1100
                ? Row(children: [
                    title,
                    const SizedBox(width: 28),
                    for (final entry in entries)
                      Expanded(
                          child: Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: entry))
                  ])
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        title,
                        for (final entry in entries)
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: entry)
                      ]));
      });
}
