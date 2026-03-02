import '../models/alert.dart';
import '../services/notification_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Selected time range for charts (e.g., '1h', '6h', '24h', '7d', '30d')
final timeRangeProvider = StateProvider<String>((ref) => '24h');

/// Currently selected warehouse ID.
/// When changed, subscribes/unsubscribes FCM topics for push notifications.
String? _previousWarehouseId;
final selectedWarehouseIdProvider = StateProvider<String?>((ref) {
  return null;
});

/// Call this helper whenever selectedWarehouseIdProvider changes to manage FCM topics.
void onWarehouseSelected(String? newId) {
  final notifService = NotificationService();
  if (_previousWarehouseId != null) {
    notifService.unsubscribeFromWarehouse(_previousWarehouseId!);
  }
  if (newId != null) {
    notifService.subscribeToWarehouse(newId);
  }
  _previousWarehouseId = newId;
}

/// Bottom navigation index
final bottomNavIndexProvider = StateProvider<int>((ref) => 0);

/// Search query for warehouses
final warehouseSearchProvider = StateProvider<String>((ref) => '');

// ─── Alert Filter Notifier (Riverpod v2+ pattern) ──────────────────────────

class AlertFilterNotifier extends Notifier<AlertFilter> {
  @override
  AlertFilter build() => AlertFilter(severity: 'all', acknowledged: false);

  void setSeverity(String severity) {
    state = state.copyWith(severity: severity);
  }

  void toggleAcknowledged() {
    state = state.copyWith(acknowledged: !state.acknowledged);
  }

  void reset() {
    state = AlertFilter(severity: 'all', acknowledged: false);
  }
}

final alertFilterProvider = NotifierProvider<AlertFilterNotifier, AlertFilter>(
  AlertFilterNotifier.new,
);

// ─── Dashboard View Mode ────────────────────────────────────────────────────

enum DashboardViewMode { grid, list }

final dashboardViewModeProvider = StateProvider<DashboardViewMode>(
  (ref) => DashboardViewMode.grid,
);

// ─── Chart type selection ───────────────────────────────────────────────────

enum ChartType { temperature, humidity, co2, ethylene, multiLine, riskBar }

final selectedChartTypeProvider = StateProvider<ChartType>(
  (ref) => ChartType.temperature,
);
