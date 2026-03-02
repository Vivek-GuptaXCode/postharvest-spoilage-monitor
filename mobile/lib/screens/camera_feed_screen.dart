import '../theme/risk_colors.dart';
import 'package:flutter/material.dart';
import '../providers/ui_state_providers.dart';
import '../providers/warehouse_providers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CameraFeedScreen extends ConsumerWidget {
  const CameraFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedWarehouse = ref.watch(selectedWarehouseIdProvider);

    if (selectedWarehouse == null) {
      return const Center(
        child: Text(
          'Select a warehouse from the Dashboard to view camera feed.',
        ),
      );
    }

    final latestData = ref.watch(latestReadingProvider(selectedWarehouse));

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Camera Feed — Visual Freshness AI',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: latestData.when(
              data: (data) {
                // M1 writes camelCase to Firestore; check camelCase first
                final imageUrl = data['imageUrl'] ?? data['image_url'] ?? '';
                final freshnessLabel = data['freshnessLabel'] ?? data['freshness_label'] ?? '';
                final freshnessScore = (data['freshnessScore'] ?? data['freshness_score'] ?? -1).toDouble();

                if (imageUrl.toString().isEmpty) {
                  return _buildPlaceholder();
                }

                return Stack(
                  children: [
                    // Camera image
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl.toString(),
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: Colors.black,
                          child: const Center(child: CircularProgressIndicator()),
                        ),
                        errorWidget: (context, url, error) => _buildPlaceholder(),
                      ),
                    ),
                    // Freshness classification overlay
                    if (freshnessLabel.toString().isNotEmpty)
                      Positioned(
                        bottom: 16,
                        left: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(180),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _freshnessIcon(freshnessLabel.toString()),
                                color: _freshnessColor(freshnessLabel.toString()),
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      freshnessLabel.toString(),
                                      style: TextStyle(
                                        color: _freshnessColor(freshnessLabel.toString()),
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (freshnessScore >= 0)
                                      Text(
                                        'Confidence: ${(freshnessScore * 100).toStringAsFixed(1)}%',
                                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error: $err')),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              FilledButton.icon(
                onPressed: () {
                  // Force refresh the image by invalidating the provider
                  ref.invalidate(latestReadingProvider(selectedWarehouse));
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  // Placeholder: future image capture trigger via API
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Image capture requires IoT device connection')),
                  );
                },
                icon: const Icon(Icons.camera_alt),
                label: const Text('Capture'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off, size: 64, color: Colors.white54),
            SizedBox(height: 12),
            Text(
              'No camera image available.\nImages appear when ESP32-CAM uploads via RPi gateway.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  Color _freshnessColor(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('fresh')) return RiskColors.safe;
    if (lower.contains('early') || lower.contains('ripe')) return RiskColors.caution;
    if (lower.contains('decay') || lower.contains('rot') || lower.contains('spoil')) return RiskColors.critical;
    return Colors.white;
  }

  IconData _freshnessIcon(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('fresh')) return Icons.check_circle;
    if (lower.contains('early') || lower.contains('ripe')) return Icons.warning_amber;
    if (lower.contains('decay') || lower.contains('rot') || lower.contains('spoil')) return Icons.dangerous;
    return Icons.help_outline;
  }
}
