import 'alerts_screen.dart';
import 'charts_screen.dart';
import 'camera_feed_screen.dart';
import '../theme/risk_colors.dart';
import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_providers.dart';
import '../providers/ui_state_providers.dart';
import '../providers/warehouse_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
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
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: _GlassAppBar(ref: ref),
      ),
      body: screens[navIndex],
      bottomNavigationBar: _GlassNavBar(
        selectedIndex: navIndex,
        onDestinationSelected: (i) {
          ref.read(bottomNavIndexProvider.notifier).state = i;
        },
      ),
    );
  }
}

class _GlassAppBar extends StatelessWidget {
  final WidgetRef ref;
  const _GlassAppBar({required this.ref});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface.withAlpha(200),
        border: const Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [AppColors.neonGreen, AppColors.neonBlue],
                ).createShader(bounds),
                child: const Icon(
                  Icons.warehouse_rounded,
                  size: 28,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Colors.white, AppColors.textSecondary],
                ).createShader(bounds),
                child: Text(
                  'PostHarvest',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: IconButton(
                  icon: const Icon(
                    Icons.logout_rounded,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                  onPressed: () =>
                      ref.read(authNotifierProvider.notifier).signOut(),
                  tooltip: 'Sign Out',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const _GlassNavBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.grid_view_rounded, Icons.grid_view_rounded, 'Dashboard'),
      (Icons.show_chart_rounded, Icons.show_chart_rounded, 'Charts'),
      (Icons.notifications_outlined, Icons.notifications_rounded, 'Alerts'),
      (Icons.videocam_outlined, Icons.videocam_rounded, 'Camera'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(
          top: BorderSide(color: AppColors.border, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(100),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (i) {
              final isSelected = selectedIndex == i;
              final item = items[i];
              return GestureDetector(
                onTap: () => onDestinationSelected(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.neonGreen.withAlpha(20)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected
                        ? Border.all(
                            color: AppColors.neonGreen.withAlpha(60),
                            width: 1,
                          )
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSelected ? item.$2 : item.$1,
                        color: isSelected
                            ? AppColors.neonGreen
                            : AppColors.textMuted,
                        size: 22,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.$3,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 10,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: isSelected
                              ? AppColors.neonGreen
                              : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
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
          return _EmptyState();
        }
        return CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Warehouses',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -1,
                      ),
                    ),
                    Text(
                      '${warehouses.length} locations monitored',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Stats row
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: _StatsRow(warehouseCount: warehouses.length),
              ),
            ),
            // Warehouse cards
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final wh = warehouses[index];
                  return _WarehouseCard(
                    warehouse: wh,
                    index: index,
                    onTap: () {
                      ref.read(selectedWarehouseIdProvider.notifier).state =
                          wh.id;
                      onWarehouseSelected(wh.id);
                      context.push('/warehouse/${wh.id}');
                    },
                  );
                }, childCount: warehouses.length),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.neonGreen),
      ),
      error: (err, stack) => Center(
        child: Text(
          'Error: $err',
          style: const TextStyle(color: AppColors.neonRed),
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final int warehouseCount;
  const _StatsRow({required this.warehouseCount});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatChip(
            label: 'Active',
            value: '$warehouseCount',
            color: AppColors.neonGreen,
            icon: Icons.sensors,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatChip(
            label: 'Live Feed',
            value: 'ON',
            color: AppColors.neonBlue,
            icon: Icons.wifi_tethering_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatChip(
            label: 'Realtime',
            value: '24/7',
            color: AppColors.neonAmber,
            icon: Icons.bolt_rounded,
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(50), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: GoogleFonts.dmMono(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    color: AppColors.textMuted,
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

class _WarehouseCard extends StatelessWidget {
  final dynamic warehouse;
  final int index;
  final VoidCallback onTap;

  const _WarehouseCard({
    required this.warehouse,
    required this.index,
    required this.onTap,
  });

  static const _gradients = [
    [Color(0xFF00E5A0), Color(0xFF00B4D8)],
    [Color(0xFFBD5FFF), Color(0xFF7B2FBE)],
    [Color(0xFFFFB703), Color(0xFFFB8500)],
    [Color(0xFFFF4757), Color(0xFFFF6B9D)],
  ];

  @override
  Widget build(BuildContext context) {
    final colors = _gradients[index % _gradients.length];

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: AppColors.surface,
              border: Border.all(color: AppColors.border, width: 1),
              boxShadow: [
                BoxShadow(
                  color: colors[0].withAlpha(20),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                // Header with gradient accent
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colors[0].withAlpha(25),
                        colors[1].withAlpha(10),
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: colors[0].withAlpha(40),
                        width: 1,
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: colors),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: colors[0].withAlpha(80),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.warehouse_rounded,
                          color: Colors.black,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              warehouse.name,
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on_outlined,
                                  size: 12,
                                  color: AppColors.textMuted,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    warehouse.location,
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 11,
                                      color: AppColors.textMuted,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: colors[0].withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: colors[0].withAlpha(60),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          warehouse.cropType,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colors[0],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Sensor row
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: _WarehouseSensorRow(warehouseId: warehouse.id),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.neonGreen.withAlpha(15),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.neonGreen.withAlpha(50)),
            ),
            child: const Icon(
              Icons.warehouse_outlined,
              size: 40,
              color: AppColors.neonGreen,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No Warehouses',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add a warehouse to start monitoring',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
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
        if (data.isEmpty) {
          return Text(
            'No sensor data yet',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 12,
              color: AppColors.textMuted,
            ),
          );
        }

        final riskScore = (data['riskScore'] ?? data['risk_score'] ?? 0)
            .toDouble();
        final riskColor = RiskColors.fromRiskScore(riskScore);
        final riskLabel = RiskColors.labelFromScore(riskScore);

        final timestamp = data['timestamp'];
        String lastUpdated = '';
        if (timestamp != null) {
          try {
            final dt = timestamp is DateTime
                ? timestamp
                : (timestamp as dynamic).toDate();
            lastUpdated = DateFormat('HH:mm').format(dt);
          } catch (_) {}
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Risk badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: riskColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: riskColor.withAlpha(60),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: riskColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: riskColor, blurRadius: 4),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$riskLabel · ${riskScore.toStringAsFixed(0)}',
                        style: GoogleFonts.dmMono(
                          color: riskColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (lastUpdated.isNotEmpty)
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time_rounded,
                        size: 11,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        lastUpdated,
                        style: GoogleFonts.dmMono(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MiniSensor(
                    label: 'TEMP',
                    value: '${data['temperature'] ?? '--'}°',
                    color: const Color(0xFFFF6B6B),
                    icon: Icons.thermostat_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniSensor(
                    label: 'HUM',
                    value: '${data['humidity'] ?? '--'}%',
                    color: const Color(0xFF4FACFE),
                    icon: Icons.water_drop_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniSensor(
                    label: 'CO₂',
                    value: '${data['co2'] ?? data['co2Level'] ?? '--'}',
                    color: const Color(0xFF43E97B),
                    icon: Icons.cloud_outlined,
                  ),
                ),
              ],
            ),
          ],
        );
      },
      loading: () => const SizedBox(
        height: 50,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.neonGreen,
            ),
          ),
        ),
      ),
      error: (err, _) => Text(
        'Sensor error',
        style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppColors.neonRed),
      ),
    );
  }
}

class _MiniSensor extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;

  const _MiniSensor({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(40), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.dmMono(
                    fontSize: 9,
                    color: AppColors.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.dmMono(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
