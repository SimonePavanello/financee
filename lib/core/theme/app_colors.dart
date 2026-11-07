import 'package:flutter/material.dart';

/// Palette dell'app: indaco/viola come colore di brand, menta per le
/// entrate e corallo per le uscite.
abstract final class AppColors {
  static const indigo = Color(0xFF4F46E5);
  static const violet = Color(0xFF7C3AED);
  static const purple = Color(0xFFA855F7);

  static const income = Color(0xFF12B886);
  static const expense = Color(0xFFFF6B6B);
  static const transfer = Color(0xFF6C7BFF);
  static const warning = Color(0xFFF59E0B);

  static const heroGradient = LinearGradient(
    colors: [Color(0xFF4338CA), Color(0xFF6D28D9), Color(0xFF9333EA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const buttonGradient = LinearGradient(
    colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const lightBackground = Color(0xFFF4F5FB);
  static const darkBackground = Color(0xFF0E0F1A);
  static const darkSurface = Color(0xFF171929);

  static Color forIncome(bool isIncome) => isIncome ? income : expense;
}
