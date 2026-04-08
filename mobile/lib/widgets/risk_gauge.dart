import '../theme/risk_colors.dart';
import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gauge_indicator/gauge_indicator.dart';

/// Risk Score Gauge
class RiskGauge extends StatelessWidget {
  final double riskScore;
  final String label;

  const RiskGauge({super.key, required this.riskScore, this.label = 'Risk'});

  Color _riskColor() => RiskColors.fromRiskScore(riskScore);
  String _riskLabel() => RiskColors.labelFromScore(riskScore);

  @override
  Widget build(BuildContext context) {
    final color = _riskColor();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'SPOILAGE RISK',
          style: GoogleFonts.dmMono(
            fontSize: 10,
            color: AppColors.textMuted,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 260,
          height: 155,
          child: AnimatedRadialGauge(
            duration: const Duration(milliseconds: 1200),
            curve: Curves.elasticOut,
            radius: 120,
            value: riskScore,
            axis: GaugeAxis(
              min: 0,
              max: 100,
              degrees: 180,
              style: const GaugeAxisStyle(
                thickness: 18,
                background: Color(0xFF161B22),
                segmentSpacing: 3,
              ),
              pointer: GaugePointer.needle(
                width: 14,
                height: 90,
                borderRadius: 14,
                color: color,
              ),
              progressBar: const GaugeProgressBar.basic(color: Colors.transparent),
              segments: const [
                GaugeSegment(from: 0, to: 25, color: Color(0xFF00E5A0)),
                GaugeSegment(from: 25, to: 50, color: Color(0xFFFFB703)),
                GaugeSegment(from: 50, to: 75, color: Color(0xFFFF8C42)),
                GaugeSegment(from: 75, to: 100, color: Color(0xFFFF4757)),
              ],
            ),
            builder: (context, child, value) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value.toStringAsFixed(0),
                  style: GoogleFonts.dmMono(
                    color: color,
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                Text(
                  '%',
                  style: GoogleFonts.dmMono(
                    fontSize: 14,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withAlpha(60)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: color, blurRadius: 6)],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_riskLabel()} Risk',
                style: GoogleFonts.spaceGrotesk(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Temperature Gauge
class TemperatureGauge extends StatelessWidget {
  final double temperature;

  const TemperatureGauge({super.key, required this.temperature});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      height: 170,
      child: AnimatedRadialGauge(
        duration: const Duration(milliseconds: 700),
        radius: 78,
        value: temperature.clamp(0, 50),
        axis: GaugeAxis(
          min: 0,
          max: 50,
          degrees: 240,
          style: const GaugeAxisStyle(
            thickness: 14,
            background: Color(0xFF161B22),
          ),
          segments: const [
            GaugeSegment(from: 0, to: 15, color: Color(0xFF4FACFE)),
            GaugeSegment(from: 15, to: 25, color: Color(0xFF00E5A0)),
            GaugeSegment(from: 25, to: 35, color: Color(0xFFFF8C42)),
            GaugeSegment(from: 35, to: 50, color: Color(0xFFFF4757)),
          ],
        ),
        builder: (context, child, value) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${value.toStringAsFixed(1)}°',
              style: GoogleFonts.dmMono(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.thermostat_rounded, size: 12, color: Color(0xFFFF6B6B)),
                const SizedBox(width: 3),
                Text(
                  'TEMP',
                  style: GoogleFonts.dmMono(fontSize: 10, color: AppColors.textMuted, letterSpacing: 0.5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Humidity Gauge
class HumidityGauge extends StatelessWidget {
  final double humidity;

  const HumidityGauge({super.key, required this.humidity});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      height: 170,
      child: AnimatedRadialGauge(
        duration: const Duration(milliseconds: 700),
        radius: 78,
        value: humidity.clamp(0, 100),
        axis: GaugeAxis(
          min: 0,
          max: 100,
          degrees: 240,
          style: const GaugeAxisStyle(
            thickness: 14,
            background: Color(0xFF161B22),
          ),
          segments: const [
            GaugeSegment(from: 0, to: 30, color: Color(0xFFFFB703)),
            GaugeSegment(from: 30, to: 60, color: Color(0xFF00E5A0)),
            GaugeSegment(from: 60, to: 80, color: Color(0xFF4FACFE)),
            GaugeSegment(from: 80, to: 100, color: Color(0xFFBD5FFF)),
          ],
        ),
        builder: (context, child, value) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${value.toStringAsFixed(1)}%',
              style: GoogleFonts.dmMono(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.water_drop_rounded, size: 12, color: Color(0xFF4FACFE)),
                const SizedBox(width: 3),
                Text(
                  'HUM',
                  style: GoogleFonts.dmMono(fontSize: 10, color: AppColors.textMuted, letterSpacing: 0.5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
