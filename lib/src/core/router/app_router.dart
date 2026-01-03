import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:six7_chat/src/features/auth/presentation/screens/onboarding_screen.dart';
import 'package:six7_chat/src/features/chat/presentation/screens/chat_screen.dart';
import 'package:six7_chat/src/features/groups/presentation/screens/group_chat_screen.dart';
import 'package:six7_chat/src/features/groups/presentation/screens/new_group_screen.dart';
import 'package:six7_chat/src/features/home/presentation/screens/home_screen.dart';
import 'package:six7_chat/src/features/contacts/presentation/screens/contacts_screen.dart';
import 'package:six7_chat/src/features/profile/presentation/screens/profile_screen.dart';
import 'package:six7_chat/src/features/qr/presentation/screens/qr_display_screen.dart';
import 'package:six7_chat/src/features/qr/presentation/screens/qr_scanner_screen.dart';
import 'package:six7_chat/src/features/search/presentation/screens/search_screen.dart';
import 'package:six7_chat/src/features/settings/presentation/screens/account_settings_screen.dart';
import 'package:six7_chat/src/features/settings/presentation/screens/chat_settings_screen.dart';
import 'package:six7_chat/src/features/settings/presentation/screens/help_settings_screen.dart';
import 'package:six7_chat/src/features/settings/presentation/screens/language_settings_screen.dart';
import 'package:six7_chat/src/features/settings/presentation/screens/notification_settings_screen.dart';
import 'package:six7_chat/src/features/settings/presentation/screens/settings_screen.dart';
import 'package:six7_chat/src/features/settings/presentation/screens/storage_settings_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: true,
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
        routes: [
          GoRoute(
            path: 'chat/:peerId',
            name: 'chat',
            builder: (context, state) {
              final peerId = state.pathParameters['peerId']!;
              final peerName = state.uri.queryParameters['name'];
              final autofocus = state.uri.queryParameters['autofocus'] == 'true';
              return ChatScreen(peerId: peerId, peerName: peerName, autofocus: autofocus);
            },
          ),
          GoRoute(
            path: 'group-chat/:groupId',
            name: 'group-chat',
            builder: (context, state) {
              final groupId = state.pathParameters['groupId']!;
              return GroupChatScreen(groupId: groupId);
            },
          ),
          GoRoute(
            path: 'contacts',
            name: 'contacts',
            builder: (context, state) => const ContactsScreen(),
          ),
          GoRoute(
            path: 'settings',
            name: 'settings',
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: 'qr-scanner',
            name: 'qr-scanner',
            builder: (context, state) => const QrScannerScreen(),
          ),
          GoRoute(
            path: 'qr-display',
            name: 'qr-display',
            builder: (context, state) => const QrDisplayScreen(),
          ),
          GoRoute(
            path: 'search',
            name: 'search',
            builder: (context, state) => const SearchScreen(),
          ),
          GoRoute(
            path: 'new-group',
            name: 'new-group',
            builder: (context, state) => const NewGroupScreen(),
            routes: [
              GoRoute(
                path: 'details',
                name: 'new-group-details',
                builder: (context, state) {
                  final selectedContactIds = state.extra as List<String>? ?? [];
                  return GroupDetailsScreen(
                    selectedContactIds: selectedContactIds,
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: 'profile',
            name: 'profile',
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: 'dht-info',
            name: 'dht-info',
            builder: (context, state) => const DhtInfoScreen(),
          ),
          GoRoute(
            path: 'settings/account',
            name: 'settings-account',
            builder: (context, state) => const AccountSettingsScreen(),
          ),
          GoRoute(
            path: 'settings/chats',
            name: 'settings-chats',
            builder: (context, state) => const ChatSettingsScreen(),
          ),
          GoRoute(
            path: 'settings/notifications',
            name: 'settings-notifications',
            builder: (context, state) => const NotificationSettingsScreen(),
          ),
          GoRoute(
            path: 'settings/storage',
            name: 'settings-storage',
            builder: (context, state) => const StorageSettingsScreen(),
          ),
          GoRoute(
            path: 'settings/language',
            name: 'settings-language',
            builder: (context, state) => const LanguageSettingsScreen(),
          ),
          GoRoute(
            path: 'settings/help',
            name: 'settings-help',
            builder: (context, state) => const HelpSettingsScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Page not found: ${state.uri}'),
      ),
    ),
  );
});
