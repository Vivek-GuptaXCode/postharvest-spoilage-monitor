import 'dart:async';
import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
import 'package:flutter/material.dart';
import '../screens/charts_screen.dart';
import '../screens/alerts_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/camera_feed_screen.dart';
import '../screens/warehouse_detail_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A [ChangeNotifier] that fires whenever Firebase Auth state changes.
/// Used as GoRouter's refreshListenable so the router re-evaluates its
/// redirect without being fully recreated.
class _AuthChangeNotifier extends ChangeNotifier {
  late final StreamSubscription<User?> _sub;

  _AuthChangeNotifier() {
    _sub = FirebaseAuth.instance.authStateChanges().listen((_) {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

/// GoRouter provider with auth-based route guarding.
/// Uses refreshListenable so the router is NOT recreated on auth changes —
/// only the redirect is re-evaluated, preserving navigation state.
final routerProvider = Provider<GoRouter>((ref) {
  final authNotifier = _AuthChangeNotifier();
  ref.onDispose(authNotifier.dispose);

  return GoRouter(
    debugLogDiagnostics: true,
    refreshListenable: authNotifier,
    redirect: (context, state) {
      final isLoggedIn = FirebaseAuth.instance.currentUser != null;
      final isLoginRoute = state.matchedLocation == '/login';

      // Not logged in and not on login page → redirect to login
      if (!isLoggedIn && !isLoginRoute) return '/login';
      // Logged in but on login page → redirect to home
      if (isLoggedIn && isLoginRoute) return '/';
      // Otherwise, no redirect needed
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/warehouse/:id',
        builder: (context, state) {
          final warehouseId = state.pathParameters['id']!;
          return WarehouseDetailScreen(warehouseId: warehouseId);
        },
      ),
      GoRoute(
        path: '/charts',
        builder: (context, state) => const ChartsScreen(),
      ),
      GoRoute(
        path: '/alerts',
        builder: (context, state) => const AlertsScreen(),
      ),
      GoRoute(
        path: '/camera',
        builder: (context, state) => const CameraFeedScreen(),
      ),
    ],
    errorBuilder:
        (context, state) => Scaffold(
          body: Center(child: Text('Page not found: ${state.matchedLocation}')),
        ),
  );
});
