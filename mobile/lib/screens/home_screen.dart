import 'alerts_screen.dart';
import 'charts_screen.dart';
import 'camera_feed_screen.dart';
import '../widgets/sensor_card.dart';
import '../theme/risk_colors.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_providers.dart';
import '../providers/ui_state_providers.dart';
import '../providers/warehouse_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navIndex = ref.watch(bottomNavIndexProvider);

    final screens = [
      _DashboardTab(),
      const ChartsScreen(),
      const AlertsScreen(),
      const CameraFeedScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('PostHarvest Monitor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () {
              ref.read(authNotifierProvider.notifier).signOut();
            },
          ),
        ],
      ),
      body: screens[navIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: navIndex,
        onDestinationSelected: (i) {
          ref.read(bottomNavIndexProvider.notifier).state = i;
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart_outlined),
            selectedIcon: Icon(Icons.show_chart),
            label: 'Charts',
          ),
          NavigationDestination(
            icon: Icon(Icons.warning_amber_outlined),
            selectedIcon: Icon(Icons.warning_amber),
            label: 'Alerts',
          ),
          NavigationDestination(
            icon: Icon(Icons.videocam_outlined),
            selectedIcon: Icon(Icons.videocam),
            label: 'Camera',
          ),
        ],
      ),
    );
  }
}

class _DashboardTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warehousesAsync = ref.watch(warehousesProvider);

    return warehousesAsync.when(
      data: (warehouses) {
        if (warehouses.isEmpty) {
          return const Center(
            child: Text('No warehouses found. Add one to get started.'),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: warehouses.length,
          itemBuilder: (context, index) {
            final wh = warehouses[index];
            return Card(
              clipBehavior: Clip.antiAlias,
              margin: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: () {
                  // Set the selected warehouse so Charts/Alerts/Camera tabs work
                  ref.read(selectedWarehouseIdProvider.notifier).state = wh.id;
                  onWarehouseSelected(wh.id);
                  context.push('/warehouse/${wh.id}');
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.warehouse,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              wh.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Chip(label: Text(wh.cropType)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        wh.location,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      // Show latest sensor readings
                      _WarehouseSensorRow(warehouseId: wh.id),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }
}

class _WarehouseSensorRow extends ConsumerWidget {
  final String warehouseId;
  const _WarehouseSensorRow({required this.warehouseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = ref.watch(latestReadingProvider(warehouseId));

    return latest.when(
      data: (data) {
        if (data.isEmpty) return const Text('No sensor data yet');

        final riskScore = (data['riskScore'] ?? data['risk_score'] ?? 0).toDouble();
        final riskColor = RiskColors.fromRiskScore(riskScore);
        final riskLabel = RiskColors.labelFromScore(riskScore);

        // Last updated time
        final timestamp = data['timestamp'];
        String lastUpdated = '';
        if (timestamp != null) {
          try {
            final dt = timestamp is DateTime
                ? timestamp
                : (timestamp as dynamic).toDate();
            lastUpdated = DateFormat('HH:mm, MMM d').format(dt);
          } catch (_) {}
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Risk badge + last updated
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: riskColor.withAlpha(40),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: riskColor, width: 1),
                  ),
                  child: Text(
                    '$riskLabel (${riskScore.toStringAsFixed(0)})',
                    style: TextStyle(
                      color: riskColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                if (lastUpdated.isNotEmpty)
                  Text(
                    lastUpdated,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Sensor values
            Row(
              children: [
                SensorCard(
                  label: 'Temp',
                  value: '${data['temperature'] ?? '--'}°C',
                  icon: Icons.thermostat,
                ),
                const SizedBox(width: 8),
                SensorCard(
                  label: 'Humidity',
                  value: '${data['humidity'] ?? '--'}%',
                  icon: Icons.water_drop,
                ),
                const SizedBox(width: 8),
                SensorCard(
                  label: 'CO₂',
                  value: '${data['co2'] ?? data['co2Level'] ?? '--'} ppm',
                  icon: Icons.cloud,
                ),
              ],
            ),
          ],
        );
      },
      loading:
          () => const SizedBox(
            height: 40,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
      error:
          (err, _) => Text(
            'Sensor error: $err',
            style: const TextStyle(fontSize: 12, color: Colors.red),
          ),
    );
  }
}
