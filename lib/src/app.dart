import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/core/notifications/notification_listener.dart';
import 'package:six7_chat/src/core/router/app_router.dart';
import 'package:six7_chat/src/core/theme/app_theme.dart';

class Six7App extends ConsumerWidget {
  const Six7App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    
    // Initialize notification listener (starts listening for incoming messages)
    // This provider handles its own initialization and cleanup
    ref.watch(notificationListenerProvider);

    return MaterialApp.router(
      title: 'Six7',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
