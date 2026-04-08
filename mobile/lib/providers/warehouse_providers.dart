import '../models/reading.dart';
import '../models/warehouse.dart';
import '../models/zone.dart' as zone_model;
import '../models/alert.dart' as alert_model;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stream all warehouses for the current user
final warehousesProvider = StreamProvider<List<Warehouse>>((ref) {
  return FirebaseFirestore.instance
      .collection('warehouses')
      .orderBy('name')
      .snapshots()
      .map((snap) => snap.docs.map(Warehouse.fromFirestore).toList());
});

/// Stream the latest sensor data for a specific warehouse (single document)
/// Listens to: warehouses/{warehouseId}/latest/current
final latestReadingProvider =
    StreamProvider.family<Map<String, dynamic>, String>((ref, warehouseId) {
      return FirebaseFirestore.instance
          .doc('warehouses/$warehouseId/latest/current')
          .snapshots()
          .map((snap) {
            if (snap.exists) {
              final data = snap.data()!;
              // Access typed fields: data['temperature'] as num, etc.
              return data;
            }
            return <String, dynamic>{};
          });
    });

/// Stream alerts ordered by timestamp — returns typed AlertModel list
final alertsProvider = StreamProvider.family<List<alert_model.Alert>, String>((
  ref,
  warehouseId,
) {
  return FirebaseFirestore.instance
      .collection('warehouses/$warehouseId/alerts')
      .orderBy('timestamp', descending: true)
      .limit(20)
      .snapshots()
      .map(
        (snap) =>
            snap.docs
                .map((doc) => alert_model.Alert.fromFirestore(doc))
                .toList(),
      );
});

/// Stream last 24h readings (or custom range) — returns typed Reading list
/// Important: Firestore requires a composite index for where() + orderBy()
/// on different fields. The SDK will print an error with a direct link to
/// create the index in the Firebase Console.
final readingsHistoryProvider = StreamProvider.family<
  List<Reading>,
  ({String warehouseId, String timeRange})
>((ref, params) {
  final now = DateTime.now();
  late DateTime startTime;

  switch (params.timeRange) {
    case '1h':
      startTime = now.subtract(const Duration(hours: 1));
      break;
    case '6h':
      startTime = now.subtract(const Duration(hours: 6));
      break;
    case '24h':
      startTime = now.subtract(const Duration(hours: 24));
      break;
    case '7d':
      startTime = now.subtract(const Duration(days: 7));
      break;
    case '30d':
      startTime = now.subtract(const Duration(days: 30));
      break;
    default:
      startTime = now.subtract(const Duration(hours: 24));
  }

  return FirebaseFirestore.instance
      .collection('warehouses/${params.warehouseId}/readings')
      .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startTime))
      .orderBy('timestamp', descending: false)
      .snapshots()
      .map(
        (snap) => snap.docs.map((doc) => Reading.fromFirestore(doc)).toList(),
      );
});

/// Stream a single warehouse document (for metadata like commodityType)
final warehouseDocProvider = StreamProvider.family<Warehouse, String>((ref, warehouseId) {
  return FirebaseFirestore.instance
      .doc('warehouses/$warehouseId')
      .snapshots()
      .map((snap) => Warehouse.fromFirestore(snap));
});

/// Check snapshot metadata for offline/cache status
/// Usage: snap.metadata.isFromCache, snap.metadata.hasPendingWrites
/// Android/iOS: Offline persistence is enabled by default (100MB cache).

/// Provider for a single document with metadata awareness
final latestReadingWithMetaProvider = StreamProvider.family<
  ({Map<String, dynamic> data, bool isFromCache, bool hasPendingWrites}),
  String
>((ref, warehouseId) {
  return FirebaseFirestore.instance
      .doc('warehouses/$warehouseId/latest/current')
      .snapshots()
      .map(
        (snap) => (
          data: snap.data() ?? {},
          isFromCache: snap.metadata.isFromCache,
          hasPendingWrites: snap.metadata.hasPendingWrites,
        ),
      );
});

// ═══════════════════════════════════════════════════════════════════════
// ZONE-AWARE PROVIDERS
// ═══════════════════════════════════════════════════════════════════════

/// Stream all zones for a warehouse
/// Listens to: warehouses/{warehouseId}/zones
final zonesProvider = StreamProvider.family<List<zone_model.Zone>, String>((
  ref,
  warehouseId,
) {
  return FirebaseFirestore.instance
      .collection('warehouses/$warehouseId/zones')
      .snapshots()
      .map(
        (snap) =>
            snap.docs.map((doc) => zone_model.Zone.fromFirestore(doc)).toList(),
      );
});

/// Stream the latest sensor data for a specific zone
/// Listens to: warehouses/{warehouseId}/zones/{zoneId}/latest/current
final zoneLatestProvider = StreamProvider.family<
  Map<String, dynamic>,
  ({String warehouseId, String zoneId})
>((ref, params) {
  return FirebaseFirestore.instance
      .doc(
        'warehouses/${params.warehouseId}/zones/${params.zoneId}/latest/current',
      )
      .snapshots()
      .map((snap) {
        if (snap.exists) {
          return snap.data()!;
        }
        return <String, dynamic>{};
      });
});

/// Stream historical readings for a specific zone
final zoneReadingsHistoryProvider = StreamProvider.family<
  List<Reading>,
  ({String warehouseId, String zoneId, String timeRange})
>((ref, params) {
  final now = DateTime.now();
  late DateTime startTime;

  switch (params.timeRange) {
    case '1h':
      startTime = now.subtract(const Duration(hours: 1));
      break;
    case '6h':
      startTime = now.subtract(const Duration(hours: 6));
      break;
    case '24h':
      startTime = now.subtract(const Duration(hours: 24));
      break;
    case '7d':
      startTime = now.subtract(const Duration(days: 7));
      break;
    case '30d':
      startTime = now.subtract(const Duration(days: 30));
      break;
    default:
      startTime = now.subtract(const Duration(hours: 24));
  }

  return FirebaseFirestore.instance
      .collection(
        'warehouses/${params.warehouseId}/zones/${params.zoneId}/readings',
      )
      .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startTime))
      .orderBy('timestamp', descending: false)
      .snapshots()
      .map(
        (snap) => snap.docs.map((doc) => Reading.fromFirestore(doc)).toList(),
      );
});
