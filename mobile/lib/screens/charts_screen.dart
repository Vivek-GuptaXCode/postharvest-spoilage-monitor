import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/reading.dart';
import '../providers/ui_state_providers.dart';
import '../providers/warehouse_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChartsScreen extends ConsumerWidget {
  const ChartsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedWarehouse = ref.watch(selectedWarehouseIdProvider);
    final timeRange = ref.watch(timeRangeProvider);
    final chartType = ref.watch(selectedChartTypeProvider);

    if (selectedWarehouse == null) {
      return const Center(
        child: Text('Select a warehouse from the Dashboard to view charts.'),
      );
    }

    final historyAsync = ref.watch(
      readingsHistoryProvider((
        warehouseId: selectedWarehouse,
        timeRange: timeRange,
      )),
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Chart type selector
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<ChartType>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ChartType.temperature, label: Text('Temp')),
                ButtonSegment(value: ChartType.humidity, label: Text('Humid')),
                ButtonSegment(value: ChartType.co2, label: Text('CO₂')),
                ButtonSegment(value: ChartType.ethylene, label: Text('C₂H₄')),
                ButtonSegment(value: ChartType.multiLine, label: Text('All')),
                ButtonSegment(value: ChartType.riskBar, label: Text('Risk')),
              ],
              selected: {chartType},
              onSelectionChanged: (selected) {
                ref.read(selectedChartTypeProvider.notifier).state =
                    selected.first;
              },
            ),
          ),
          const SizedBox(height: 8),

          // Time range chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children:
                  ['1h', '6h', '24h', '7d', '30d'].map((range) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(range),
                        selected: timeRange == range,
                        onSelected: (_) {
                          ref.read(timeRangeProvider.notifier).state = range;
                        },
                      ),
                    );
                  }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // Chart area
          Expanded(
            child: historyAsync.when(
              data: (readings) {
                if (readings.isEmpty) {
                  return const Center(child: Text('No data for this period.'));
                }

                // Multi-line overlay chart
                if (chartType == ChartType.multiLine) {
                  return _buildMultiLineChart(context, readings);
                }

                // Risk distribution bar chart
                if (chartType == ChartType.riskBar) {
                  return _buildRiskBarChart(context, readings);
                }

                // Single metric time-series chart
                return _buildSingleMetricChart(context, readings, chartType);
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Chart error: $err')),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Single Metric Line Chart ─────────────────────────────────────────────

  Widget _buildSingleMetricChart(
    BuildContext context,
    List<Reading> readings,
    ChartType type,
  ) {
    final spots = <FlSpot>[];
    for (int i = 0; i < readings.length; i++) {
      final r = readings[i];
      final hourOffset =
          r.timestamp.difference(readings.first.timestamp).inMinutes / 60.0;
      final val = switch (type) {
        ChartType.temperature => r.temperature,
        ChartType.humidity => r.humidity,
        ChartType.co2 => r.co2Level ?? 0.0,
        ChartType.ethylene => r.ethyleneLevel ?? 0.0,
        _ => 0.0,
      };
      spots.add(FlSpot(hourOffset, val));
    }

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: true),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 4,
              getTitlesWidget: (value, meta) {
                final hour = value.toInt();
                if (hour % 4 == 0) {
                  return Text('${hour}h', style: const TextStyle(fontSize: 10));
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 40),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: true),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                return LineTooltipItem(
                  spot.y.toStringAsFixed(1),
                  const TextStyle(color: Colors.white, fontSize: 12),
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Theme.of(context).colorScheme.primary.withAlpha(50),
            ),
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // ─── Multi-Line Chart (Temp + Humidity + Risk) ────────────────────────────

  Widget _buildMultiLineChart(BuildContext context, List<Reading> readings) {
    final tempSpots =
        readings.map((r) {
          final hourOffset =
              r.timestamp.difference(readings.first.timestamp).inMinutes / 60.0;
          return FlSpot(hourOffset, r.temperature);
        }).toList();

    final humiditySpots =
        readings.map((r) {
          final hourOffset =
              r.timestamp.difference(readings.first.timestamp).inMinutes / 60.0;
          return FlSpot(hourOffset, r.humidity);
        }).toList();

    return Column(
      children: [
        // Legend row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legendItem(Colors.redAccent, 'Temperature (°C)'),
            const SizedBox(width: 16),
            _legendItem(Colors.blueAccent, 'Humidity (%)'),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: 100,
              lineBarsData: [
                // Temperature line
                LineChartBarData(
                  spots: tempSpots,
                  isCurved: true,
                  color: Colors.redAccent,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: Colors.redAccent.withAlpha(25),
                  ),
                ),
                // Humidity line
                LineChartBarData(
                  spots: humiditySpots,
                  isCurved: true,
                  color: Colors.blueAccent,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                ),
              ],
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: 4,
                    getTitlesWidget: (value, meta) {
                      final hour = value.toInt();
                      if (hour % 4 == 0) {
                        return Text(
                          '${hour}h',
                          style: const TextStyle(fontSize: 10),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              gridData: const FlGridData(show: true),
              borderData: FlBorderData(show: true),
              lineTouchData: LineTouchData(
                handleBuiltInTouches: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      final label = spot.barIndex == 0 ? 'Temp' : 'Humidity';
                      return LineTooltipItem(
                        '$label: ${spot.y.toStringAsFixed(1)}',
                        const TextStyle(color: Colors.white, fontSize: 12),
                      );
                    }).toList();
                  },
                ),
              ),
            ),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          ),
        ),
      ],
    );
  }

  // ─── Risk Distribution Bar Chart ──────────────────────────────────────────

  Widget _buildRiskBarChart(BuildContext context, List<Reading> readings) {
    // Use ML model's riskScore from Firestore readings (written by M1's Cloud Function)
    int lowCount = 0, medCount = 0, highCount = 0, criticalCount = 0;

    for (final r in readings) {
      final risk = (r.riskScore ?? 0.0).clamp(0.0, 100.0);
      if (risk < 25) {
        lowCount++;
      } else if (risk < 50) {
        medCount++;
      } else if (risk < 75) {
        highCount++;
      } else {
        criticalCount++;
      }
    }

    return Column(
      children: [
        Text(
          'Risk Distribution',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: BarChart(
            BarChartData(
              barGroups: [
                BarChartGroupData(
                  x: 0,
                  barRods: [
                    BarChartRodData(
                      toY: lowCount.toDouble(),
                      color: Colors.green,
                      width: 20,
                    ),
                  ],
                ),
                BarChartGroupData(
                  x: 1,
                  barRods: [
                    BarChartRodData(
                      toY: medCount.toDouble(),
                      color: Colors.yellow,
                      width: 20,
                    ),
                  ],
                ),
                BarChartGroupData(
                  x: 2,
                  barRods: [
                    BarChartRodData(
                      toY: highCount.toDouble(),
                      color: Colors.orange,
                      width: 20,
                    ),
                  ],
                ),
                BarChartGroupData(
                  x: 3,
                  barRods: [
                    BarChartRodData(
                      toY: criticalCount.toDouble(),
                      color: Colors.red,
                      width: 20,
                    ),
                  ],
                ),
              ],
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, _) {
                      const labels = ['Low', 'Medium', 'High', 'Critical'];
                      if (value.toInt() >= 0 && value.toInt() < labels.length) {
                        return Text(
                          labels[value.toInt()],
                          style: const TextStyle(fontSize: 11),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 30),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              gridData: const FlGridData(show: true),
              borderData: FlBorderData(show: true),
            ),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          ),
        ),
      ],
    );
  }

  // ─── Legend Helper ────────────────────────────────────────────────────────

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
