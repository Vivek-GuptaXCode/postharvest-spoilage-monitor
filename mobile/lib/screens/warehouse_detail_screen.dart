import 'dart:io';
import '../widgets/risk_gauge.dart';
import '../widgets/sensor_card.dart';
import '../theme/risk_colors.dart';
import 'package:flutter/material.dart';
import '../providers/api_providers.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/ui_state_providers.dart';
import '../providers/warehouse_providers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WarehouseDetailScreen extends ConsumerWidget {
  final String warehouseId;
  const WarehouseDetailScreen({super.key, required this.warehouseId});

  /// Export sensor readings as CSV and share/save the file
  Future<void> _exportCsv(
    BuildContext context,
    WidgetRef ref,
    String warehouseId,
  ) async {
    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Exporting CSV…')));
      final apiService = ref.read(apiServiceProvider);
      final csv = await apiService.exportReadingsCsv(warehouseId, hours: 24);

      // Write to temp file and share
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/warehouse_${warehouseId}_export.csv');
      await file.writeAsString(csv);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Warehouse $warehouseId — Sensor Data Export',
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // WATCH — reactive, rebuilds on new data
    final latestData = ref.watch(latestReadingProvider(warehouseId));
    final timeRange = ref.watch(timeRangeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Warehouse Detail'),
        actions: [
          // Export CSV button
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export CSV',
            onPressed: () => _exportCsv(context, ref, warehouseId),
          ),
          // Time range selector
          PopupMenuButton<String>(
            initialValue: timeRange,
            onSelected: (value) {
              ref.read(timeRangeProvider.notifier).state = value;
            },
            itemBuilder:
                (_) => const [
                  PopupMenuItem(value: '1h', child: Text('Last 1 hour')),
                  PopupMenuItem(value: '6h', child: Text('Last 6 hours')),
                  PopupMenuItem(value: '24h', child: Text('Last 24 hours')),
                  PopupMenuItem(value: '7d', child: Text('Last 7 days')),
                  PopupMenuItem(value: '30d', child: Text('Last 30 days')),
                ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.schedule),
                  const SizedBox(width: 4),
                  Text(timeRange),
                ],
              ),
            ),
          ),
        ],
      ),
      body: latestData.when(
        data: (data) {
          // Read the warehouse document for metadata (commodityType)
          // that M1 doesn't write to latest/current
          final warehouseDoc = ref.watch(warehouseDocProvider(warehouseId));
          final commodityType = warehouseDoc.valueOrNull?.cropType ?? '';
          return _DetailBody(
            data: data,
            warehouseId: warehouseId,
            commodityType: commodityType,
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final Map<String, dynamic> data;
  final String warehouseId;
  final String commodityType;
  const _DetailBody({
    required this.data,
    required this.warehouseId,
    this.commodityType = '',
  });

  @override
  Widget build(BuildContext context) {
    final temp = (data['temperature'] ?? 0).toDouble();
    final humidity = (data['humidity'] ?? 0).toDouble();
    // M1 writes camelCase to Firestore; check camelCase first, snake_case fallback
    final co2 = (data['co2'] ?? data['co2Level'] ?? 0).toDouble();
    final gasLevel = (data['gasLevel'] ?? data['gas_level'] ?? data['ethyleneLevel'] ?? 0).toDouble();
    final riskScore = (data['riskScore'] ?? data['risk_score'] ?? 0).toDouble();
    final riskLabel = (data['riskLevel'] ?? data['risk_level'] ?? RiskColors.labelFromScore(riskScore)).toString();
    final daysToSpoilage = (data['daysToSpoilage'] ?? data['days_to_spoilage'] ?? -1).toDouble();
    final recommendation = data['recommendation'] as String? ?? '';
    // commodityType comes from the warehouse doc (passed as constructor param),
    // NOT from latest/current (M1 doesn't write it there)
    final displayCommodity = commodityType.isNotEmpty
        ? commodityType
        : (data['commodityType'] ?? data['commodity_type'] ?? '').toString();
    final estimatedLossInr = (data['estimatedLossInr'] ?? data['estimated_loss_inr'] ?? -1).toDouble();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Risk gauge
          Center(
            child: RiskGauge(riskScore: riskScore, label: '$riskLabel — Spoilage Risk'),
          ),
          const SizedBox(height: 16),

          // Shelf-life countdown card
          if (daysToSpoilage >= 0)
            Card(
              color: RiskColors.fromRiskScore(riskScore).withAlpha(25),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.timer_outlined, color: RiskColors.fromRiskScore(riskScore), size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Estimated Shelf Life',
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${daysToSpoilage.toStringAsFixed(1)} days remaining',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: RiskColors.fromRiskScore(riskScore),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (displayCommodity.isNotEmpty)
                      Chip(label: Text(displayCommodity)),
                  ],
                ),
              ),
            ),

          // Recommendation card
          if (recommendation.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.primaryContainer.withAlpha(40),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recommendation',
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(recommendation, style: Theme.of(context).textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Estimated loss card
          if (estimatedLossInr >= 0) ...[
            const SizedBox(height: 12),
            Card(
              color: Colors.red.withAlpha(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.currency_rupee, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    Text(
                      'Estimated Loss: ₹${estimatedLossInr.toStringAsFixed(0)}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Temperature & Humidity gauges side-by-side
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: TemperatureGauge(temperature: temp),
                ),
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: HumidityGauge(humidity: humidity),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Sensor cards grid
          Text(
            'Live Sensor Data',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: [
              SensorCard(
                label: 'Temperature',
                value: '${temp.toStringAsFixed(1)}°C',
                icon: Icons.thermostat,
                expanded: true,
              ),
              SensorCard(
                label: 'Humidity',
                value: '${humidity.toStringAsFixed(1)}%',
                icon: Icons.water_drop,
                expanded: true,
              ),
              SensorCard(
                label: 'CO₂',
                value: '${co2.toStringAsFixed(0)} ppm',
                icon: Icons.cloud,
                expanded: true,
              ),
              SensorCard(
                label: 'Gas / VOC',
                value: '${gasLevel.toStringAsFixed(1)} ppm',
                icon: Icons.science,
                expanded: true,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Recent alerts section
          Text('Recent Alerts', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _AlertsList(warehouseId: warehouseId),
        ],
      ),
    );
  }
}

class _AlertsList extends ConsumerWidget {
  final String warehouseId;
  const _AlertsList({required this.warehouseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(alertsProvider(warehouseId));

    return alertsAsync.when(
      data: (alerts) {
        if (alerts.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No alerts — all systems normal.'),
          );
        }
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: alerts.length.clamp(0, 5),
          itemBuilder: (context, i) {
            final alert = alerts[i];
            return ListTile(
              leading: Icon(
                Icons.warning_amber,
                color:
                    alert.severity == 'critical'
                        ? Colors.red
                        : alert.severity == 'warning' || alert.severity == 'high'
                        ? Colors.orange
                        : Colors.yellow[700],
              ),
              title: Text(alert.message),
              subtitle: Text(alert.type),
              dense: true,
            );
          },
        );
      },
      loading:
          () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (err, _) => Text('Error loading alerts: $err'),
    );
  }
}
