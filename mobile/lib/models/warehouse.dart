import 'package:cloud_firestore/cloud_firestore.dart';

class Warehouse {
  final String id;
  final String name;
  final String location;
  final String cropType;
  final double capacity;
  final int zoneCount;
  final List<String> zones;
  final DateTime? createdAt;

  Warehouse({
    required this.id,
    required this.name,
    required this.location,
    required this.cropType,
    required this.capacity,
    this.zoneCount = 0,
    this.zones = const [],
    this.createdAt,
  });

  factory Warehouse.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // M1 writes location as a Firestore GeoPoint — convert to readable string
    String locationStr = '';
    final loc = data['location'];
    if (loc is GeoPoint) {
      locationStr = '${loc.latitude.toStringAsFixed(4)}° N, ${loc.longitude.toStringAsFixed(4)}° E';
    } else if (loc is Map) {
      locationStr = '${loc['latitude'] ?? 0}° N, ${loc['longitude'] ?? 0}° E';
    } else if (loc is String) {
      locationStr = loc;
    }

    return Warehouse(
      id: doc.id,
      name: data['name'] ?? '',
      location: locationStr,
      // M1 writes 'commodityType'; M2 API may use 'cropType'
      cropType: data['cropType'] ?? data['commodityType'] ?? '',
      capacity: (data['capacity'] ?? 0).toDouble(),
      zoneCount: (data['zoneCount'] ?? 0).toInt(),
      zones: List<String>.from(data['zones'] ?? []),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Create a Warehouse from a plain JSON map (REST API)
  factory Warehouse.fromJson(Map<String, dynamic> json) {
    return Warehouse(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      location: json['location'] as String? ?? '',
      cropType:
          json['cropType'] as String? ?? json['commodityType'] as String? ?? '',
      capacity: (json['capacity'] as num?)?.toDouble() ?? 0,
      zoneCount: (json['zoneCount'] as num?)?.toInt() ?? 0,
      zones: List<String>.from(json['zones'] ?? []),
      createdAt:
          json['createdAt'] != null
              ? DateTime.tryParse(json['createdAt'].toString())
              : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'location': location,
      'cropType': cropType,
      'capacity': capacity,
      'zoneCount': zoneCount,
      'zones': zones,
      'createdAt':
          createdAt != null
              ? Timestamp.fromDate(createdAt!)
              : FieldValue.serverTimestamp(),
    };
  }

  /// Convert to a plain JSON map (REST API)
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'location': location,
    'cropType': cropType,
    'capacity': capacity,
    'zoneCount': zoneCount,
    'zones': zones,
    'createdAt': createdAt?.toIso8601String(),
  };

  Warehouse copyWith({
    String? id,
    String? name,
    String? location,
    String? cropType,
    double? capacity,
    int? zoneCount,
    List<String>? zones,
    DateTime? createdAt,
  }) {
    return Warehouse(
      id: id ?? this.id,
      name: name ?? this.name,
      location: location ?? this.location,
      cropType: cropType ?? this.cropType,
      capacity: capacity ?? this.capacity,
      zoneCount: zoneCount ?? this.zoneCount,
      zones: zones ?? this.zones,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
