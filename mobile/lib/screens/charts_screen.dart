import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/reading.dart';
import '../theme/app_theme.dart';
import '../providers/ui_state_providers.dart';
import '../providers/warehouse_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

class ChartsScreen extends ConsumerWidget {
  const ChartsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedWarehouse = ref.watch(selectedWarehouseIdProvider);
    final timeRange = ref.watch(timeRangeProvider);
    final chartType = ref.watch(selectedChartTypeProvider);
    final selectedZoneId = ref.watch(selectedZoneIdProvider);

    if (selectedWarehouse == null) {
      return _EmptySelection();
    }

    // Use zone-level or warehouse-level readings based on zone selection
    final historyAsync = selectedZoneId != null
        ? ref.watch(zoneReadingsHistoryProvider((
            warehouseId: selectedWarehouse,
            zoneId: selectedZoneId,
            timeRange: timeRange,
          )))
        : ref.watch(readingsHistoryProvider(
            (warehouseId: selectedWarehouse, timeRange: timeRange),
          ));

    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          // Zone selector for charts
          _ChartsZoneSelector(warehouseId: selectedWarehouse),

          // Chart type selector
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _ChartTypeTab(
                    type: ChartType.temperature,
                    label: 'TEMP',
                    color: const Color(0xFFFF6B6B),
                    current: chartType,
                    ref: ref,
                  ),
                  _ChartTypeTab(
                    type: ChartType.humidity,
                    label: 'HUM',
                    color: const Color(0xFF4FACFE),
                    current: chartType,
                    ref: ref,
                  ),
                  _ChartTypeTab(
                    type: ChartType.co2,
                    label: 'CO₂',
                    color: const Color(0xFF43E97B),
                    current: chartType,
                    ref: ref,
                  ),
                  _ChartTypeTab(
                    type: ChartType.ethylene,
                    label: 'C₂H₄',
                    color: const Color(0xFFA78BFA),
                    current: chartType,
                    ref: ref,
                  ),
                  _ChartTypeTab(
                    type: ChartType.multiLine,
                    label: 'ALL',
                    color: AppColors.neonGreen,
                    current: chartType,
                    ref: ref,
                  ),
                  _ChartTypeTab(
                    type: ChartType.riskBar,
                    label: 'RISK',
                    color: AppColors.neonAmber,
                    current: chartType,
                    ref: ref,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Time range chips
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 5,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final ranges = ['1h', '6h', '24h', '7d', '30d'];
                final r = ranges[i];
                final selected = timeRange == r;
                return GestureDetector(
                  onTap: () => ref.read(timeRangeProvider.notifier).state = r,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: selected
                          ? const LinearGradient(colors: [Color(0xFF00E5A0), Color(0xFF00B4D8)])
                          : null,
                      color: selected ? null : AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: selected ? Colors.transparent : AppColors.border),
                      boxShadow: selected
                          ? [BoxShadow(color: AppColors.neonGreen.withAlpha(60), blurRadius: 12)]
                          : null,
                    ),
                    child: Text(
                      r,
                      style: GoogleFonts.dmMono(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.black : AppColors.textMuted,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // Chart area
          Expanded(
            child: historyAsync.when(
              data: (readings) {
                if (readings.isEmpty) {
                  return _NoData();
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 16, 16),
                  child: _buildChart(context, readings, chartType),
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator(color: AppColors.neonGreen)),
              error: (err, _) => Center(
                child: Text('Chart error: $err', style: const TextStyle(color: AppColors.neonRed)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(BuildContext context, List<Reading> readings, ChartType type) {
    if (type == ChartType.multiLine) return _buildMultiLineChart(context, readings);
    if (type == ChartType.riskBar) return _buildRiskBarChart(context, readings);
    return _buildSingleMetricChart(context, readings, type);
  }

  // ─── helpers ─────────────────────────────────────────────────────────────

  double _xInterval(double range) {
    if (range <= 0) return 1;
    if (range <= 1) return 0.25;
    if (range <= 6) return 1;
    if (range <= 24) return 4;
    if (range <= 168) return 24;
    return 120;
  }

  static const _chartMeta = {
    ChartType.temperature: (Color(0xFFFF6B6B), Color(0xFFFF8E53), '°C', 'Temperature'),
    ChartType.humidity: (Color(0xFF4FACFE), Color(0xFF00F2FE), '%', 'Humidity'),
    ChartType.co2: (Color(0xFF43E97B), Color(0xFF38F9D7), 'ppm', 'CO₂'),
    ChartType.ethylene: (Color(0xFFA78BFA), Color(0xFF8B5CF6), 'ppm', 'Ethylene'),
  };

  FlGridData _grid() => FlGridData(
    show: true,
    drawVerticalLine: false,
    getDrawingHorizontalLine: (_) =>
        FlLine(color: Colors.white.withAlpha(12), strokeWidth: 1, dashArray: [6, 6]),
  );

  FlBorderData _border() => FlBorderData(
    show: true,
    border: Border(
      bottom: BorderSide(color: Colors.white.withAlpha(25), width: 1),
      left: BorderSide(color: Colors.white.withAlpha(25), width: 1),
    ),
  );

  SideTitles _xTitles(double maxX, double interval) => SideTitles(
    showTitles: true,
    reservedSize: 30,
    interval: interval,
    getTitlesWidget: (value, meta) {
      if (value == meta.min || value == meta.max) return const SizedBox.shrink();
      String text;
      if (maxX <= 1) {
        text = '${(value * 60).toInt()}m';
      } else if (maxX <= 168) {
        text = '${value.toInt()}h';
      } else {
        text = '${(value / 24).toInt()}d';
      }
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(text, style: GoogleFonts.dmMono(fontSize: 10, color: AppColors.textMuted)),
      );
    },
  );

  LineChartBarData _line(List<FlSpot> spots, Color main, Color accent) => LineChartBarData(
    spots: spots,
    isCurved: true,
    preventCurveOverShooting: true,
    curveSmoothness: 0.3,
    barWidth: 2.5,
    isStrokeCapRound: true,
    color: main,
    shadow: Shadow(color: main.withAlpha(80), blurRadius: 12, offset: const Offset(0, 6)),
    dotData: FlDotData(
      show: spots.length <= 60,
      getDotPainter: (_, __, ___, ____) =>
          FlDotCirclePainter(radius: 3, color: main, strokeWidth: 2, strokeColor: Colors.white),
    ),
    belowBarData: BarAreaData(
      show: true,
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [main.withAlpha(70), accent.withAlpha(30), accent.withAlpha(0)],
        stops: const [0.0, 0.5, 1.0],
      ),
    ),
  );

  Widget _legendItem(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: color.withAlpha(120), blurRadius: 6, spreadRadius: 1)],
        ),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: GoogleFonts.spaceGrotesk(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
      ),
    ],
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // SINGLE METRIC
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSingleMetricChart(BuildContext context, List<Reading> readings, ChartType type) {
    final meta = _chartMeta[type]!;
    final mainColor = meta.$1;
    final accentColor = meta.$2;
    final unit = meta.$3;
    final label = meta.$4;

    final spots = readings.map((r) {
      final h = r.timestamp.difference(readings.first.timestamp).inMinutes / 60.0;
      final val = switch (type) {
        ChartType.temperature => r.temperature,
        ChartType.humidity => r.humidity,
        ChartType.co2 => r.co2Level ?? 0.0,
        ChartType.ethylene => r.ethyleneLevel ?? 0.0,
        _ => 0.0,
      };
      return FlSpot(h, val);
    }).toList();

    if (spots.isEmpty) return const SizedBox.shrink();

    final maxX = spots.last.x;
    final xInterval = _xInterval(maxX);
    final yVals = spots.map((s) => s.y);
    final dataMin = yVals.reduce(min);
    final dataMax = yVals.reduce(max);
    final yPad = max((dataMax - dataMin) * 0.15, 1.0);
    final chartMinY = (dataMin - yPad).floorToDouble();
    final chartMaxY = (dataMax + yPad).ceilToDouble();
    final yInterval = max(1.0, ((chartMaxY - chartMinY) / 5).ceilToDouble());

    final timeSpan = readings.last.timestamp
        .difference(readings.first.timestamp)
        .inHours
        .toDouble();
    final minScale = 1;
    final maxScale = timeSpan > 0 ? 4 * timeSpan : minScale;

    return Column(
      children: [
        // Stat card header
        Container(
          margin: const EdgeInsets.only(left: 8, right: 0, bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: mainColor.withAlpha(15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: mainColor.withAlpha(50)),
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: GoogleFonts.dmMono(fontSize: 10, color: mainColor, letterSpacing: 1),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${spots.last.y.toStringAsFixed(1)} $unit',
                    style: GoogleFonts.dmMono(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _MiniStat('MIN', '${dataMin.toStringAsFixed(1)} $unit', mainColor),
                  const SizedBox(height: 4),
                  _MiniStat('MAX', '${dataMax.toStringAsFixed(1)} $unit', mainColor),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: LineChart(
            LineChartData(
              minY: chartMinY,
              maxY: chartMaxY,
              clipData: const FlClipData.all(),
              gridData: _grid(),
              borderData: _border(),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(sideTitles: _xTitles(maxX, xInterval)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 46,
                    interval: yInterval,
                    getTitlesWidget: (value, meta) {
                      if (value == meta.min || value == meta.max) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          value.toStringAsFixed(value % 1 == 0 ? 0 : 1),
                          style: GoogleFonts.dmMono(fontSize: 10, color: AppColors.textMuted),
                        ),
                      );
                    },
                  ),
                ),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              lineTouchData: LineTouchData(
                handleBuiltInTouches: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => const Color(0xFF1E2533),
                  tooltipPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  tooltipMargin: 12,
                  tooltipBorder: BorderSide(color: mainColor.withAlpha(100), width: 1),
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItems: (spots) => spots
                      .map(
                        (spot) => LineTooltipItem(
                          '${spot.y.toStringAsFixed(1)} $unit',
                          GoogleFonts.dmMono(
                            color: mainColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                          children: [
                            TextSpan(
                              text: '\n${spot.x.toStringAsFixed(1)}h',
                              style: GoogleFonts.dmMono(color: AppColors.textMuted, fontSize: 10),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
              lineBarsData: [_line(spots, mainColor, accentColor)],
            ),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOutCubic,

            /* Chart Zoom */
            transformationConfig: FlTransformationConfig(
              scaleEnabled: true,
              scaleAxis: FlScaleAxis.horizontal,
              minScale: minScale.toDouble(),
              maxScale: maxScale.toDouble(),
              panEnabled: true,
            ),
            /* End Chart Zoom */
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MULTI LINE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMultiLineChart(BuildContext context, List<Reading> readings) {
    const tempColor = Color(0xFFFF6B6B);
    const humidColor = Color(0xFF4FACFE);

    List<FlSpot> makeSpots(double Function(Reading) v) => readings.map((r) {
      final h = r.timestamp.difference(readings.first.timestamp).inMinutes / 60.0;
      return FlSpot(h, v(r));
    }).toList();

    final tempSpots = makeSpots((r) => r.temperature);
    final humidSpots = makeSpots((r) => r.humidity);
    final maxX = tempSpots.isEmpty ? 0.0 : tempSpots.last.x;

    final timeSpan = readings.last.timestamp
        .difference(readings.first.timestamp)
        .inHours
        .toDouble();
    final minScale = 1;
    final maxScale = timeSpan > 0 ? 4 * timeSpan : minScale;

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(left: 8, right: 0, bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _legendItem(tempColor, 'Temperature (°C)'),
              Container(width: 1, height: 24, color: AppColors.border),
              _legendItem(humidColor, 'Humidity (%)'),
            ],
          ),
        ),
        Expanded(
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: 100,
              clipData: const FlClipData.all(),
              gridData: _grid(),
              borderData: _border(),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(sideTitles: _xTitles(maxX, _xInterval(maxX))),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 38,
                    interval: 20,
                    getTitlesWidget: (value, meta) {
                      if (value == meta.min || value == meta.max) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          '${value.toInt()}',
                          style: GoogleFonts.dmMono(fontSize: 10, color: AppColors.textMuted),
                        ),
                      );
                    },
                  ),
                ),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              lineTouchData: LineTouchData(
                handleBuiltInTouches: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => const Color(0xFF1E2533),
                  tooltipPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  tooltipBorder: const BorderSide(color: AppColors.border, width: 1),
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItems: (spots) => spots.map((spot) {
                    final isTemp = spot.barIndex == 0;
                    final color = isTemp ? tempColor : humidColor;
                    final unit = isTemp ? '°C' : '%';
                    return LineTooltipItem(
                      '${isTemp ? 'Temp' : 'Humidity'}: ${spot.y.toStringAsFixed(1)} $unit',
                      GoogleFonts.dmMono(color: color, fontWeight: FontWeight.w600, fontSize: 12),
                    );
                  }).toList(),
                ),
              ),
              lineBarsData: [
                _line(tempSpots, tempColor, const Color(0xFFFF8E53)),
                _line(humidSpots, humidColor, const Color(0xFF00F2FE)),
              ],
            ),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOutCubic,

            /* Chart Zoom */
            transformationConfig: FlTransformationConfig(
              scaleEnabled: true,
              scaleAxis: FlScaleAxis.horizontal,
              minScale: minScale.toDouble(),
              maxScale: maxScale.toDouble(),
              panEnabled: true,
            ),
            /* End Chart Zoom */
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RISK BAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRiskBarChart(BuildContext context, List<Reading> readings) {
    int low = 0, med = 0, high = 0, critical = 0;
    for (final r in readings) {
      final risk = (r.riskScore ?? 0.0).clamp(0.0, 100.0);
      if (risk < 25)
        low++;
      else if (risk < 50)
        med++;
      else if (risk < 75)
        high++;
      else
        critical++;
    }

    final counts = [low, med, high, critical];
    final maxVal = counts.reduce(max).toDouble();
    final yInterval = max(1.0, (maxVal / 4).ceilToDouble());

    const gradients = [
      [Color(0xFF00E5A0), Color(0xFF00B4D8)],
      [Color(0xFFFFB703), Color(0xFFFB8500)],
      [Color(0xFFFF8C42), Color(0xFFFF6B2B)],
      [Color(0xFFFF4757), Color(0xFFFF6B9D)],
    ];
    const labels = ['Low', 'Medium', 'High', 'Critical'];

    final timeSpan = readings.last.timestamp
        .difference(readings.first.timestamp)
        .inHours
        .toDouble();
    final minScale = 1;
    final maxScale = timeSpan > 0 ? 4 * timeSpan : minScale;

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(left: 8, right: 0, bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(
              4,
              (i) => Column(
                children: [
                  Text(
                    '${counts[i]}',
                    style: GoogleFonts.dmMono(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: gradients[i][0],
                    ),
                  ),
                  Text(
                    labels[i],
                    style: GoogleFonts.spaceGrotesk(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: BarChart(
            BarChartData(
              maxY: maxVal + yInterval,
              barGroups: List.generate(
                4,
                (i) => BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: counts[i].toDouble(),
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: gradients[i],
                      ),
                      width: 36,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(10),
                        topRight: Radius.circular(10),
                      ),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: maxVal + yInterval,
                        color: Colors.white.withAlpha(6),
                      ),
                    ),
                  ],
                ),
              ),
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => const Color(0xFF1E2533),
                  tooltipPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  tooltipBorder: const BorderSide(color: AppColors.border, width: 1),
                  getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                    '${labels[groupIndex]}\n',
                    GoogleFonts.spaceGrotesk(
                      color: gradients[groupIndex][0],
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    children: [
                      TextSpan(
                        text: '${rod.toY.toInt()} readings',
                        style: GoogleFonts.dmMono(color: AppColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    getTitlesWidget: (value, _) {
                      final i = value.toInt();
                      if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          labels[i],
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: gradients[i][0],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    interval: yInterval,
                    getTitlesWidget: (value, meta) {
                      if (value == meta.min || value == meta.max) return const SizedBox.shrink();
                      return Text(
                        '${value.toInt()}',
                        style: GoogleFonts.dmMono(fontSize: 10, color: AppColors.textMuted),
                      );
                    },
                  ),
                ),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: _grid(),
              borderData: _border(),
            ),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOutCubic,

            /* Chart Zoom */
            transformationConfig: FlTransformationConfig(
              scaleEnabled: true,
              scaleAxis: FlScaleAxis.horizontal,
              minScale: minScale.toDouble(),
              maxScale: maxScale.toDouble(),
              panEnabled: true,
            ),
            /* End Chart Zoom */
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _MiniStat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label ', style: GoogleFonts.dmMono(fontSize: 10, color: AppColors.textMuted)),
        Text(
          value,
          style: GoogleFonts.dmMono(fontSize: 12, fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }
}

class _ChartTypeTab extends StatelessWidget {
  final ChartType type, current;
  final String label;
  final Color color;
  final WidgetRef ref;

  const _ChartTypeTab({
    required this.type,
    required this.label,
    required this.color,
    required this.current,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final selected = type == current;
    return GestureDetector(
      onTap: () => ref.read(selectedChartTypeProvider.notifier).state = type,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: selected ? color.withAlpha(25) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: selected ? Border.all(color: color.withAlpha(80), width: 1) : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.dmMono(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: selected ? color : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _EmptySelection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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
                color: AppColors.neonGreen.withAlpha(15),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.neonGreen.withAlpha(50)),
              ),
              child: const Icon(Icons.show_chart_rounded, size: 36, color: AppColors.neonGreen),
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
              style: GoogleFonts.spaceGrotesk(fontSize: 13, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoData extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.bar_chart_rounded, size: 48, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(
            'No data for this period',
            style: GoogleFonts.spaceGrotesk(fontSize: 16, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Zone selector chips displayed above the chart type tabs.
class _ChartsZoneSelector extends ConsumerWidget {
  final String warehouseId;
  const _ChartsZoneSelector({required this.warehouseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zonesAsync = ref.watch(zonesProvider(warehouseId));
    final selectedZoneId = ref.watch(selectedZoneIdProvider);

    return zonesAsync.when(
      data: (zones) {
        if (zones.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: zones.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final isAll = index == 0;
                final zoneId = isAll ? null : zones[index - 1].id;
                final label = isAll ? 'All Zones' : zones[index - 1].label;
                final isSelected = selectedZoneId == zoneId;

                return GestureDetector(
                  onTap: () {
                    ref.read(selectedZoneIdProvider.notifier).state = zoneId;
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.neonGreen.withAlpha(25)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.neonGreen.withAlpha(80)
                            : AppColors.border,
                      ),
                    ),
                    child: Text(
                      label,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? AppColors.neonGreen
                            : AppColors.textMuted,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
      loading: () => const SizedBox(height: 38),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
