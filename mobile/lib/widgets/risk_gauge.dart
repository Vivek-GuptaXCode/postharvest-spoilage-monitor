import '../theme/risk_colors.dart';
import 'package:flutter/material.dart';
import 'package:gauge_indicator/gauge_indicator.dart';

/// Risk Score Gauge (0–100, semi-circle with needle pointer)
class RiskGauge extends StatelessWidget {
  final double riskScore; // 0.0 – 100.0
  final String label;

  const RiskGauge({super.key, required this.riskScore, this.label = 'Risk'});

  Color _riskColor() => RiskColors.fromRiskScore(riskScore);

  String _riskLabel() => RiskColors.labelFromScore(riskScore);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 260,
          height: 150,
          child: AnimatedRadialGauge(
            duration: const Duration(seconds: 1),
            curve: Curves.elasticOut,
            radius: 120,
            value: riskScore,
            axis: GaugeAxis(
              min: 0,
              max: 100,
              degrees: 180,
              style: GaugeAxisStyle(
                thickness: 20,
                background:
                    isDark ? const Color(0xFF1E1E2E) : const Color(0xFFE0E0E0),
                segmentSpacing: 4,
              ),
              pointer: GaugePointer.needle(
                width: 16,
                height: 100,
                borderRadius: 16,
                color: isDark ? Colors.white : Colors.black87,
              ),
              progressBar: const GaugeProgressBar.basic(
                color: Colors.transparent,
              ),
              segments: const [
                GaugeSegment(from: 0, to: 25, color: Colors.green),
                GaugeSegment(from: 25, to: 50, color: Colors.yellow),
                GaugeSegment(from: 50, to: 75, color: Colors.orange),
                GaugeSegment(from: 75, to: 100, color: Colors.red),
              ],
            ),
            builder:
                (context, child, value) => RadialGaugeLabel(
                  value: value,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ),
                ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${_riskLabel()} $label',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: _riskColor(),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Temperature Gauge (0–50°C, 240° arc)
class TemperatureGauge extends StatelessWidget {
  final double temperature;

  const TemperatureGauge({super.key, required this.temperature});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      height: 180,
      child: AnimatedRadialGauge(
        duration: const Duration(milliseconds: 500),
        radius: 80,
        value: temperature.clamp(0, 50),
        axis: GaugeAxis(
          min: 0,
          max: 50,
          degrees: 240,
          style: const GaugeAxisStyle(thickness: 15),
          segments: const [
            GaugeSegment(from: 0, to: 15, color: Colors.blue),
            GaugeSegment(from: 15, to: 25, color: Colors.green),
            GaugeSegment(from: 25, to: 35, color: Colors.orange),
            GaugeSegment(from: 35, to: 50, color: Colors.red),
          ],
        ),
        builder:
            (context, child, value) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${value.toStringAsFixed(1)}°C',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text('Temp', style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
      ),
    );
  }
}

/// Humidity Gauge (0–100%, 240° arc)
class HumidityGauge extends StatelessWidget {
  final double humidity;

  const HumidityGauge({super.key, required this.humidity});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      height: 180,
      child: AnimatedRadialGauge(
        duration: const Duration(milliseconds: 500),
        radius: 80,
        value: humidity.clamp(0, 100),
        axis: GaugeAxis(
          min: 0,
          max: 100,
          degrees: 240,
          style: const GaugeAxisStyle(thickness: 15),
          segments: const [
            GaugeSegment(from: 0, to: 30, color: Colors.orange),
            GaugeSegment(from: 30, to: 60, color: Colors.green),
            GaugeSegment(from: 60, to: 80, color: Colors.green),
            GaugeSegment(from: 80, to: 100, color: Colors.blue),
          ],
        ),
        builder:
            (context, child, value) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${value.toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text('Humidity', style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
      ),
    );
  }
}
