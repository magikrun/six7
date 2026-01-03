import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/app.dart';
import 'package:six7_chat/src/core/storage/storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure system UI for edge-to-edge display
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    // Status bar
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    // Navigation bar - transparent to allow content to extend behind
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
  ));
  
  // Enable edge-to-edge mode on Android
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Initialize storage
  final storageService = StorageService();
  await storageService.initialize();

  // NOTE: Rust bridge initialization removed.
  // Korium 0.4.0 uses native UniFFI bindings via platform channels.
  // The native bridge is automatically initialized by the platform.
  
  // NOTE: Notification service is initialized via notificationListenerProvider
  // which is watched in Six7App.

  runApp(
    ProviderScope(
      overrides: [
        // Provide the initialized storage service
        storageServiceProvider.overrideWithValue(storageService),
      ],
      child: const Six7App(),
    ),
  );
}
