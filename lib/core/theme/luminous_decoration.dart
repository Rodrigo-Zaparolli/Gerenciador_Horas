import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Paint-only artwork. It never participates in layout or hit testing.
class LuminousDecoration extends BoxDecoration {
  const LuminousDecoration({
    super.gradient,
    super.color,
    super.image,
    super.backgroundBlendMode,
    super.shape,
    super.border,
    super.borderRadius,
    super.boxShadow,
    required this.accent,
    this.waves = false,
  });
  final Color accent;
  final bool waves;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _LuminousPainter(
      super.createBoxPainter(onChanged), accent, waves, borderRadius);

  @override
  LuminousDecoration copyWith(
          {Color? color,
          DecorationImage? image,
          BoxBorder? border,
          BorderRadiusGeometry? borderRadius,
          List<BoxShadow>? boxShadow,
          Gradient? gradient,
          BlendMode? backgroundBlendMode,
          BoxShape? shape}) =>
      LuminousDecoration(
          accent: accent,
          waves: waves,
          color: color ?? this.color,
          image: image ?? this.image,
          border: border ?? this.border,
          borderRadius: borderRadius ?? this.borderRadius,
          boxShadow: boxShadow ?? this.boxShadow,
          gradient: gradient ?? this.gradient,
          backgroundBlendMode: backgroundBlendMode ?? this.backgroundBlendMode,
          shape: shape ?? this.shape);
}

class _LuminousPainter extends BoxPainter {
  _LuminousPainter(this.base, this.accent, this.waves, this.radius);
  final BoxPainter base;
  final Color accent;
  final bool waves;
  final BorderRadiusGeometry? radius;
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    base.paint(canvas, offset, configuration);
    final size = configuration.size;
    if (size == null || size.isEmpty) return;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    final outline =
        (radius?.resolve(configuration.textDirection ?? TextDirection.ltr) ??
                BorderRadius.circular(16))
            .toRRect(Offset.zero & size);
    canvas.clipRRect(outline);
    final line = Path()
      ..moveTo(18, size.height - 1.5)
      ..lineTo(size.width * .72, size.height - 1.5);
    canvas.drawPath(
        line,
        Paint()
          ..color = accent.withValues(alpha: .75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    if (waves) {
      for (var i = 0; i < 22; i++) {
        final t = i / 21;
        final path = Path()
          ..moveTo(size.width * .24, size.height * (1.08 + t * .05))
          ..cubicTo(
              size.width * .64,
              size.height * (1.12 - t * .18),
              size.width * .70,
              size.height * (.68 + t * .24),
              size.width * 1.01,
              size.height * (.52 + t * .42));
        canvas.drawPath(
            path,
            Paint()
              ..shader = LinearGradient(colors: [
                accent.withValues(alpha: 0),
                accent.withValues(alpha: .20),
                accent.withValues(alpha: .55)
              ]).createShader(Offset.zero & size)
              ..style = PaintingStyle.stroke
              ..strokeWidth = .7);
        if (i == 0) {
          canvas.drawPath(
              path,
              Paint()
                ..color = accent.withValues(alpha: .65)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
        }
      }
      canvas.drawRRect(
          outline.deflate(1),
          Paint()
            ..color = accent.withValues(alpha: .35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    }
    canvas.restore();
  }

  @override
  void dispose() {
    base.dispose();
    super.dispose();
  }
}

class AmbientWaves extends CustomPainter {
  const AmbientWaves(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    for (var layer = 0; layer < 2; layer++) {
      final tint = layer == 0 ? color : const Color(0xFF9D38FF);
      for (var i = 0; i < 28; i++) {
        final path = Path();
        for (var x = 0.0; x <= size.width; x += 5) {
          final t = x / size.width;
          final y = size.height -
              32 -
              math.sin(t * math.pi * 3.2 + layer * 2 + i * .035) *
                  (24 + i * .7);
          if (x == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        canvas.drawPath(
            path,
            Paint()
              ..shader = LinearGradient(colors: [
                tint.withValues(alpha: .05),
                tint.withValues(alpha: .7),
                tint.withValues(alpha: .1)
              ]).createShader(Offset.zero & size)
              ..style = PaintingStyle.stroke
              ..strokeWidth = i == 14 ? 2 : .65
              ..maskFilter =
                  i == 14 ? const MaskFilter.blur(BlurStyle.normal, 2) : null);
        if (i == 14) {
          canvas.drawPath(
              path,
              Paint()
                ..shader = LinearGradient(colors: [
                  tint.withValues(alpha: .1),
                  tint,
                  tint.withValues(alpha: .25)
                ]).createShader(Offset.zero & size)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.2);
        }
      }
    }
  }

  @override
  bool shouldRepaint(AmbientWaves oldDelegate) => oldDelegate.color != color;
}
