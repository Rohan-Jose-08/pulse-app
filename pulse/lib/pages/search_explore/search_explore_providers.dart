import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../backend/api_service.dart';

// Data models mapped from backend payloads
class ExploreUser {
  final String id;
  final String username;
  final String fullName;
  final String avatarUrl;

  const ExploreUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.avatarUrl,
  });

  factory ExploreUser.fromMap(Map<String, dynamic> map) {
    return ExploreUser(
      id: (map['id'] ?? map['uid'] ?? '').toString(),
      username: (map['username'] ?? map['displayName'] ?? '').toString(),
      fullName: (map['name'] ?? map['displayName'] ?? map['username'] ?? '')
          .toString(),
      avatarUrl: (map['profileImageUrl'] ?? map['photoUrl'] ?? '').toString(),
    );
  }
}

class ExplorePulse {
  final String id;
  final String title;
  final String hostUsername;
  final String authorId;
  final DateTime? time;
  final String
      location; // human readable (from Location.name/city/country fallback)
  final String imageUrl;
  final double? latitude;
  final double? longitude;
  final double? distanceKm;
  final DateTime? activeFrom;
  final DateTime? activeUntil;

  const ExplorePulse({
    required this.id,
    required this.title,
    required this.hostUsername,
    required this.authorId,
    required this.time,
    required this.location,
    required this.imageUrl,
    this.latitude,
    this.longitude,
    this.distanceKm,
    this.activeFrom,
    this.activeUntil,
  });

  factory ExplorePulse.fromMap(Map<String, dynamic> map) {
    DateTime? parsedTime;
    final rawTime = map['eventTime'] ?? map['time'];
    if (rawTime is String) {
      parsedTime = DateTime.tryParse(rawTime);
    }
    double? parseDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    // Structured location object (if provided as nested)
    final locObj = map['location'];
    String humanLocation = '';
    double? latVal = parseDouble(map['latitude'] ?? map['lat']);
    double? lngVal = parseDouble(map['longitude'] ?? map['lng']);
    if (locObj is Map) {
      latVal = parseDouble(locObj['latitude']) ?? latVal;
      lngVal = parseDouble(locObj['longitude']) ?? lngVal;
      final pieces = [
        (locObj['name'] ?? ''),
        (locObj['city'] ?? ''),
        (locObj['country'] ?? ''),
      ]
          .map((e) => (e ?? '').toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (pieces.isNotEmpty) humanLocation = pieces.join(', ');
    }
    if (humanLocation.isEmpty) {
      final raw = (map['location'] ?? '').toString();
      if (raw.isNotEmpty) humanLocation = raw; // legacy string
    }
    if (humanLocation.isEmpty && latVal != null && lngVal != null) {
      humanLocation =
          '${latVal.toStringAsFixed(4)}, ${lngVal.toStringAsFixed(4)}';
    }

    // Parse active window dates
    DateTime? activeFromVal;
    DateTime? activeUntilVal;
    final rawActiveFrom = map['activeFrom'];
    final rawActiveUntil = map['activeUntil'];
    if (rawActiveFrom is String) {
      activeFromVal = DateTime.tryParse(rawActiveFrom);
    }
    if (rawActiveUntil is String) {
      activeUntilVal = DateTime.tryParse(rawActiveUntil);
    }

    return ExplorePulse(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? 'Untitled').toString(),
      hostUsername: (map['hostUsername'] ??
              map['author']?['username'] ??
              map['author']?['displayName'] ??
              '')
          .toString(),
      authorId: (map['author']?['id'] ?? map['authorId'] ?? '').toString(),
      time: parsedTime,
      location: humanLocation,
      imageUrl: (map['imageUrl'] ?? '').toString(),
      latitude: latVal,
      longitude: lngVal,
      distanceKm: parseDouble(map['distanceKm']),
      activeFrom: activeFromVal,
      activeUntil: activeUntilVal,
    );
  }
}

// Search query state
final searchQueryProvider = StateProvider<String>((ref) => '');

// Debounced query for suggestions
class DebouncedQuery extends StateNotifier<String> {
  DebouncedQuery(this.ref) : super('');
  final Ref ref;
  Timer? _timer;

  void set(String value, {Duration delay = const Duration(milliseconds: 250)}) {
    _timer?.cancel();
    _timer = Timer(delay, () => state = value);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final debouncedQueryProvider =
    StateNotifierProvider<DebouncedQuery, String>((ref) {
  return DebouncedQuery(ref);
});

// Filtered suggestions for users and pulses
final userSuggestionsProvider = FutureProvider<List<ExploreUser>>((ref) async {
  final query = ref.watch(debouncedQueryProvider).trim();
  if (query.isEmpty) return const [];
  final resp = await ApiService.instance.searchUsers(query);
  return (resp ?? const []).map((e) => ExploreUser.fromMap(e)).take(5).toList();
});

final pulseSuggestionsProvider =
    FutureProvider<List<ExplorePulse>>((ref) async {
  final query = ref.watch(debouncedQueryProvider).trim();
  if (query.isEmpty) return const [];
  final resp = await ApiService.instance.searchPulses(query);
  return (resp ?? const [])
      .map((e) => ExplorePulse.fromMap(e))
      .take(5)
      .toList();
});

// Full search results (users then pulses)
final userResultsProvider = FutureProvider<List<ExploreUser>>((ref) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) return const [];
  final resp = await ApiService.instance.searchUsers(query);
  return (resp ?? const []).map((e) => ExploreUser.fromMap(e)).toList();
});

final pulseResultsProvider = FutureProvider<List<ExplorePulse>>((ref) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) return const [];
  final resp = await ApiService.instance.searchPulses(query);
  return (resp ?? const []).map((e) => ExplorePulse.fromMap(e)).toList();
});

// Explore grid with simple pagination over mock pulses
class ExplorePagination extends StateNotifier<List<ExplorePulse>> {
  ExplorePagination(this.ref) : super([]) {
    _init();
  }

  final Ref ref;
  List<ExplorePulse> _source = const [];
  static const int _pageSize = 20;
  int _page = 0;
  bool _isLoading = false;
  bool _hasMore = true;
  bool _initialized = false;

  bool get hasMore => _hasMore;
  bool get isLoading => _isLoading || !_initialized;

  Future<void> _init() async {
    await _fetchSource();
    await loadMore();
    _initialized = true;
  }

  Future<void> _fetchSource() async {
    final resp = await ApiService.instance.getPulses();
    _source = (resp ?? const []).map((e) => ExplorePulse.fromMap(e)).toList();
  }

  Future<void> loadMore() async {
    if (_isLoading || !_hasMore) return;
    _isLoading = true;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final start = _page * _pageSize;
    final end = start + _pageSize;
    if (start >= _source.length) {
      _hasMore = false;
      _isLoading = false;
      return;
    }
    final next =
        _source.sublist(start, end > _source.length ? _source.length : end);
    state = [...state, ...next];
    _page += 1;
    _isLoading = false;
  }

  Future<void> refresh() async {
    _page = 0;
    _hasMore = true;
    state = [];
    await _fetchSource();
    await loadMore();
  }
}

final explorePaginationProvider =
    StateNotifierProvider<ExplorePagination, List<ExplorePulse>>((ref) {
  return ExplorePagination(ref);
});
