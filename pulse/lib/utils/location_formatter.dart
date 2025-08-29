import 'package:google_maps_webservice/geocoding.dart';
import 'package:geocoding/geocoding.dart';

class LocationFormatter {
  /// Formats location from latitude and longitude coordinates
  static String formatLocation({
    double? latitude,
    double? longitude,
    String? address,
  }) {
    // If address is provided, use it directly
    if (address != null && address.isNotEmpty) {
      return address;
    }

    // If we have coordinates, format them
    if (latitude != null && longitude != null) {
      return 'Location: ${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
    }

    return 'Location not specified';
  }

  /// Formats location from a Pulse object or similar structure
  static String formatLocationFromPulse({
    required double? latitude,
    required double? longitude,
    String? customAddress,
  }) {
    return formatLocation(
      latitude: latitude,
      longitude: longitude,
      address: customAddress,
    );
  }

  /// Checks if location has coordinates
  static bool hasCoordinates({
    double? latitude,
    double? longitude,
  }) {
    return latitude != null && longitude != null;
  }

  /// Gets short address representation
  static String getShortAddress({
    double? latitude,
    double? longitude,
    String? address,
  }) {
    if (address != null && address.isNotEmpty) {
      // Try to extract city/area from full address
      final parts = address.split(',');
      if (parts.length >= 2) {
        return parts[0].trim(); // Return first part (street address or area)
      }
      return address;
    }

    if (latitude != null && longitude != null) {
      return 'Map location';
    }

    return 'Location TBD';
  }

  /// Legacy method for backward compatibility with string locations
  @Deprecated('Use formatLocation with latitude/longitude parameters instead')
  static String formatLocationString(String? location) {
    if (location == null || location.isEmpty) {
      return 'Location not specified';
    }

    // Check if location is coordinates (format: "lat,lng")
    final coordinateRegex = RegExp(r'^-?\d+\.?\d*,-?\d+\.?\d*$');
    if (coordinateRegex.hasMatch(location)) {
      final parts = location.split(',');
      final lat = double.tryParse(parts[0])?.toStringAsFixed(4) ?? parts[0];
      final lng = double.tryParse(parts[1])?.toStringAsFixed(4) ?? parts[1];
      return 'Location: $lat, $lng';
    }

    return location;
  }

  /// Legacy method for backward compatibility
  @Deprecated('Use hasCoordinates with latitude/longitude parameters instead')
  static bool isCoordinates(String location) {
    final coordinateRegex = RegExp(r'^-?\d+\.?\d*,-?\d+\.?\d*$');
    return coordinateRegex.hasMatch(location);
  }

  /// Gets address from coordinates using reverse geocoding
  static Future<String?> getAddressFromCoordinates({
    required double latitude,
    required double longitude,
  }) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      );

      if (placemarks.isNotEmpty) {
        final placemark = placemarks[0];
        final addressParts = [
          if (placemark.street != null && placemark.street!.isNotEmpty)
            placemark.street,
          if (placemark.locality != null && placemark.locality!.isNotEmpty)
            placemark.locality,
          if (placemark.administrativeArea != null &&
              placemark.administrativeArea!.isNotEmpty)
            placemark.administrativeArea,
        ].where((part) => part != null).join(', ');

        return addressParts.isNotEmpty ? addressParts : null;
      }
      return null;
    } catch (e) {
      // Don't spam the console with geocoding errors
      // This is common for coordinates in remote/ocean areas
      // print('Error getting address from coordinates: $e');
      return null;
    }
  }

  /// Creates a coordinate string from latitude and longitude
  static String coordinatesToString({
    required double latitude,
    required double longitude,
  }) {
    return '$latitude,$longitude';
  }

  /// Parses coordinate string into latitude and longitude
  static Map<String, double>? parseCoordinates(String coordinates) {
    final parts = coordinates.split(',');
    if (parts.length != 2) return null;

    final lat = double.tryParse(parts[0]);
    final lng = double.tryParse(parts[1]);

    if (lat == null || lng == null) return null;

    return {
      'latitude': lat,
      'longitude': lng,
    };
  }
}
