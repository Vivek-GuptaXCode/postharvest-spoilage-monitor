import '../models/alert.dart';
import '../theme/risk_colors.dart';
import '../theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AlertTile extends StatelessWidget {
  final Alert alert;
  final ValueChanged<Alert>? onAcknowledge;

  const AlertTile({super.key, required this.alert, this.onAcknowledge});

  Color _severityColor() {
    switch (alert.severity) {
      case 'critical':
        return RiskColors.critical;
      case 'high':
      case 'warning':
        return RiskColors.warning;
      case 'medium':
        return RiskColors.caution;
      case 'low':
        return RiskColors.safe;
      default:
        return AppColors.textMuted;
    }
  }

  IconData _typeIcon() {
    switch (alert.type) {
      case 'temperature':
        return Icons.thermostat_rounded;
      case 'humidity':
        return Icons.water_drop_rounded;
      case 'co2':
        return Icons.cloud_rounded;
      case 'ethylene':
      case 'gas':
        return Icons.science_rounded;
      case 'high_risk':
        return Icons.warning_amber_rounded;
      case 'critical_risk':
        return Icons.error_rounded;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _severityColor();
    final timeStr = DateFormat('MMM d, HH:mm').format(alert.timestamp);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(50), width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top accent bar
          Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color, color.withAlpha(0)]),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withAlpha(50), width: 1),
                  ),
                  child: Icon(_typeIcon(), color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Severity badge + time
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: color.withAlpha(20),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              alert.severity.toUpperCase(),
                              style: GoogleFonts.dmMono(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: color,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                          if (alert.zoneId != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.neonBlue.withAlpha(20),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                alert.zoneId!.replaceAll('-', ' ').toUpperCase(),
                                style: GoogleFonts.dmMono(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.neonBlue,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            timeStr,
                            style: GoogleFonts.dmMono(
                              fontSize: 10,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Message
                      Text(
                        alert.message,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 13,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Footer: type + acknowledge
                      Row(
                        children: [
                          Text(
                            alert.type.replaceAll('_', ' ').toUpperCase(),
                            style: GoogleFonts.dmMono(
                              fontSize: 10,
                              color: AppColors.textMuted,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const Spacer(),
                          if (alert.acknowledged)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppColors.neonGreen,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Acknowledged',
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 11,
                                    color: AppColors.neonGreen,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            )
                          else if (onAcknowledge != null)
                            GestureDetector(
                              onTap: () => onAcknowledge!(alert),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withAlpha(15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: color.withAlpha(50),
                                  ),
                                ),
                                child: Text(
                                  'Acknowledge',
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: color,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
