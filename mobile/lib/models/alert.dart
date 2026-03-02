import 'package:cloud_firestore/cloud_firestore.dart';

/// Alert model matching M1's Firestore schema:
///   { type, severity, message, timestamp, acknowledged }
///
/// - `type` values from M1: "critical_risk", "high_risk"
/// - `severity` values from M1: "critical", "warning"
/// - `warehouseId` is NOT stored in the doc body — it's extracted from the
///   Firestore document path: warehouses/{warehouseId}/alerts/{alertId}
class Alert {
  final String id;
  final String warehouseId;
  final String type; // M1 writes: 'critical_risk', 'high_risk'
  final String severity; // M1 writes: 'critical', 'warning'
  final String message;
  final bool acknowledged;
  final DateTime timestamp;

  Alert({
    required this.id,
    this.warehouseId = '',
    required this.type,
    required this.severity,
    required this.message,
    this.acknowledged = false,
    required this.timestamp,
  });

  /// Extract warehouseId from the document reference path.
  /// Path pattern: warehouses/{warehouseId}/alerts/{alertId}
  static String _extractWarehouseId(DocumentReference ref) {
    // ref.path = "warehouses/wh001/alerts/abc123"
    final segments = ref.path.split('/');
    if (segments.length >= 2 && segments[0] == 'warehouses') {
      return segments[1];
    }
    return '';
  }

  factory Alert.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Alert(
      id: doc.id,
      warehouseId: data['warehouseId'] ?? _extractWarehouseId(doc.reference),
      type: data['type'] ?? '',
      severity: data['severity'] ?? 'warning',
      message: data['message'] ?? '',
      acknowledged: data['acknowledged'] ?? false,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory Alert.fromQueryDoc(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Alert(
      id: doc.id,
      warehouseId: data['warehouseId'] ?? _extractWarehouseId(doc.reference),
      type: data['type'] ?? '',
      severity: data['severity'] ?? 'warning',
      message: data['message'] ?? '',
      acknowledged: data['acknowledged'] ?? false,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'severity': severity,
      'message': message,
      'acknowledged': acknowledged,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }

  Alert copyWith({
    String? id,
    String? warehouseId,
    String? type,
    String? severity,
    String? message,
    bool? acknowledged,
    DateTime? timestamp,
  }) {
    return Alert(
      id: id ?? this.id,
      warehouseId: warehouseId ?? this.warehouseId,
      type: type ?? this.type,
      severity: severity ?? this.severity,
      message: message ?? this.message,
      acknowledged: acknowledged ?? this.acknowledged,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

/// Filter model for alerts
class AlertFilter {
  final String severity;
  final bool acknowledged;

  AlertFilter({
    this.severity = 'all',
    this.acknowledged = false,
  });

  AlertFilter copyWith({
    String? severity,
    bool? acknowledged,
  }) {
    return AlertFilter(
      severity: severity ?? this.severity,
      acknowledged: acknowledged ?? this.acknowledged,
    );
  }
}
