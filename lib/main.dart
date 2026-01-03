import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/app.dart';
import 'package:six7_chat/src/core/storage/storage.dart';
import 'package:six7_chat/src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize storage
  final storageService = StorageService();
  await storageService.initialize();

  // Initialize Rust bridge
  await RustLib.init();

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
