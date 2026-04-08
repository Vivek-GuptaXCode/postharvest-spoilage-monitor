import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a physical zone within a warehouse.
///
/// Firestore path: warehouses/{warehouseId}/zones/{zoneId}
class Zone {
  final String id;
  final String label;
  final String sensorId;
  final String commodityType;
  final DateTime? createdAt;

  Zone({
    required this.id,
    required this.label,
    this.sensorId = '',
    this.commodityType = '',
    this.createdAt,
  });

  factory Zone.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Zone(
      id: doc.id,
      label: data['label'] ?? doc.id,
      sensorId: data['sensorId'] ?? '',
      commodityType: data['commodityType'] ?? data['commodity_type'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  factory Zone.fromMap(Map<String, dynamic> data, {String id = ''}) {
    return Zone(
      id: id,
      label: data['label'] ?? id,
      sensorId: data['sensorId'] ?? '',
      commodityType: data['commodityType'] ?? data['commodity_type'] ?? '',
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'label': label,
      'sensorId': sensorId,
      'commodityType': commodityType,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
    };
  }

  Zone copyWith({
    String? id,
    String? label,
    String? sensorId,
    String? commodityType,
    DateTime? createdAt,
  }) {
    return Zone(
      id: id ?? this.id,
      label: label ?? this.label,
      sensorId: sensorId ?? this.sensorId,
      commodityType: commodityType ?? this.commodityType,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
