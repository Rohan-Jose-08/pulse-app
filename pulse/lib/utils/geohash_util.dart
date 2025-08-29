/// Simple Geohash encode/decode helpers (decode only needed here)
/// Minimal implementation to derive approximate lat/lng center from a geohash
/// so we can run nearby queries when only a geohash is stored.
class GeohashUtil {
  static const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
  static const _bits = [16, 8, 4, 2, 1];

  /// Decode geohash returning (latitude, longitude) center point.
  /// Returns null if hash invalid.
  static ({double lat, double lng})? decode(String? hash) {
    if (hash == null || hash.isEmpty) return null;
    double minLat = -90, maxLat = 90;
    double minLng = -180, maxLng = 180;
    bool even = true;

    for (final c in hash.toLowerCase().split('')) {
      final cd = _base32.indexOf(c);
      if (cd == -1) return null; // invalid char
      for (final mask in _bits) {
        if (even) {
          // longitude
          final mid = (minLng + maxLng) / 2;
          if ((cd & mask) != 0) {
            minLng = mid;
          } else {
            maxLng = mid;
          }
        } else {
          // latitude
          final mid = (minLat + maxLat) / 2;
          if ((cd & mask) != 0) {
            minLat = mid;
          } else {
            maxLat = mid;
          }
        }
        even = !even;
      }
    }
    final lat = (minLat + maxLat) / 2;
    final lng = (minLng + maxLng) / 2;
    return (lat: lat, lng: lng);
  }
}
