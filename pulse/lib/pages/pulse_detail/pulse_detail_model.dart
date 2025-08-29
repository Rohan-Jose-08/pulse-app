import '/flutter_flow/flutter_flow_util.dart';
import 'pulse_detail_page.dart' show PulseDetailPage;
import 'package:flutter/material.dart';

class PulseDetailModel extends FlutterFlowModel<PulseDetailPage> {
  ///  State fields for stateful widgets in this page.

  // Loading states
  bool isLoadingDetails = true;
  bool isLoadingParticipants = false;
  bool isJoining = false;
  bool isLeaving = false;

  // Pulse data
  Map<String, dynamic>? pulseData;
  List<Map<String, dynamic>> participants = [];

  // Error state
  String? errorMessage;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {}

  // Helper methods
  void setLoading(bool loading) {
    isLoadingDetails = loading;
  }

  void setJoinLoading(bool loading) {
    isJoining = loading;
  }

  void setLeaveLoading(bool loading) {
    isLeaving = loading;
  }

  void setPulseData(Map<String, dynamic>? data) {
    pulseData = data;
    if (data != null && data['allParticipants'] != null) {
      participants = List<Map<String, dynamic>>.from(data['allParticipants']);
    }
  }

  void setError(String? error) {
    errorMessage = error;
  }

  // Getters for convenience
  String get pulseId => pulseData?['id'] ?? '';
  String get title => pulseData?['title'] ?? 'Unknown Pulse';
  String get description => pulseData?['description'] ?? '';
  String get location {
    final raw = pulseData?['location'];
    return raw is String ? raw : '';
  }

  Map<String, dynamic>? get locationObject =>
      pulseData?['location'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(pulseData!['location'])
          : null;
  double? get latitude => locationObject?['latitude'] is num
      ? (locationObject!['latitude'] as num).toDouble()
      : null;
  double? get longitude => locationObject?['longitude'] is num
      ? (locationObject!['longitude'] as num).toDouble()
      : null;
  String get street => locationObject?['street'] is String
      ? (locationObject!['street'] as String)
      : '';
  String get locationLabelDerived {
    // Always prefer structured location name; fall back to city/country; then coordinates
    final loc = locationObject;
    if (loc != null) {
      final name = (loc['name'] ?? '').toString().trim();
      final city = (loc['city'] ?? '').toString().trim();
      final country = (loc['country'] ?? '').toString().trim();
      if (name.isNotEmpty) {
        // Show name plus city OR country if available
        if (city.isNotEmpty) return '$name, $city';
        if (country.isNotEmpty) return '$name, $country';
        return name;
      }
      if (city.isNotEmpty && country.isNotEmpty) return '$city, $country';
      if (city.isNotEmpty) return city;
      if (country.isNotEmpty) return country;
      if (latitude != null && longitude != null) {
        return '${latitude!.toStringAsFixed(3)}, ${longitude!.toStringAsFixed(3)}';
      }
    }
    // Legacy string fallback
    if (location.isNotEmpty) return location;
    return '';
  }

  String get imageUrl => pulseData?['imageUrl'] ?? '';
  bool get isPublic => pulseData?['isPublic'] ?? true;
  bool get canJoin => pulseData?['canJoin'] ?? false;
  bool get isParticipant => pulseData?['isParticipant'] ?? false;
  bool get isAuthor => pulseData?['isAuthor'] ?? false;
  bool get isFullyBooked => pulseData?['isFullyBooked'] ?? false;
  int get totalParticipants => pulseData?['totalParticipants'] ?? 0;
  int? get maxParticipants => pulseData?['maxParticipants'];

  // Active window fields
  DateTime? get activeFrom {
    final v = pulseData?['activeFrom'];
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  DateTime? get activeUntil {
    final v = pulseData?['activeUntil'];
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  bool get isActive => pulseData?['isActive'] == true;
  Duration? get timeUntilStart {
    final from = activeFrom;
    if (from == null) return null;
    final now = DateTime.now();
    if (from.isBefore(now)) return Duration.zero;
    return from.difference(now);
  }

  Duration? get timeUntilEnd {
    final until = activeUntil;
    if (until == null) return null;
    final now = DateTime.now();
    if (until.isBefore(now)) return Duration.zero;
    return until.difference(now);
  }

  DateTime? get eventTime {
    final timeStr = pulseData?['eventTime'];
    if (timeStr is String) {
      return DateTime.tryParse(timeStr);
    }
    return null;
  }

  Map<String, dynamic>? get author {
    return pulseData?['author'];
  }

  List<String> get tags {
    final tagsList = pulseData?['tags'];
    if (tagsList is List) {
      return tagsList.map((e) => e.toString()).toList();
    }
    return [];
  }
}
