// Lock Screen Widget
//
// Displayed when the app is locked and requires authentication.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:six7_chat/src/core/auth/lock_service.dart';
import 'package:six7_chat/src/features/settings/domain/providers/settings_provider.dart';

/// Lock screen displayed when app requires authentication.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key, required this.child});

  /// The child widget to show when unlocked.
  final Widget child;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen>
    with WidgetsBindingObserver {
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lockService = ref.read(lockServiceProvider);

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        lockService.onAppPaused();
      case AppLifecycleState.resumed:
        lockService.onAppResumed();
        // Auto-trigger auth when returning to app if locked
        final isLocked = ref.read(appLockStateProvider);
        if (isLocked && !_isAuthenticating) {
          _authenticate();
        }
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;

    setState(() => _isAuthenticating = true);

    try {
      final lockService = ref.read(lockServiceProvider);
      final success = await lockService.unlock();

      if (!success && mounted) {
        // Show error feedback
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Authentication failed. Please try again.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAuthenticating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLocked = ref.watch(appLockStateProvider);
    final settings = ref.watch(accountSettingsProvider);

    // If neither lock option is enabled, just show child
    if (!settings.screenLock && !settings.fingerprintLock) {
      return widget.child;
    }

    // If not locked, show child
    if (!isLocked) {
      return widget.child;
    }

    // Show lock screen
    return _buildLockScreen(context, settings);
  }

  Widget _buildLockScreen(BuildContext context, AccountSettings settings) {
    final theme = Theme.of(context);
    final biometricsAsync = ref.watch(availableBiometricsProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // App icon/logo
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    Icons.lock_outline,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 32),

                // Title
                Text(
                  'Six7 is Locked',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                // Subtitle based on auth method
                Text(
                  settings.fingerprintLock
                      ? 'Use biometrics to unlock'
                      : 'Tap to unlock',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 48),

                // Unlock button
                if (_isAuthenticating)
                  const CircularProgressIndicator()
                else
                  biometricsAsync.when(
                    data: (biometrics) => _buildUnlockButton(
                      context,
                      settings,
                      biometrics,
                    ),
                    loading: () => const CircularProgressIndicator(),
                    error: (_, __) => _buildUnlockButton(context, settings, []),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnlockButton(
    BuildContext context,
    AccountSettings settings,
    List<BiometricType> biometrics,
  ) {
    final theme = Theme.of(context);

    // Determine icon based on available biometrics
    IconData icon = Icons.lock_open;
    String label = 'Unlock';

    if (settings.fingerprintLock && biometrics.isNotEmpty) {
      if (biometrics.contains(BiometricType.face)) {
        icon = Icons.face;
        label = 'Unlock with Face ID';
      } else if (biometrics.contains(BiometricType.fingerprint)) {
        icon = Icons.fingerprint;
        label = 'Unlock with Fingerprint';
      } else {
        icon = Icons.security;
        label = 'Unlock with Biometrics';
      }
    }

    return Column(
      children: [
        // Large icon button
        InkWell(
          onTap: _authenticate,
          borderRadius: BorderRadius.circular(48),
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(48),
            ),
            child: Icon(
              icon,
              size: 48,
              color: theme.colorScheme.onPrimary,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Label
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
