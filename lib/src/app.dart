import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/core/auth/lock_screen.dart';
import 'package:six7_chat/src/core/notifications/notification_listener.dart';
import 'package:six7_chat/src/core/notifications/notification_service.dart';
import 'package:six7_chat/src/core/router/app_router.dart';
import 'package:six7_chat/src/core/theme/app_theme.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/presence_provider.dart';

class Six7App extends ConsumerWidget {
  const Six7App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    
    // Initialize notification listener (starts listening for incoming messages)
    // This provider handles its own initialization and cleanup
    ref.watch(notificationListenerProvider);
    
    // Initialize presence system (publishes heartbeats, tracks contacts' presence)
    // This is read once to trigger the provider's build() which sets up listeners
    ref.watch(presenceProvider);

    // Listen for notification tap events and navigate
    ref.listen(notificationTapStreamProvider, (previous, next) {
      next.whenData((event) {
        if (event.isGroupChat) {
          router.push('/group-chat/${event.targetId}');
        } else {
          final encodedName = event.targetName != null 
              ? Uri.encodeComponent(event.targetName!)
              : 'Unknown';
          router.push('/chat/${event.targetId}?name=$encodedName');
        }
      });
    });

    // Wrap the app with LockScreen for biometric/screen lock support
    return LockScreen(
      child: MaterialApp.router(
        title: 'Six7',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        routerConfig: router,
      ),
    );
  }
}
