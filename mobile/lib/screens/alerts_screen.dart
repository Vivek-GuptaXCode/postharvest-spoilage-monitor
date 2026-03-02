import '../widgets/alert_tile.dart';
import 'package:flutter/material.dart';
import '../providers/api_providers.dart';
import '../providers/ui_state_providers.dart';
import '../providers/warehouse_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedWarehouse = ref.watch(selectedWarehouseIdProvider);
    final filter = ref.watch(alertFilterProvider);

    if (selectedWarehouse == null) {
      return const Center(
        child: Text('Select a warehouse from the Dashboard to view alerts.'),
      );
    }

    final alertsAsync = ref.watch(alertsProvider(selectedWarehouse));

    return Column(
      children: [
        // Filter bar
        Padding(
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Severity filter
                DropdownButton<String>(
                  value: filter.severity,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Severities')),
                    DropdownMenuItem(value: 'critical', child: Text('Critical')),
                    DropdownMenuItem(value: 'warning', child: Text('Warning')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      // READ — one-time, doesn't cause rebuild
                      ref.read(alertFilterProvider.notifier).setSeverity(value);
                    }
                  },
                ),
                const SizedBox(width: 12),
                FilterChip(
                  label: const Text('Acknowledged'),
                  selected: filter.acknowledged,
                  onSelected: (_) {
                    ref.read(alertFilterProvider.notifier).toggleAcknowledged();
                  },
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: () {
                    ref.read(alertFilterProvider.notifier).reset();
                  },
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('Reset'),
                ),
              ],
            ),
          ),
        ),

        // Alerts list
        Expanded(
          child: alertsAsync.when(
            data: (alerts) {
              // Apply filters on typed Alert objects
              var filtered = alerts;
              if (filter.severity != 'all') {
                filtered =
                    filtered.where((a) => a.severity == filter.severity).toList();
              }
              // When "Acknowledged" chip is OFF (default), hide acknowledged alerts
              if (!filter.acknowledged) {
                filtered = filtered.where((a) => !a.acknowledged).toList();
              }

              if (filtered.isEmpty) {
                return const Center(child: Text('No alerts match the filter.'));
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final alert = filtered[index];
                  return AlertTile(
                    alert: alert,
                    onAcknowledge: (a) async {
                      try {
                        final api = ref.read(apiServiceProvider);
                        await api.acknowledgeAlert(selectedWarehouse, a.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Alert acknowledged')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to acknowledge: $e')),
                          );
                        }
                      }
                    },
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Error: $err')),
          ),
        ),
      ],
    );
  }
}
