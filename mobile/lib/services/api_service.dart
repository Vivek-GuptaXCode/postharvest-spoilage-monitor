import 'dart:convert';
import 'package:http/http.dart' as http;

/// Custom exception for API errors
class ApiException implements Exception {
  final String message;
  final int statusCode;
  ApiException(this.message, this.statusCode);
  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiService {
  static const String defaultBaseUrl =
      'https://postharvest-api-n6hvbwpdfq-el.a.run.app';

  final String baseUrl;
  final http.Client _client;

  ApiService({String? baseUrl, http.Client? client})
    : baseUrl = baseUrl ?? defaultBaseUrl,
      _client = client ?? http.Client();

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// GET request helper (returns a Map)
  Future<Map<String, dynamic>> _get(String path) async {
    final response = await _client.get(Uri.parse('$baseUrl$path'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw ApiException('GET $path failed', response.statusCode);
  }

  /// GET request helper (returns a List)
  Future<List<dynamic>> _getList(String path) async {
    final response = await _client.get(Uri.parse('$baseUrl$path'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw ApiException('GET $path failed', response.statusCode);
  }

  /// POST request helper
  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _client.post(
      Uri.parse('$baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw ApiException('POST $path failed', response.statusCode);
  }

  // ---------------------------------------------------------------------------
  // Warehouses
  // ---------------------------------------------------------------------------

  /// GET /warehouses — list all warehouses
  Future<List<Map<String, dynamic>>> getWarehouses() async {
    final data = await _getList('/warehouses');
    return data.cast<Map<String, dynamic>>();
  }

  /// GET /warehouse/{id}/summary
  Future<Map<String, dynamic>> getWarehouseSummary(String warehouseId) {
    return _get('/warehouse/$warehouseId/summary');
  }

  // ---------------------------------------------------------------------------
  // Risk & Recommendations
  // ---------------------------------------------------------------------------

  /// GET /warehouse/{id}/risk — risk analysis from ML backend
  Future<Map<String, dynamic>> getRiskAnalysis(String warehouseId) {
    return _get('/warehouse/$warehouseId/risk');
  }

  /// GET /warehouse/{id}/recommendations
  Future<List<String>> getRecommendations(String warehouseId) async {
    final data = await _get('/warehouse/$warehouseId/recommendations');
    return List<String>.from(data['recommendations'] ?? []);
  }

  // ---------------------------------------------------------------------------
  // Alerts
  // ---------------------------------------------------------------------------

  /// POST /alerts/{wId}/{aId}/acknowledge
  Future<void> acknowledgeAlert(String warehouseId, String alertId) async {
    await _post('/alerts/$warehouseId/$alertId/acknowledge', {
      'acknowledged': true,
    });
  }

  // ---------------------------------------------------------------------------
  // Health Check
  // ---------------------------------------------------------------------------

  /// GET /health — verify backend is reachable
  Future<Map<String, dynamic>> healthCheck() {
    return _get('/health');
  }

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------

  /// GET /warehouse/{id}/export?hours=N — CSV download of readings
  Future<String> exportReadingsCsv(String warehouseId, {int hours = 24}) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/warehouse/$warehouseId/export?hours=$hours'),
    );
    if (response.statusCode == 200) {
      return response.body; // raw CSV string
    }
    throw ApiException('CSV export failed', response.statusCode);
  }

  // ---------------------------------------------------------------------------
  // Camera
  // ---------------------------------------------------------------------------

  /// Get camera feed URL
  Future<String> getCameraFeedUrl(String warehouseId) async {
    final data = await _get('/warehouse/$warehouseId/camera');
    return data['url'] as String;
  }
}
