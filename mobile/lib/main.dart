import 'theme/app_theme.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'providers/router_provider.dart';
import 'services/notification_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// TOP-LEVEL background message handler (must be outside any class).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Background message: ${message.messageId}');
  // System automatically shows notification tray banner for background messages
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Register background handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize local notifications + FCM foreground listener
  await NotificationService().initialize();

  // Handle notification tap when app was terminated
  FirebaseMessaging.instance.getInitialMessage().then((message) {
    if (message != null) {
      // Navigate to specific screen based on message data
      print(
        'App opened from terminated state via notification: ${message.messageId}',
      );
    }
  });

  // Handle notification tap when app is in background
  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    // Navigate to relevant screen
    print('App opened from background via notification: ${message.messageId}');
  });

  runApp(const ProviderScope(child: PostHarvestApp()));
}

class PostHarvestApp extends ConsumerWidget {
  const PostHarvestApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'PostHarvest Monitor',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      darkTheme: buildAppTheme(),
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
