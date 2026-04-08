import '../theme/risk_colors.dart';
import '../theme/app_theme.dart';
import '../models/zone.dart' as zone_model;
import 'package:flutter/material.dart';
import '../providers/ui_state_providers.dart';
import '../providers/warehouse_providers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

class CameraFeedScreen extends ConsumerWidget {
  const CameraFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedWarehouse = ref.watch(selectedWarehouseIdProvider);

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
                  color: AppColors.neonBlue.withAlpha(15),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.neonBlue.withAlpha(50)),
                ),
                child: const Icon(
                  Icons.videocam_rounded,
                  size: 36,
                  color: AppColors.neonBlue,
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

    // Get the warehouse-level latest data (has the single imageUrl from IoT)
    final latestData = ref.watch(latestReadingProvider(selectedWarehouse));
    final zonesAsync = ref.watch(zonesProvider(selectedWarehouse));
    final warehousesAsync = ref.watch(warehousesProvider);
    final warehouseName =
        warehousesAsync.whenData((warehouses) {
          try {
            return warehouses.firstWhere((w) => w.id == selectedWarehouse).name;
          } catch (_) {
            return selectedWarehouse;
          }
        }).value ??
        selectedWarehouse;

    return Container(
      color: AppColors.background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.neonBlue.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.neonBlue.withAlpha(50)),
                  ),
                  child: const Icon(
                    Icons.videocam_rounded,
                    color: AppColors.neonBlue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Zone Camera Feeds',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        warehouseName,
                        style: GoogleFonts.dmMono(
                          fontSize: 12,
                          color: AppColors.neonBlue,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Live indicator
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.neonRed.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.neonRed.withAlpha(60)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: AppColors.neonRed,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: AppColors.neonRed, blurRadius: 4),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'LIVE',
                        style: GoogleFonts.dmMono(
                          fontSize: 10,
                          color: AppColors.neonRed,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Zone camera grid
            Expanded(
              child: latestData.when(
                data: (whData) {
                  // The single imageUrl from IoT — shown for every zone
                  final sharedImageUrl =
                      (whData['imageUrl'] ?? whData['image_url'] ?? '')
                          .toString();

                  return zonesAsync.when(
                    data: (zones) {
                      if (zones.isEmpty) {
                        return _buildPlaceholder(
                          message: 'No zones configured',
                        );
                      }
                      return GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: zones.length,
                        itemBuilder: (context, index) {
                          return _ZoneCameraTile(
                            zone: zones[index],
                            warehouseId: selectedWarehouse,
                            sharedImageUrl: sharedImageUrl,
                          );
                        },
                      );
                    },
                    loading: () => const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.neonBlue,
                      ),
                    ),
                    error: (err, _) => Center(
                      child: Text(
                        'Error loading zones: $err',
                        style: const TextStyle(color: AppColors.neonRed),
                      ),
                    ),
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.neonBlue),
                ),
                error: (err, _) => Center(
                  child: Text(
                    'Error: $err',
                    style: const TextStyle(color: AppColors.neonRed),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    onPressed: () {
                      ref.invalidate(latestReadingProvider(selectedWarehouse));
                      ref.invalidate(zonesProvider(selectedWarehouse));
                    },
                    icon: Icons.refresh_rounded,
                    label: 'Refresh All',
                    color: AppColors.neonGreen,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Requires IoT device connection',
                            style: GoogleFonts.spaceGrotesk(),
                          ),
                          backgroundColor: AppColors.surfaceElevated,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                    },
                    icon: Icons.camera_alt_rounded,
                    label: 'Capture',
                    color: AppColors.neonBlue,
                    outlined: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder({String message = 'No camera image available'}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.neonBlue.withAlpha(15),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(
                Icons.videocam_off_rounded,
                size: 36,
                color: AppColors.neonBlue,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: GoogleFonts.spaceGrotesk(
                color: AppColors.textMuted,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Individual zone camera tile — shows shared image with zone-specific overlay.
class _ZoneCameraTile extends ConsumerWidget {
  final zone_model.Zone zone;
  final String warehouseId;
  final String sharedImageUrl;

  const _ZoneCameraTile({
    required this.zone,
    required this.warehouseId,
    required this.sharedImageUrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch zone-specific latest data for freshness/risk overlay
    final zoneLatest = ref.watch(
      zoneLatestProvider((warehouseId: warehouseId, zoneId: zone.id)),
    );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Zone label header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(13),
                topRight: Radius.circular(13),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.neonGreen,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.neonGreen,
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    zone.label,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Risk badge from zone data
                zoneLatest.when(
                  data: (data) {
                    final riskScore =
                        (data['riskScore'] ?? data['risk_score'] ?? 0)
                            .toDouble();
                    final riskLabel =
                        (data['riskLevel'] ?? data['risk_level'] ?? '')
                            .toString();
                    if (riskLabel.isEmpty) return const SizedBox.shrink();
                    final riskColor = RiskColors.fromRiskScore(riskScore);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: riskColor.withAlpha(25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        riskLabel.toUpperCase(),
                        style: GoogleFonts.dmMono(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: riskColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),

          // Image area
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(13),
                bottomRight: Radius.circular(13),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Image (same for all zones — hackathon constraint)
                  if (sharedImageUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: sharedImageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: AppColors.surface,
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.neonBlue,
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => _noImagePlaceholder(),
                    )
                  else
                    _noImagePlaceholder(),

                  // Scan line overlay
                  CustomPaint(painter: _ScanLinePainter()),

                  // Corner decorations
                  ..._buildMiniCorners(),

                  // Bottom overlay: freshness + sensor data
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: zoneLatest.when(
                      data: (data) => _buildZoneOverlay(data),
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noImagePlaceholder() {
    return Container(
      color: AppColors.surface,
      child: Center(
        child: Icon(
          Icons.videocam_off_rounded,
          color: AppColors.textMuted.withAlpha(100),
          size: 28,
        ),
      ),
    );
  }

  Widget _buildZoneOverlay(Map<String, dynamic> data) {
    if (data.isEmpty) return const SizedBox.shrink();

    final temp = (data['temperature'] ?? 0).toDouble();
    final humidity = (data['humidity'] ?? 0).toDouble();
    final freshnessLabel =
        (data['freshnessLabel'] ?? data['freshness_label'] ?? '').toString();
    final riskScore =
        (data['riskScore'] ?? data['risk_score'] ?? 0).toDouble();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            const Color(0xFF0D1117).withAlpha(220),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Freshness label if available
          if (freshnessLabel.isNotEmpty)
            Text(
              freshnessLabel,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _freshnessColor(freshnessLabel),
              ),
            ),
          const SizedBox(height: 2),
          // Compact sensor data row
          Row(
            children: [
              const Icon(Icons.thermostat_rounded, size: 10, color: Color(0xFFFF6B6B)),
              const SizedBox(width: 2),
              Text(
                '${temp.toStringAsFixed(1)}°',
                style: GoogleFonts.dmMono(
                  fontSize: 9,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.water_drop_rounded, size: 10, color: Color(0xFF4FACFE)),
              const SizedBox(width: 2),
              Text(
                '${humidity.toStringAsFixed(0)}%',
                style: GoogleFonts.dmMono(
                  fontSize: 9,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                'R:${riskScore.toStringAsFixed(0)}',
                style: GoogleFonts.dmMono(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: RiskColors.fromRiskScore(riskScore),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMiniCorners() {
    const color = AppColors.neonBlue;
    return [
      const Positioned(
        top: 4,
        left: 4,
        child: _MiniCorner(color: color, top: true, left: true),
      ),
      const Positioned(
        top: 4,
        right: 4,
        child: _MiniCorner(color: color, top: true, left: false),
      ),
      const Positioned(
        bottom: 4,
        left: 4,
        child: _MiniCorner(color: color, top: false, left: true),
      ),
      const Positioned(
        bottom: 4,
        right: 4,
        child: _MiniCorner(color: color, top: false, left: false),
      ),
    ];
  }

  Color _freshnessColor(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('fresh')) return RiskColors.safe;
    if (lower.contains('early') || lower.contains('ripe'))
      return RiskColors.caution;
    if (lower.contains('decay') ||
        lower.contains('rot') ||
        lower.contains('spoil'))
      return RiskColors.critical;
    return Colors.white;
  }
}

class _MiniCorner extends StatelessWidget {
  final Color color;
  final bool top, left;
  const _MiniCorner({
    required this.color,
    required this.top,
    required this.left,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 10,
      height: 10,
      child: CustomPaint(
        painter: _CornerPainter(
          color: color,
          thickness: 1.5,
          top: top,
          left: left,
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double thickness;
  final bool top, left;

  const _CornerPainter({
    required this.color,
    required this.thickness,
    required this.top,
    required this.left,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final x = left ? 0.0 : size.width;
    final y = top ? 0.0 : size.height;
    final dx = left ? size.width : -size.width;
    final dy = top ? size.height : -size.height;

    canvas.drawLine(Offset(x, y), Offset(x + dx, y), paint);
    canvas.drawLine(Offset(x, y), Offset(x, y + dy), paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}

class _ScanLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          AppColors.neonBlue.withAlpha(10),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_ScanLinePainter old) => false;
}

class _ActionButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final Color color;
  final bool outlined;

  const _ActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.color,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          gradient: outlined
              ? null
              : LinearGradient(colors: [color, color.withAlpha(180)]),
          color: outlined ? Colors.transparent : null,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withAlpha(outlined ? 120 : 0)),
          boxShadow: outlined
              ? null
              : [
                  BoxShadow(
                    color: color.withAlpha(60),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: outlined ? color : Colors.black),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: outlined ? color : Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
