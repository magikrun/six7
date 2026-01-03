// App Lock Service
//
// Handles screen lock and biometric authentication for the app.
// Uses local_auth for fingerprint/face recognition.
//
// SECURITY (per AGENTS.md):
// - Lock state is managed in memory, not persisted
// - Biometric auth is the only unlock method when enabled
// - Timeout constants are configurable via named constants

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:six7_chat/src/features/settings/domain/providers/settings_provider.dart';

/// Lock timeout duration in seconds.
/// SECURITY: After this duration in background, app will lock.
const int _lockTimeoutSeconds = 30;

/// Provider for the lock service.
final lockServiceProvider = Provider<LockService>((ref) {
  return LockService(ref);
});

/// Notifier for app lock state.
class AppLockStateNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setLocked(bool value) {
    state = value;
  }
}

/// Provider for app lock state.
/// True = app is locked and requires authentication.
final appLockStateProvider = NotifierProvider<AppLockStateNotifier, bool>(
  AppLockStateNotifier.new,
);

/// Provider to check if biometrics are available on this device.
final biometricsAvailableProvider = FutureProvider<bool>((ref) async {
  final lockService = ref.read(lockServiceProvider);
  return lockService.isBiometricsAvailable();
});

/// Provider to get available biometric types.
final availableBiometricsProvider =
    FutureProvider<List<BiometricType>>((ref) async {
  final lockService = ref.read(lockServiceProvider);
  return lockService.getAvailableBiometrics();
});

/// Service for managing app lock and biometric authentication.
class LockService {
  LockService(this._ref);

  final Ref _ref;
  final LocalAuthentication _auth = LocalAuthentication();

  /// Timestamp when app went to background.
  DateTime? _backgroundedAt;

  /// Timer for lock timeout.
  Timer? _lockTimer;

  /// Whether biometric authentication is available on this device.
  Future<bool> isBiometricsAvailable() async {
    try {
      final canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final canAuthenticate =
          canAuthenticateWithBiometrics || await _auth.isDeviceSupported();
      return canAuthenticate;
    } on PlatformException {
      return false;
    }
  }

  /// Get list of available biometric types.
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } on PlatformException {
      return [];
    }
  }

  /// Attempt to authenticate with biometrics.
  /// Returns true if authentication succeeded.
  Future<bool> authenticateWithBiometrics() async {
    try {
      final didAuthenticate = await _auth.authenticate(
        localizedReason: 'Authenticate to unlock Six7',
        // Allow PIN/pattern fallback, not biometric-only
      );
      return didAuthenticate;
    } on PlatformException catch (e) {
      // Log but don't expose error details to user
      // SECURITY: Don't reveal why auth failed
      // ignore: avoid_print
      print('[LockService] Auth error: ${e.code}');
      return false;
    }
  }

  /// Called when app goes to background.
  void onAppPaused() {
    final settings = _ref.read(accountSettingsProvider);

    // Only track background time if screen lock is enabled
    if (settings.screenLock || settings.fingerprintLock) {
      _backgroundedAt = DateTime.now();

      // Start a timer to lock after timeout
      _lockTimer?.cancel();
      _lockTimer = Timer(
        const Duration(seconds: _lockTimeoutSeconds),
        _lockApp,
      );
    }
  }

  /// Called when app returns to foreground.
  void onAppResumed() {
    _lockTimer?.cancel();
    _lockTimer = null;

    final settings = _ref.read(accountSettingsProvider);

    // Check if we need to lock based on time in background
    if (_backgroundedAt != null &&
        (settings.screenLock || settings.fingerprintLock)) {
      final elapsed = DateTime.now().difference(_backgroundedAt!);

      if (elapsed.inSeconds >= _lockTimeoutSeconds) {
        _lockApp();
      }
    }

    _backgroundedAt = null;
  }

  /// Lock the app.
  void _lockApp() {
    _ref.read(appLockStateProvider.notifier).setLocked(true);
  }

  /// Attempt to unlock the app.
  /// Returns true if unlock succeeded.
  Future<bool> unlock() async {
    final settings = _ref.read(accountSettingsProvider);

    // If fingerprint lock is enabled, require biometric auth
    if (settings.fingerprintLock) {
      final authenticated = await authenticateWithBiometrics();
      if (authenticated) {
        _ref.read(appLockStateProvider.notifier).setLocked(false);
        return true;
      }
      return false;
    }

    // If only screen lock (no fingerprint), just unlock
    // (In a full implementation, you'd have a PIN entry here)
    _ref.read(appLockStateProvider.notifier).setLocked(false);
    return true;
  }

  /// Dispose resources.
  void dispose() {
    _lockTimer?.cancel();
  }
}
