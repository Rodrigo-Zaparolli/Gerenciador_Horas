import 'package:flutter/material.dart';

class BetaHologram extends StatelessWidget {
  const BetaHologram({super.key, required this.speaking});
  final bool speaking;
  @override
  Widget build(BuildContext context) => Semantics(
      label: 'Holograma da BETA',
      child: TweenAnimationBuilder<double>(
          tween: Tween(end: speaking ? 1 : .88),
          duration: const Duration(milliseconds: 600),
          builder: (_, intensity, child) =>
              Opacity(opacity: intensity, child: child),
          child: Image.asset('assets/images/beta_hologram.png',
              width: 144,
              height: 168,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium)));
}
