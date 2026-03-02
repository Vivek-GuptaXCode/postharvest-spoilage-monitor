import 'package:flutter/material.dart';

class RiskColors {
  static const Color safe = Color(0xFF4CAF50); // Green
  static const Color caution = Color(0xFFFFC107); // Yellow/Amber
  static const Color warning = Color(0xFFFF9800); // Orange
  static const Color critical = Color(0xFFE53935); // Red

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
}
