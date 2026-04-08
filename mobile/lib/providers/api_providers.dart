import '../services/api_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Base URL for the backend API
const String baseUrl = 'https://postharvest-api-n6hvbwpdfq-el.a.run.app';

/// Provides the API service instance
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService(baseUrl: baseUrl);
});

/// FutureProvider — list all warehouses from the REST API
final warehousesApiProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final apiService = ref.read(apiServiceProvider);
  return apiService.getWarehouses();
});

/// FutureProvider — One-time API call for warehouse summary
final warehouseSummaryProvider =
    FutureProvider.family<Map<String, dynamic>, String>((
      ref,
      warehouseId,
    ) async {
      final apiService = ref.read(apiServiceProvider);
      return apiService.getWarehouseSummary(warehouseId);
    });

/// FutureProvider — Risk analysis from ML backend
final riskAnalysisProvider =
    FutureProvider.family<Map<String, dynamic>, String>((
      ref,
      warehouseId,
    ) async {
      final apiService = ref.read(apiServiceProvider);
      return apiService.getRiskAnalysis(warehouseId);
    });

/// FutureProvider — Recommendations from backend
final recommendationsProvider = FutureProvider.family<List<String>, String>((
  ref,
  warehouseId,
) async {
  final apiService = ref.read(apiServiceProvider);
  return apiService.getRecommendations(warehouseId);
});

/// FutureProvider — Health check
final healthCheckProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final apiService = ref.read(apiServiceProvider);
  return apiService.healthCheck();
});

/// FutureProvider — CSV export of readings
/// Parameter: ({String warehouseId, int hours})
final exportCsvProvider = FutureProvider.family<
  String,
  ({String warehouseId, int hours})
>((ref, params) async {
  final apiService = ref.read(apiServiceProvider);
  return apiService.exportReadingsCsv(params.warehouseId, hours: params.hours);
});

/// FutureProvider — list zones for a warehouse from the REST API
final zonesApiProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      warehouseId,
    ) async {
      final apiService = ref.read(apiServiceProvider);
      return apiService.getZones(warehouseId);
    });

/// FutureProvider — zone-level summary from the REST API
final zoneSummaryApiProvider = FutureProvider.family<
  Map<String, dynamic>,
  ({String warehouseId, String zoneId})
>((ref, params) async {
  final apiService = ref.read(apiServiceProvider);
  return apiService.getZoneSummary(params.warehouseId, params.zoneId);
});
