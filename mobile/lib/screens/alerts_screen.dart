import '../widgets/alert_tile.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../providers/api_providers.dart';
import '../providers/ui_state_providers.dart';
import '../providers/warehouse_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedWarehouse = ref.watch(selectedWarehouseIdProvider);
    final filter = ref.watch(alertFilterProvider);

    if (selectedWarehouse == null) {
      return Container(
        color: AppColors.background,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.neonAmber.withAlpha(15),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.neonAmber.withAlpha(50)),
                ),
                child: const Icon(
                  Icons.notifications_rounded,
                  size: 36,
                  color: AppColors.neonAmber,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'No Warehouse Selected',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Select a warehouse from the Dashboard',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final alertsAsync = ref.watch(alertsProvider(selectedWarehouse));

    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          // Filter bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: const Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [AppColors.neonAmber, Color(0xFFFB8500)],
                      ).createShader(bounds),
                      child: const Icon(
                        Icons.notifications_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Alerts',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () =>
                          ref.read(alertFilterProvider.notifier).reset(),
                      icon: const Icon(
                        Icons.refresh_rounded,
                        size: 14,
                        color: AppColors.textMuted,
                      ),
                      label: Text(
                        'Reset',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // Severity filter
                      ...['all', 'critical', 'warning'].map((sev) {
                        final selected = filter.severity == sev;
                        final colors = {
                          'all': AppColors.neonGreen,
                          'critical': AppColors.neonRed,
                          'warning': AppColors.neonAmber,
                        };
                        final color = colors[sev]!;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => ref
                                .read(alertFilterProvider.notifier)
                                .setSeverity(sev),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? color.withAlpha(25)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selected
                                      ? color.withAlpha(80)
                                      : AppColors.border,
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                sev == 'all' ? 'All' : sev.capitalize(),
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: selected ? color : AppColors.textMuted,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                      // Acknowledged toggle
                      GestureDetector(
                        onTap: () => ref
                            .read(alertFilterProvider.notifier)
                            .toggleAcknowledged(),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: filter.acknowledged
                                ? AppColors.neonBlue.withAlpha(25)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: filter.acknowledged
                                  ? AppColors.neonBlue.withAlpha(80)
                                  : AppColors.border,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                filter.acknowledged
                                    ? Icons.check_circle_rounded
                                    : Icons.check_circle_outline_rounded,
                                size: 14,
                                color: filter.acknowledged
                                    ? AppColors.neonBlue
                                    : AppColors.textMuted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Acknowledged',
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: filter.acknowledged
                                      ? AppColors.neonBlue
                                      : AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: alertsAsync.when(
              data: (alerts) {
                var filtered = alerts;
                if (filter.severity != 'all') {
                  filtered = filtered
                      .where((a) => a.severity == filter.severity)
                      .toList();
                }
                if (!filter.acknowledged) {
                  filtered = filtered.where((a) => !a.acknowledged).toList();
                }

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppColors.neonGreen.withAlpha(15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.neonGreen,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No alerts match the filter',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 16,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
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
                              SnackBar(
                                content: Text(
                                  'Alert acknowledged',
                                  style: GoogleFonts.spaceGrotesk(),
                                ),
                                backgroundColor: AppColors.neonGreen,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed: $e'),
                                backgroundColor: AppColors.neonRed,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                          }
                        }
                      },
                    );
                  },
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.neonGreen),
              ),
              error: (err, _) => Center(
                child: Text(
                  'Error: $err',
                  style: const TextStyle(color: AppColors.neonRed),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
