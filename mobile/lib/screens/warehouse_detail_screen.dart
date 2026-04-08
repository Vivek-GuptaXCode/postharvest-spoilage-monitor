import 'dart:io';
import '../widgets/risk_gauge.dart';
import '../widgets/sensor_card.dart';
import '../theme/risk_colors.dart';
import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../providers/api_providers.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/ui_state_providers.dart';
import '../providers/warehouse_providers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

/// Horizontal chip bar for zone selection.
/// "All" chip → null selectedZoneId (aggregate warehouse data).
/// Each zone chip → that zone's ID.
class _ZoneSelector extends ConsumerWidget {
  final String warehouseId;
  const _ZoneSelector({required this.warehouseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zonesAsync = ref.watch(zonesProvider(warehouseId));
    final selectedZoneId = ref.watch(selectedZoneIdProvider);

    return zonesAsync.when(
      data: (zones) {
        if (zones.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: zones.length + 1, // +1 for "All"
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final isAll = index == 0;
              final zoneId = isAll ? null : zones[index - 1].id;
              final label = isAll ? 'All' : zones[index - 1].label;
              final isSelected = selectedZoneId == zoneId;

              return ChoiceChip(
                label: Text(
                  label,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? AppColors.background : Colors.white,
                  ),
                ),
                selected: isSelected,
                selectedColor: AppColors.neonGreen,
                backgroundColor: AppColors.surfaceElevated,
                side: BorderSide(
                  color: isSelected
                      ? AppColors.neonGreen
                      : AppColors.border,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                onSelected: (_) {
                  ref.read(selectedZoneIdProvider.notifier).state = zoneId;
                },
              );
            },
          ),
        );
      },
      loading: () => const SizedBox(height: 42),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class WarehouseDetailScreen extends ConsumerWidget {
  final String warehouseId;
  const WarehouseDetailScreen({super.key, required this.warehouseId});

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: AppColors.neonRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedZoneId = ref.watch(selectedZoneIdProvider);
    final timeRange = ref.watch(timeRangeProvider);

    // Choose data source: zone-specific or warehouse-level aggregate
    final latestData = selectedZoneId != null
        ? ref.watch(zoneLatestProvider(
            (warehouseId: warehouseId, zoneId: selectedZoneId)))
        : ref.watch(latestReadingProvider(warehouseId));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // Gradient app bar
          SliverAppBar(
            expandedHeight: 140,
            pinned: true,
            backgroundColor: AppColors.surface,
            surfaceTintColor: Colors.transparent,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: const BackButton(color: Colors.white),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.download_rounded,
                      size: 18,
                      color: AppColors.neonGreen,
                    ),
                    tooltip: 'Export CSV',
                    onPressed: () => _exportCsv(context, ref, warehouseId),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: PopupMenuButton<String>(
                    initialValue: timeRange,
                    color: AppColors.surfaceElevated,
                    onSelected: (value) {
                      ref.read(timeRangeProvider.notifier).state = value;
                    },
                    itemBuilder: (_) => ['1h', '6h', '24h', '7d', '30d']
                        .map(
                          (r) => PopupMenuItem(
                            value: r,
                            child: Text(
                              'Last $r',
                              style: GoogleFonts.spaceGrotesk(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.schedule_rounded,
                            size: 16,
                            color: AppColors.neonBlue,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            timeRange,
                            style: GoogleFonts.dmMono(
                              fontSize: 13,
                              color: AppColors.neonBlue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF00E5A0).withAlpha(30),
                      AppColors.surface,
                    ],
                  ),
                ),
                child: const Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: _WaveDecoration(),
                  ),
                ),
              ),
              title: Text(
                'Warehouse Detail',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          // Zone selector chips
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: _ZoneSelector(warehouseId: warehouseId),
            ),
          ),
          // Body
          SliverToBoxAdapter(
            child: latestData.when(
              data: (data) {
                final warehouseDoc = ref.watch(
                  warehouseDocProvider(warehouseId),
                );
                final commodityType = warehouseDoc.valueOrNull?.cropType ?? '';
                return _DetailBody(
                  data: data,
                  warehouseId: warehouseId,
                  commodityType: commodityType,
                );
              },
              loading: () => const SizedBox(
                height: 400,
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.neonGreen),
                ),
              ),
              error: (err, stack) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Error: $err',
                    style: const TextStyle(color: AppColors.neonRed),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaveDecoration extends StatelessWidget {
  const _WaveDecoration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 40,
      child: CustomPaint(painter: _WavePainter()),
    );
  }
}

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00E5A0).withAlpha(30)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, size.height * 0.5);
    path.quadraticBezierTo(
      size.width * 0.25,
      0,
      size.width * 0.5,
      size.height * 0.5,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height,
      size.width,
      size.height * 0.5,
    );
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WavePainter old) => false;
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
    final co2 = (data['co2'] ?? data['co2Level'] ?? 0).toDouble();
    final gasLevel =
        (data['gasLevel'] ?? data['gas_level'] ?? data['ethyleneLevel'] ?? 0)
            .toDouble();
    final riskScore = (data['riskScore'] ?? data['risk_score'] ?? 0).toDouble();
    final riskLabel =
        (data['riskLevel'] ??
                data['risk_level'] ??
                RiskColors.labelFromScore(riskScore))
            .toString();
    final daysToSpoilage =
        (data['daysToSpoilage'] ?? data['days_to_spoilage'] ?? -1).toDouble();
    final recommendation = data['recommendation'] as String? ?? '';
    final displayCommodity = commodityType.isNotEmpty
        ? commodityType
        : (data['commodityType'] ?? data['commodity_type'] ?? '').toString();
    final estimatedLossInr =
        (data['estimatedLossInr'] ?? data['estimated_loss_inr'] ?? -1)
            .toDouble();
    final riskColor = RiskColors.fromRiskScore(riskScore);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Risk gauge
          Center(
            child: _GlassCard(
              glowColor: riskColor,
              child: RiskGauge(
                riskScore: riskScore,
                label: '$riskLabel — Spoilage Risk',
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Shelf life + Loss row
          if (daysToSpoilage >= 0 || estimatedLossInr >= 0)
            Row(
              children: [
                if (daysToSpoilage >= 0)
                  Expanded(
                    child: _GlassCard(
                      glowColor: riskColor,
                      child: _ShelfLifeWidget(
                        days: daysToSpoilage,
                        riskColor: riskColor,
                        commodity: displayCommodity,
                      ),
                    ),
                  ),
                if (daysToSpoilage >= 0 && estimatedLossInr >= 0)
                  const SizedBox(width: 12),
                if (estimatedLossInr >= 0)
                  Expanded(
                    child: _GlassCard(
                      glowColor: AppColors.neonRed,
                      child: _LossWidget(loss: estimatedLossInr),
                    ),
                  ),
              ],
            ),

          if ((daysToSpoilage >= 0 || estimatedLossInr >= 0))
            const SizedBox(height: 16),

          // Recommendation
          if (recommendation.isNotEmpty) ...[
            _GlassCard(
              glowColor: AppColors.neonBlue,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.neonBlue.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.lightbulb_rounded,
                      color: AppColors.neonBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RECOMMENDATION',
                          style: GoogleFonts.dmMono(
                            fontSize: 10,
                            color: AppColors.neonBlue,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          recommendation,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Temp & Humidity gauges
          Row(
            children: [
              Expanded(
                child: _GlassCard(
                  glowColor: const Color(0xFFFF6B6B),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: TemperatureGauge(temperature: temp),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _GlassCard(
                  glowColor: const Color(0xFF4FACFE),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: HumidityGauge(humidity: humidity),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Section header
          _SectionHeader(
            title: 'Live Sensor Data',
            icon: Icons.sensors_rounded,
          ),
          const SizedBox(height: 12),

          // Sensor grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              SensorCard(
                label: 'Temperature',
                value: '${temp.toStringAsFixed(1)}°C',
                icon: Icons.thermostat_rounded,
                expanded: true,
              ),
              SensorCard(
                label: 'Humidity',
                value: '${humidity.toStringAsFixed(1)}%',
                icon: Icons.water_drop_rounded,
                expanded: true,
              ),
              SensorCard(
                label: 'CO₂',
                value: '${co2.toStringAsFixed(0)} ppm',
                icon: Icons.cloud_rounded,
                expanded: true,
              ),
              SensorCard(
                label: 'Gas / VOC',
                value: '${gasLevel.toStringAsFixed(1)} ppm',
                icon: Icons.science_rounded,
                expanded: true,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Recent alerts
          _SectionHeader(
            title: 'Recent Alerts',
            icon: Icons.notifications_rounded,
          ),
          const SizedBox(height: 12),
          _AlertsList(warehouseId: warehouseId),
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final Color glowColor;

  const _GlassCard({required this.child, required this.glowColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: glowColor.withAlpha(50), width: 1),
        boxShadow: [
          BoxShadow(
            color: glowColor.withAlpha(20),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ShelfLifeWidget extends StatelessWidget {
  final double days;
  final Color riskColor;
  final String commodity;

  const _ShelfLifeWidget({
    required this.days,
    required this.riskColor,
    required this.commodity,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SHELF LIFE',
          style: GoogleFonts.dmMono(
            fontSize: 10,
            color: AppColors.textMuted,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              days.toStringAsFixed(1),
              style: GoogleFonts.dmMono(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: riskColor,
                height: 1,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4),
              child: Text(
                'days',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
        if (commodity.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: riskColor.withAlpha(20),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              commodity,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                color: riskColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _LossWidget extends StatelessWidget {
  final double loss;
  const _LossWidget({required this.loss});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'EST. LOSS',
          style: GoogleFonts.dmMono(
            fontSize: 10,
            color: AppColors.textMuted,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(
              Icons.currency_rupee_rounded,
              color: AppColors.neonRed,
              size: 20,
            ),
            Expanded(
              child: Text(
                loss.toStringAsFixed(0),
                style: GoogleFonts.dmMono(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.neonRed,
                  height: 1,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Projected value',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 11,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 20,
          decoration: BoxDecoration(
            gradient: AppColors.gradientGreen,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Icon(icon, size: 18, color: AppColors.neonGreen),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ],
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
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.neonGreen.withAlpha(10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.neonGreen.withAlpha(40)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.neonGreen,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  'All systems normal — no alerts',
                  style: GoogleFonts.spaceGrotesk(
                    color: AppColors.neonGreen,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          );
        }
        return Column(
          children: alerts.take(5).map((alert) {
            final severityColor = alert.severity == 'critical'
                ? AppColors.neonRed
                : alert.severity == 'warning' || alert.severity == 'high'
                ? AppColors.neonAmber
                : AppColors.neonAmber;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: severityColor.withAlpha(12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: severityColor.withAlpha(50),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: severityColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: severityColor,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alert.message,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 13,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          alert.type.toUpperCase().replaceAll('_', ' '),
                          style: GoogleFonts.dmMono(
                            fontSize: 10,
                            color: severityColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(
          color: AppColors.neonGreen,
          strokeWidth: 2,
        ),
      ),
      error: (err, _) => Text(
        'Error loading alerts: $err',
        style: const TextStyle(color: AppColors.neonRed),
      ),
    );
  }
}
