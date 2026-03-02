import 'package:cloud_firestore/cloud_firestore.dart';

class Reading {
  final String id;
  final String warehouseId;
  final double temperature;
  final double humidity;
  final double? co2Level;
  final double? ethyleneLevel;
  final double? riskScore;
  final String? riskLevel;
  final double? daysToSpoilage;
  final DateTime timestamp;

  Reading({
    required this.id,
    required this.warehouseId,
    required this.temperature,
    required this.humidity,
    this.co2Level,
    this.ethyleneLevel,
    this.riskScore,
    this.riskLevel,
    this.daysToSpoilage,
    required this.timestamp,
  });

  factory Reading.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Reading(
      id: doc.id,
      warehouseId: data['warehouseId'] ?? data['warehouse_id'] ?? '',
      temperature: (data['temperature'] ?? 0).toDouble(),
      humidity: (data['humidity'] ?? 0).toDouble(),
      // Support both field-name conventions from backend
      // M1 writes 'co2' (matches) and 'gasLevel' (camelCase) to Firestore
      co2Level: (data['co2'] ?? data['co2Level'])?.toDouble(),
      ethyleneLevel: (data['gasLevel'] ?? data['gas_level'] ?? data['ethyleneLevel'])?.toDouble(),
      // M1 writes riskScore, riskLevel, daysToSpoilage (camelCase) to every reading
      riskScore: (data['riskScore'] ?? data['risk_score'])?.toDouble(),
      riskLevel: (data['riskLevel'] ?? data['risk_level'])?.toString(),
      daysToSpoilage: (data['daysToSpoilage'] ?? data['days_to_spoilage'])?.toDouble(),
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory Reading.fromMap(Map<String, dynamic> data, {String id = ''}) {
    return Reading(
      id: id,
      warehouseId: data['warehouseId'] ?? data['warehouse_id'] ?? '',
      temperature: (data['temperature'] ?? 0).toDouble(),
      humidity: (data['humidity'] ?? 0).toDouble(),
      co2Level: (data['co2'] ?? data['co2Level'])?.toDouble(),
      ethyleneLevel: (data['gasLevel'] ?? data['gas_level'] ?? data['ethyleneLevel'])?.toDouble(),
      riskScore: (data['riskScore'] ?? data['risk_score'])?.toDouble(),
      riskLevel: (data['riskLevel'] ?? data['risk_level'])?.toString(),
      daysToSpoilage: (data['daysToSpoilage'] ?? data['days_to_spoilage'])?.toDouble(),
      timestamp: data['timestamp'] is Timestamp
          ? (data['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'warehouseId': warehouseId,
      'temperature': temperature,
      'humidity': humidity,
      'co2Level': co2Level,
      'ethyleneLevel': ethyleneLevel,
      'riskScore': riskScore,
      'riskLevel': riskLevel,
      'daysToSpoilage': daysToSpoilage,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }

  Reading copyWith({
    String? id,
    String? warehouseId,
    double? temperature,
    double? humidity,
    double? co2Level,
    double? ethyleneLevel,
    double? riskScore,
    String? riskLevel,
    double? daysToSpoilage,
    DateTime? timestamp,
  }) {
    return Reading(
      id: id ?? this.id,
      warehouseId: warehouseId ?? this.warehouseId,
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      co2Level: co2Level ?? this.co2Level,
      ethyleneLevel: ethyleneLevel ?? this.ethyleneLevel,
      riskScore: riskScore ?? this.riskScore,
      riskLevel: riskLevel ?? this.riskLevel,
      daysToSpoilage: daysToSpoilage ?? this.daysToSpoilage,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
