import 'package:flutter/material.dart';

class RiskColors {
  static const Color safe = Color(0xFF00E5A0);      // Neon Green
  static const Color caution = Color(0xFFFFB703);   // Amber
  static const Color warning = Color(0xFFFF8C42);   // Orange
  static const Color critical = Color(0xFFFF4757);  // Neon Red

  static Color fromRiskScore(double score) {
    if (score < 25) return safe;
    if (score < 50) return caution;
    if (score < 75) return warning;
    return critical;
  }

  static String labelFromScore(double score) {
    if (score < 25) return 'Low';
    if (score < 50) return 'Medium';
    if (score < 75) return 'High';
    return 'Critical';
  }

  static LinearGradient gradientFromScore(double score) {
    if (score < 25) {
      return const LinearGradient(colors: [Color(0xFF00E5A0), Color(0xFF00B4D8)]);
    }
    if (score < 50) {
      return const LinearGradient(colors: [Color(0xFFFFB703), Color(0xFFFB8500)]);
    }
    if (score < 75) {
      return const LinearGradient(colors: [Color(0xFFFF8C42), Color(0xFFFF6B2B)]);
    }
    return const LinearGradient(colors: [Color(0xFFFF4757), Color(0xFFFF6B9D)]);
  }
}
