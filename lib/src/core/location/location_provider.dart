import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:six7_chat/src/core/utils/geohash.dart';

/// Minimum interval between location updates (1 hour).
const Duration _locationUpdateInterval = Duration(hours: 1);

/// Location state for the app.
class LocationState {
  const LocationState({
    this.latitude,
    this.longitude,
    this.geohash,
    this.lastUpdated,
    this.error,
    this.isLoading = false,
    this.permissionGranted = false,
  });

  /// Current latitude.
  final double? latitude;

  /// Current longitude.
  final double? longitude;

  /// Geohash encoded from current location (6 chars).
  final String? geohash;

  /// When the location was last updated.
  final DateTime? lastUpdated;

  /// Last error message, if any.
  final String? error;

  /// Whether location is being fetched.
  final bool isLoading;

  /// Whether location permission has been granted.
  final bool permissionGranted;

  /// Whether we have a valid location.
  bool get hasLocation => latitude != null && longitude != null && geohash != null;

  /// Whether we have location permission.
  /// Returns true if permission was granted or we have a location (implies permission).
  bool get hasPermission => permissionGranted || hasLocation;

  /// Geohash prefix for proximity matching (~100km).
  String? get proximityPrefix => geohash != null 
      ? Geohash.getProximityPrefix(geohash!) 
      : null;

  LocationState copyWith({
    double? latitude,
    double? longitude,
    String? geohash,
    DateTime? lastUpdated,
    String? error,
    bool? isLoading,
    bool? permissionGranted,
  }) {
    return LocationState(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      geohash: geohash ?? this.geohash,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      error: error,
      isLoading: isLoading ?? this.isLoading,
      permissionGranted: permissionGranted ?? this.permissionGranted,
    );
  }
}

/// Provider for location services.
final locationProvider = NotifierProvider<LocationNotifier, LocationState>(
  LocationNotifier.new,
);

/// Notifier for managing location state.
class LocationNotifier extends Notifier<LocationState> {
  @override
  LocationState build() {
    return const LocationState();
  }

  /// Requests location permission from the user.
  Future<bool> requestPermission() async {
    try {
      // Check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        state = state.copyWith(
          error: 'Location services are disabled',
          isLoading: false,
        );
        return false;
      }

      // Check permission status
      var permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          state = state.copyWith(
            error: 'Location permission denied',
            isLoading: false,
          );
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        state = state.copyWith(
          error: 'Location permission permanently denied. Please enable in settings.',
          isLoading: false,
          permissionGranted: false,
        );
        return false;
      }

      state = state.copyWith(permissionGranted: true, error: null);
      return true;
    } catch (e) {
      debugPrint('[Location] Permission request failed: $e');
      state = state.copyWith(
        error: 'Failed to request permission: $e',
        isLoading: false,
      );
      return false;
    }
  }

  /// Fetches the current location and updates the geohash.
  /// Returns true if successful.
  Future<bool> updateLocation() async {
    // Check if we recently updated
    if (state.lastUpdated != null) {
      final elapsed = DateTime.now().difference(state.lastUpdated!);
      if (elapsed < _locationUpdateInterval && state.hasLocation) {
        debugPrint('[Location] Using cached location (${elapsed.inMinutes}m old)');
        return true;
      }
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      // Request permission first
      final hasPermission = await requestPermission();
      if (!hasPermission) {
        return false;
      }

      // Get current position with low accuracy (saves battery, ~100m is fine for geohash)
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 30),
        ),
      );

      // Encode to geohash (6 chars for ~1km precision, but we only use 3 for matching)
      final hash = Geohash.encode(
        position.latitude,
        position.longitude,
        precision: 6,
      );

      state = LocationState(
        latitude: position.latitude,
        longitude: position.longitude,
        geohash: hash,
        lastUpdated: DateTime.now(),
        isLoading: false,
      );

      debugPrint('[Location] Updated: ${position.latitude}, ${position.longitude} -> $hash');
      return true;
    } catch (e) {
      debugPrint('[Location] Failed to get location: $e');
      state = state.copyWith(
        error: 'Failed to get location: $e',
        isLoading: false,
      );
      return false;
    }
  }

  /// Clears the current location (e.g., when disabling discovery).
  void clearLocation() {
    state = const LocationState();
    debugPrint('[Location] Cleared');
  }

  /// Checks if another geohash is within proximity (~100km).
  bool isWithinProximity(String? otherGeohash) {
    if (state.geohash == null || otherGeohash == null) {
      return false;
    }
    return Geohash.isWithinProximity(state.geohash!, otherGeohash);
  }
}
