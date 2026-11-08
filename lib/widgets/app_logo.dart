import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Il logo di Financee (monogramma F con la moneta), lo stesso disegno
/// dell'icona dell'app (vedi `tool/generate_app_icon.dart`).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Financee',
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: _LogoPainter()),
    ),
  );
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter();

  /// Il disegno è su una griglia di 120 × 120 unità.
  static const _grid = 120.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _grid;
    canvas.scale(scale);
    const square = Rect.fromLTWH(0, 0, _grid, _grid);
    canvas.drawRRect(
      RRect.fromRectAndRadius(square, const Radius.circular(28)),
      Paint()..shader = AppColors.heroGradient.createShader(square),
    );
    final white = Paint()..color = Colors.white;
    final mint = Paint()..color = AppColors.income;
    RRect bar(double l, double t, double r, double b) =>
        RRect.fromLTRBR(l, t, r, b, const Radius.circular(7.5));
    canvas
      ..drawRRect(bar(36, 26, 51, 94), white)
      ..drawRRect(bar(36, 26, 86, 41), white)
      ..drawRRect(bar(36, 53, 72, 68), mint)
      ..drawCircle(const Offset(84, 83), 9, mint);
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) => false;
}
