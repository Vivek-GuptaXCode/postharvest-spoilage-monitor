import '../models/alert.dart';
import '../theme/risk_colors.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

class AlertTile extends StatelessWidget {
  final Alert alert;
  /// Called when the user swipes to acknowledge the alert.
  final ValueChanged<Alert>? onAcknowledge;

  const AlertTile({super.key, required this.alert, this.onAcknowledge});

  Color _severityColor() {
    switch (alert.severity) {
      case 'critical':
        return RiskColors.critical;
      case 'high':
      case 'warning':  // M1 generates 'warning' for high-risk alerts
        return RiskColors.warning;
      case 'medium':
        return RiskColors.caution;
      case 'low':
        return RiskColors.safe;
      default:
        return Colors.grey;
    }
  }

  IconData _typeIcon() {
    switch (alert.type) {
      case 'temperature':
        return Icons.thermostat;
      case 'humidity':
        return Icons.water_drop;
      case 'co2':
        return Icons.cloud;
      case 'ethylene':
      case 'gas':
        return Icons.science;
      // M1 writes type as "{risk_level}_risk" e.g. "high_risk", "critical_risk"
      case 'high_risk':
        return Icons.warning_amber;
      case 'critical_risk':
        return Icons.error;
      default:
        return Icons.warning_amber;
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('MMM d, HH:mm').format(alert.timestamp);

    final tile = Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: severity icon + acknowledge button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: _severityColor().withAlpha(30),
                      child: Icon(_typeIcon(), color: _severityColor(), size: 16),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      alert.severity.toUpperCase(),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: _severityColor(),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (alert.acknowledged)
                  const Icon(Icons.check_circle, color: Colors.green, size: 20)
                else if (onAcknowledge != null)
                  IconButton(
                    icon: Icon(Icons.circle_outlined, color: _severityColor(), size: 20),
                    onPressed: () => onAcknowledge!(alert),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Acknowledge',
                  )
                else
                  Icon(Icons.circle_outlined, color: _severityColor(), size: 20),
              ],
            ),
            // const SizedBox(height: 8),
            // Message body
            Text(alert.message, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            // Subtitle
            Text(
              '${alert.type.split('_')[0].toUpperCase()} RISK • $timeStr',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );

    return tile;
  }
}
