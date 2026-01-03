import 'dart:math';

/// Geohash encoding/decoding utilities for location-based filtering.
///
/// Geohash precision reference:
/// - 1 char: ~5,000km × 5,000km
/// - 2 chars: ~1,250km × 625km
/// - 3 chars: ~156km × 156km
/// - 4 chars: ~40km × 20km
/// - 5 chars: ~5km × 5km
/// - 6 chars: ~1.2km × 0.6km
///
/// For ~100km matching, we compare first 3 characters.
class Geohash {
  Geohash._();

  static const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
  static const List<int> _bits = [16, 8, 4, 2, 1];

  /// Number of characters to compare for ~100km proximity.
  /// 3 chars ≈ 156km × 156km cell
  static const int proximityPrecision = 3;

  /// Default precision for encoding (6 chars ≈ 1.2km).
  static const int defaultPrecision = 6;

  /// Encodes latitude and longitude to a geohash string.
  ///
  /// [latitude] must be in range [-90, 90].
  /// [longitude] must be in range [-180, 180].
  /// [precision] is the number of characters in the result (default 6).
  static String encode(double latitude, double longitude, {int precision = defaultPrecision}) {
    // Validate inputs
    if (latitude < -90 || latitude > 90) {
      throw ArgumentError('Latitude must be between -90 and 90');
    }
    if (longitude < -180 || longitude > 180) {
      throw ArgumentError('Longitude must be between -180 and 180');
    }
    if (precision < 1 || precision > 12) {
      throw ArgumentError('Precision must be between 1 and 12');
    }

    double latMin = -90.0;
    double latMax = 90.0;
    double lngMin = -180.0;
    double lngMax = 180.0;

    final buffer = StringBuffer();
    bool isLng = true;
    int bit = 0;
    int ch = 0;

    while (buffer.length < precision) {
      if (isLng) {
        final mid = (lngMin + lngMax) / 2;
        if (longitude >= mid) {
          ch |= _bits[bit];
          lngMin = mid;
        } else {
          lngMax = mid;
        }
      } else {
        final mid = (latMin + latMax) / 2;
        if (latitude >= mid) {
          ch |= _bits[bit];
          latMin = mid;
        } else {
          latMax = mid;
        }
      }

      isLng = !isLng;
      bit++;

      if (bit == 5) {
        buffer.write(_base32[ch]);
        bit = 0;
        ch = 0;
      }
    }

    return buffer.toString();
  }

  /// Decodes a geohash string to latitude and longitude.
  ///
  /// Returns a [GeohashLocation] with the center point and bounds.
  static GeohashLocation decode(String geohash) {
    if (geohash.isEmpty) {
      throw ArgumentError('Geohash cannot be empty');
    }

    double latMin = -90.0;
    double latMax = 90.0;
    double lngMin = -180.0;
    double lngMax = 180.0;

    bool isLng = true;

    for (final char in geohash.toLowerCase().split('')) {
      final idx = _base32.indexOf(char);
      if (idx == -1) {
        throw ArgumentError('Invalid geohash character: $char');
      }

      for (final mask in _bits) {
        if (isLng) {
          final mid = (lngMin + lngMax) / 2;
          if ((idx & mask) != 0) {
            lngMin = mid;
          } else {
            lngMax = mid;
          }
        } else {
          final mid = (latMin + latMax) / 2;
          if ((idx & mask) != 0) {
            latMin = mid;
          } else {
            latMax = mid;
          }
        }
        isLng = !isLng;
      }
    }

    return GeohashLocation(
      latitude: (latMin + latMax) / 2,
      longitude: (lngMin + lngMax) / 2,
      latitudeError: (latMax - latMin) / 2,
      longitudeError: (lngMax - lngMin) / 2,
    );
  }

  /// Checks if two geohashes are within proximity of each other.
  ///
  /// Compares the first [proximityPrecision] characters (default 3 for ~100km).
  /// Returns true if both geohashes share the same prefix.
  static bool isWithinProximity(String geohash1, String geohash2, {int? precision}) {
    final p = precision ?? proximityPrecision;
    if (geohash1.length < p || geohash2.length < p) {
      return false;
    }
    return geohash1.substring(0, p).toLowerCase() == 
           geohash2.substring(0, p).toLowerCase();
  }

  /// Gets the neighboring geohashes for a given geohash.
  ///
  /// This is useful for matching users near cell boundaries.
  static List<String> getNeighbors(String geohash) {
    if (geohash.isEmpty) return [];

    final decoded = decode(geohash);
    final precision = geohash.length;

    // Calculate cell size
    final latError = decoded.latitudeError * 2;
    final lngError = decoded.longitudeError * 2;

    final neighbors = <String>[];
    
    // 8 directions: N, NE, E, SE, S, SW, W, NW
    final offsets = [
      [1, 0],   // N
      [1, 1],   // NE
      [0, 1],   // E
      [-1, 1],  // SE
      [-1, 0],  // S
      [-1, -1], // SW
      [0, -1],  // W
      [1, -1],  // NW
    ];

    for (final offset in offsets) {
      final newLat = decoded.latitude + (offset[0] * latError);
      final newLng = decoded.longitude + (offset[1] * lngError);

      // Check bounds
      if (newLat >= -90 && newLat <= 90 && newLng >= -180 && newLng <= 180) {
        neighbors.add(encode(newLat, newLng, precision: precision));
      }
    }

    return neighbors;
  }

  /// Gets the proximity prefix for matching (~100km).
  static String getProximityPrefix(String geohash) {
    if (geohash.length < proximityPrecision) return geohash;
    return geohash.substring(0, proximityPrecision);
  }

  /// Calculates approximate distance between two coordinates in kilometers.
  static double distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusKm = 6371.0;
    
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    
    final a = sin(dLat / 2) * sin(dLat / 2) +
              cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
              sin(dLng / 2) * sin(dLng / 2);
    
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return earthRadiusKm * c;
  }

  static double _toRadians(double degrees) => degrees * pi / 180;
}

/// Represents a decoded geohash location with center and error bounds.
class GeohashLocation {
  const GeohashLocation({
    required this.latitude,
    required this.longitude,
    required this.latitudeError,
    required this.longitudeError,
  });

  final double latitude;
  final double longitude;
  final double latitudeError;
  final double longitudeError;

  @override
  String toString() => 'GeohashLocation($latitude, $longitude ±$latitudeError, ±$longitudeError)';
}
