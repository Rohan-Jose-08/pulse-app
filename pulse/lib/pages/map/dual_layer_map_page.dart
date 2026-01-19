import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:provider/provider.dart';
import '../../backend/api_service.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import '../../flutter_flow/flutter_flow_util.dart';
import '../../main.dart';
import '../../components/navbar_widget.dart';
import '../pulse_detail/pulse_detail_page.dart';
import '../create_pulse/create_pulse_widget.dart';

/// Data models
class PulseMarker {
  final String id;
  final String title;
  final String? category; // determines icon
  final double lat;
  final double lng;
  final int attendeeCount;
  final DateTime? eventTime;
  final bool isActive;
  PulseMarker({
    required this.id,
    required this.title,
    required this.lat,
    required this.lng,
    required this.attendeeCount,
    this.category,
    this.eventTime,
    this.isActive = false,
  });
}

class UserBubble {
  final String id;
  final String name;
  final String? avatarUrl;
  final double lat;
  final double lng;
  final String? status;
  final bool isActive;
  UserBubble({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.avatarUrl,
    this.status,
    this.isActive = false,
  });
}

/// Simple in-page state (can be migrated to Riverpod later)
class DualLayerMapState extends ChangeNotifier {
  bool loading = false;
  bool showPulses = true;
  bool showPeople = true;
  double radiusKm = 5;
  List<PulseMarker> pulses = [];
  List<UserBubble> users = [];
  gmaps.LatLng? currentCenter;
  Timer? _refreshTimer;

  Future<void> load({required gmaps.LatLng center}) async {
    if (loading) return; // debounce
    loading = true;
    notifyListeners();
    currentCenter = center;
    try {
      final api = ApiService.instance;
      final overview = await api.getMapOverview(
          latitude: center.latitude,
          longitude: center.longitude,
          radiusKm: radiusKm,
          includePulses: true,
          includeUsers: true);
      final pulseList = (overview?['pulses'] as List?) ?? [];
      final userList = (overview?['users'] as List?) ?? [];
      pulses = pulseList.map((p) {
        final loc = p['location'] ?? {};
        return PulseMarker(
          id: (p['id'] ?? '').toString(),
          title: (p['title'] ?? 'Untitled').toString(),
          category: p['category']?.toString(),
          lat: (loc['lat'] ?? 0).toDouble(),
          lng: (loc['lng'] ?? 0).toDouble(),
          attendeeCount: (p['attendeeCount'] ?? 0) as int,
          eventTime:
              p['eventTime'] != null ? DateTime.tryParse(p['eventTime']) : null,
          isActive: p['isActive'] == true,
        );
      }).toList();
      users = userList.map((u) {
        final loc = u['location'] ?? {};
        return UserBubble(
          id: (u['id'] ?? '').toString(),
          name: (u['name'] ?? 'User').toString(),
          avatarUrl: u['avatarUrl'] as String?,
          lat: (loc['lat'] ?? 0).toDouble(),
          lng: (loc['lng'] ?? 0).toDouble(),
          status: u['status'] as String?,
          isActive: u['isActive'] == true,
        );
      }).toList();
    } catch (e) {
      debugPrint('DualLayerMap load error: $e');
    }
    loading = false;
    notifyListeners();
  }

  void startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (currentCenter != null) load(center: currentCenter!);
    });
  }

  void disposeAuto() {
    _refreshTimer?.cancel();
  }

  void setFilters({bool? pulsesLayer, bool? peopleLayer, double? radius}) {
    if (pulsesLayer != null) showPulses = pulsesLayer;
    if (peopleLayer != null) showPeople = peopleLayer;
    if (radius != null) radiusKm = radius;
    notifyListeners();
  }
}

class DualLayerMapPage extends StatefulWidget {
  const DualLayerMapPage({super.key});
  static const String routeName = 'dualLayerMap';
  static const String routePath = '/map';
  @override
  State<DualLayerMapPage> createState() => _DualLayerMapPageState();
}

// Internal cluster model (file scope)
class _PulseCluster {
  static int _counter = 0;
  final int id = _counter++;
  double lat;
  double lng;
  final List<PulseMarker> pulses = [];
  _PulseCluster._({required this.lat, required this.lng});
}

class _HeatPoint {
  final double lat;
  final double lng;
  final double weight;
  _HeatPoint(this.lat, this.lng, {this.weight = 1});
}

class _HeatBucket {
  final int gx;
  final int gy;
  double totalWeight = 0;
  int count = 0;
  _HeatBucket(this.gx, this.gy);
  void add(_HeatPoint p) {
    totalWeight += p.weight;
    count++;
  }
}

class _DualLayerMapPageState extends State<DualLayerMapPage>
    with TickerProviderStateMixin {
  gmaps.GoogleMapController? _controller;
  final DualLayerMapState _state = DualLayerMapState();
  final Set<gmaps.Marker> _markers = {};
  final Set<gmaps.Circle> _circles = {};
  final Set<gmaps.Circle> _heatmapCircles = {};
  late final AnimationController _pulseController;
  late final AnimationController _fabController;
  final Map<String, DateTime> _activeBounces = {}; // markerId -> start time
  static const Duration _bounceDuration = Duration(milliseconds: 650);
  double _currentZoom = 12;
  bool _enableClustering = true;
  Timer? _cameraMoveDebounce;
  bool _showHeatmap = false;
  bool _speedDialOpen = false;
  bool _showLegend = false;
  bool _mapStyleDark = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _isSearching = false;

  // Dark map style
  static const String _darkMapStyle = '''
  [
    {"elementType": "geometry", "stylers": [{"color": "#242f3e"}]},
    {"elementType": "labels.text.fill", "stylers": [{"color": "#746855"}]},
    {"elementType": "labels.text.stroke", "stylers": [{"color": "#242f3e"}]},
    {"featureType": "administrative.locality", "elementType": "labels.text.fill", "stylers": [{"color": "#d59563"}]},
    {"featureType": "poi", "elementType": "labels.text.fill", "stylers": [{"color": "#d59563"}]},
    {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#263c3f"}]},
    {"featureType": "poi.park", "elementType": "labels.text.fill", "stylers": [{"color": "#6b9a76"}]},
    {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#38414e"}]},
    {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#212a37"}]},
    {"featureType": "road", "elementType": "labels.text.fill", "stylers": [{"color": "#9ca5b3"}]},
    {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#746855"}]},
    {"featureType": "road.highway", "elementType": "geometry.stroke", "stylers": [{"color": "#1f2835"}]},
    {"featureType": "road.highway", "elementType": "labels.text.fill", "stylers": [{"color": "#f3d19c"}]},
    {"featureType": "transit", "elementType": "geometry", "stylers": [{"color": "#2f3948"}]},
    {"featureType": "transit.station", "elementType": "labels.text.fill", "stylers": [{"color": "#d59563"}]},
    {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#17263c"}]},
    {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#515c6d"}]},
    {"featureType": "water", "elementType": "labels.text.stroke", "stylers": [{"color": "#17263c"}]}
  ]
  ''';

  @override
  void initState() {
    super.initState();
    _pulseController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..addListener(_updatePulseAnimation)
          ..repeat();
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final loc = await _determineInitialLocation();
      await _state.load(center: loc);
      _state.startAutoRefresh();
      _rebuildMarkers();
    });
    _state.addListener(_onStateChanged);
  }

  Future<gmaps.LatLng> _determineInitialLocation() async {
    return const gmaps.LatLng(40.7128, -74.0060); // TODO: real device location
  }

  void _onStateChanged() => _rebuildMarkers();

  void _rebuildMarkers() {
    final markers = <gmaps.Marker>{};
    if (_state.showPulses) {
      final zoomForDetail = 14.0; // above this show individual pulses
      if (_enableClustering && _currentZoom < zoomForDetail) {
        for (final cluster in _buildPulseClusters()) {
          if (cluster.pulses.length == 1) {
            final p = cluster.pulses.first;
            final markerId = 'pulse_${p.id}';
            final bounceShift = _bounceOffset(markerId, p.lat);
            markers.add(_buildPulseMarker(p, markerId, bounceShift));
          } else {
            final id = 'pulse_cluster_${cluster.id}';
            final hue = cluster.pulses.length >= 10
                ? 0.0
                : cluster.pulses.length >= 5
                    ? 30.0
                    : 50.0;
            markers.add(gmaps.Marker(
                markerId: gmaps.MarkerId(id),
                position: gmaps.LatLng(cluster.lat, cluster.lng),
                infoWindow: gmaps.InfoWindow(
                    title: '${cluster.pulses.length} pulses',
                    snippet: 'Tap to zoom in'),
                onTap: () async {
                  final targetZoom = (_currentZoom + 2).clamp(3, 20).toDouble();
                  await _controller?.animateCamera(
                      gmaps.CameraUpdate.newCameraPosition(gmaps.CameraPosition(
                          target: gmaps.LatLng(cluster.lat, cluster.lng),
                          zoom: targetZoom)));
                },
                icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(hue)));
          }
        }
      } else {
        for (final p in _state.pulses) {
          final markerId = 'pulse_${p.id}';
          final bounceShift = _bounceOffset(markerId, p.lat);
          markers.add(_buildPulseMarker(p, markerId, bounceShift));
        }
      }
    }
    if (_state.showPeople) {
      for (final u in _state.users) {
        final markerId = 'user_${u.id}';
        final bounceShift = _bounceOffset(markerId, u.lat);
        markers.add(gmaps.Marker(
            markerId: gmaps.MarkerId(markerId),
            position: gmaps.LatLng(u.lat + bounceShift, u.lng),
            onTap: () {
              _triggerBounce(markerId);
              Future.delayed(const Duration(milliseconds: 100), () {
                if (mounted) _openUserCard(u);
              });
            },
            icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
                gmaps.BitmapDescriptor.hueAzure)));
      }
    }
    setState(() {
      _markers
        ..clear()
        ..addAll(markers);
      _rebuildCircles();
      if (_showHeatmap) _rebuildHeatmap();
    });
  }

  gmaps.Marker _buildPulseMarker(
          PulseMarker p, String markerId, double bounceShift) =>
      gmaps.Marker(
          markerId: gmaps.MarkerId(markerId),
          position: gmaps.LatLng(p.lat + bounceShift, p.lng),
          onTap: () {
            _triggerBounce(markerId);
            Future.delayed(const Duration(milliseconds: 120), () {
              if (mounted) _openPulseSheet(p);
            });
          },
          icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
              _pulseHue(p.category)));

  // Simple spatial clustering (iterative, O(n*k)) adequate for modest counts
  List<_PulseCluster> _buildPulseClusters() {
    final clusters = <_PulseCluster>[];
    if (_state.pulses.isEmpty) return clusters;
    // cluster radius scales inverse to zoom
    final clusterRadiusMeters = _zoomToClusterRadius(_currentZoom);
    for (final p in _state.pulses) {
      _PulseCluster? target;
      for (final c in clusters) {
        if (_distanceMeters(c.lat, c.lng, p.lat, p.lng) <=
            clusterRadiusMeters) {
          target = c;
          break;
        }
      }
      if (target == null) {
        target = _PulseCluster._(lat: p.lat, lng: p.lng)..pulses.add(p);
        clusters.add(target);
      } else {
        target.pulses.add(p);
        // Recompute centroid
        final total = target.pulses.length.toDouble();
        target.lat =
            target.pulses.map((e) => e.lat).reduce((a, b) => a + b) / total;
        target.lng =
            target.pulses.map((e) => e.lng).reduce((a, b) => a + b) / total;
      }
    }
    return clusters;
  }

  double _zoomToClusterRadius(double zoom) {
    if (zoom >= 15) return 0; // no clustering
    if (zoom >= 14) return 80;
    if (zoom >= 13) return 140;
    if (zoom >= 12) return 250;
    if (zoom >= 11) return 400;
    return 600; // very zoomed out
  }

  double _distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0; // m
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _degToRad(double deg) => deg * math.pi / 180.0;

  // Convert bounce progress to upward latitude shift (meters -> degrees)
  double _bounceOffset(String markerId, double baseLat) {
    final start = _activeBounces[markerId];
    if (start == null) return 0.0;
    final elapsed = DateTime.now().difference(start);
    final t = elapsed.inMilliseconds / _bounceDuration.inMilliseconds;
    if (t >= 1) return 0.0; // finished
    // Ease out + small settle bounce: use sin curve damped
    final primary = math.sin(t * math.pi); // 0..1..0
    final decel = (1 - t);
    final amplitudeMeters = 35.0; // visible but subtle
    final meters = primary * decel * amplitudeMeters;
    // Approx meters -> degrees latitude
    return meters / 111320.0;
  }

  void _triggerBounce(String markerId) {
    _activeBounces[markerId] = DateTime.now();
    // immediate rebuild for first frame
    _rebuildMarkers();
  }

  void _rebuildCircles() {
    final circles = <gmaps.Circle>{};
    final progress = _pulseController.value; // 0..1
    // Animated ripple for each active pulse
    for (final p in _state.pulses) {
      if (!p.isActive) continue;
      final base = 60.0; // meters
      final spread = 90.0; // additional meters
      // two ripples offset by 0.5 phase
      for (int i = 0; i < 2; i++) {
        final phase = (progress + (i * 0.5)) % 1.0;
        final radius = base + spread * phase;
        final opacity = (1 - phase).clamp(0.0, 1.0);
        circles.add(gmaps.Circle(
          circleId: gmaps.CircleId('pulse_ripple_${p.id}_$i'),
          center: gmaps.LatLng(p.lat, p.lng),
          radius: radius,
          strokeColor: Colors.pink.withOpacity(opacity * 0.6),
          strokeWidth: 2,
          fillColor: Colors.pink.withOpacity(opacity * 0.15),
          consumeTapEvents: false,
        ));
      }
    }
    // Breathing aura for active users (light blue pulsing radius)
    if (_state.showPeople) {
      final breath = (math.sin(progress * 2 * math.pi) + 1) / 2; // 0..1
      for (final u in _state.users) {
        if (!u.isActive) continue;
        final base = 25.0; // meters
        final amp = 15.0; // meters
        final radius = base + amp * breath;
        final opacity = 0.25 + 0.35 * (1 - breath); // soften at expansion
        circles.add(gmaps.Circle(
          circleId: gmaps.CircleId('user_aura_${u.id}'),
          center: gmaps.LatLng(u.lat, u.lng),
          radius: radius,
          strokeColor: Colors.blueAccent.withOpacity(opacity * 0.7),
          strokeWidth: 1,
          fillColor: Colors.lightBlueAccent.withOpacity(opacity * 0.35),
          consumeTapEvents: false,
        ));
      }
    }
    _circles
      ..clear()
      ..addAll(circles);
  }

  void _rebuildHeatmap() {
    final combinedPoints = <_HeatPoint>[];
    if (_state.showPulses) {
      for (final p in _state.pulses) {
        combinedPoints.add(_HeatPoint(p.lat, p.lng,
            weight: (p.attendeeCount).clamp(1, 50).toDouble()));
      }
    }
    if (_state.showPeople) {
      for (final u in _state.users) {
        combinedPoints.add(_HeatPoint(u.lat, u.lng, weight: 5));
      }
    }
    if (combinedPoints.isEmpty) {
      _heatmapCircles.clear();
      return;
    }
    final cellSizeDeg =
        _zoomToCellSize(_currentZoom); // latitude degrees cell size
    final mapBuckets = <String, _HeatBucket>{};
    for (final pt in combinedPoints) {
      final gx = (pt.lat / cellSizeDeg).floor();
      final gy = (pt.lng / cellSizeDeg).floor();
      final key = '$gx:$gy';
      final bucket = mapBuckets.putIfAbsent(key, () => _HeatBucket(gx, gy));
      bucket.add(pt);
    }
    final buckets = mapBuckets.values.toList();
    if (buckets.length > 280) {
      // throttle: merge by skipping every other
      buckets.sort((a, b) => b.totalWeight.compareTo(a.totalWeight));
      buckets.removeRange(280, buckets.length);
    }
    double maxW = 0;
    for (final b in buckets) {
      if (b.totalWeight > maxW) maxW = b.totalWeight;
    }
    maxW = maxW == 0 ? 1 : maxW;
    final heatCircles = <gmaps.Circle>{};
    for (final b in buckets) {
      final intensity = (b.totalWeight / maxW).clamp(0.0, 1.0);
      final centerLat = (b.gx + .5) * cellSizeDeg;
      final centerLng = (b.gy + .5) * cellSizeDeg;
      final radiusMeters = _cellRadiusMeters(cellSizeDeg);
      final color = _gradientColor(intensity);
      heatCircles.add(gmaps.Circle(
        circleId: gmaps.CircleId('heat_${b.gx}_${b.gy}'),
        center: gmaps.LatLng(centerLat, centerLng),
        radius: radiusMeters,
        strokeWidth: 0,
        fillColor: color.withOpacity(.45 * intensity + .15),
        consumeTapEvents: false,
      ));
    }
    _heatmapCircles
      ..clear()
      ..addAll(heatCircles);
  }

  double _zoomToCellSize(double zoom) {
    if (zoom >= 16) return 0.0008; // ~90m
    if (zoom >= 15) return 0.0012; // ~130m
    if (zoom >= 14) return 0.002; // ~220m
    if (zoom >= 13) return 0.0035; // ~390m
    if (zoom >= 12) return 0.006; // ~670m
    if (zoom >= 11) return 0.01; // ~1.1km
    return 0.018; // ~2km
  }

  double _cellRadiusMeters(double cellSizeDeg) {
    // Rough conversion: 1 deg lat ~ 111.32 km
    return cellSizeDeg * 111320 / 2.2; // half cell * fudge to overlap
  }

  Color _gradientColor(double t) {
    const stops = [
      Color(0xFF0D47A1), // deep blue
      Color(0xFF1976D2),
      Color(0xFF26C6DA), // cyan
      Color(0xFF66BB6A), // green
      Color(0xFFFFEE58), // yellow
      Color(0xFFFFA726), // orange
      Color(0xFFD32F2F), // red
    ];
    if (t <= 0) return stops.first;
    if (t >= 1) return stops.last;
    final scaled = t * (stops.length - 1);
    final i = scaled.floor();
    final frac = scaled - i;
    final a = stops[i];
    final b = stops[i + 1];
    int lerp(int av, int bv) => av + ((bv - av) * frac).round();
    return Color.fromARGB(
        255, lerp(a.red, b.red), lerp(a.green, b.green), lerp(a.blue, b.blue));
  }

  void _updatePulseAnimation() {
    // Only rebuild circles if there are active pulses to reduce rebuild cost
    bool needsMarkerRebuild = false;
    // Clean up finished bounces
    if (_activeBounces.isNotEmpty) {
      final finished = <String>[];
      final now = DateTime.now();
      _activeBounces.forEach((id, start) {
        if (now.difference(start) >= _bounceDuration)
          finished.add(id);
        else
          needsMarkerRebuild = true; // active bounce needs position update
      });
      for (final id in finished) {
        _activeBounces.remove(id);
      }
    }
    if (mounted) {
      if (_state.pulses.any((p) => p.isActive)) {
        _rebuildCircles();
      }
      if (needsMarkerRebuild) {
        _rebuildMarkers();
      }
      if (_showHeatmap) {
        // animate subtle heat shimmer by slight opacity variation using progress
        _rebuildHeatmap();
      }
    }
  }

  double _pulseHue(String? category) {
    switch (category) {
      case 'concert':
        return 300;
      case 'party':
        return 20;
      case 'meetup':
        return 200;
      default:
        return gmaps.BitmapDescriptor.hueRose;
    }
  }

  @override
  void dispose() {
    _state.disposeAuto();
    _state.removeListener(_onStateChanged);
    _pulseController.dispose();
    _fabController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _openPulseSheet(PulseMarker p) {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final theme = FlutterFlowTheme.of(context);
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return DraggableScrollableSheet(
              initialChildSize: 0.4,
              minChildSize: 0.25,
              maxChildSize: 0.85,
              builder: (_, scroll) {
                return Container(
                    decoration: BoxDecoration(
                        color: theme.secondaryBackground,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(28)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ]),
                    child: Column(
                      children: [
                        // Handle bar
                        Container(
                          margin: const EdgeInsets.only(top: 12),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: theme.secondaryText.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Expanded(
                          child: ListView(
                              controller: scroll,
                              padding: const EdgeInsets.all(20),
                              children: [
                                // Header row
                                Row(children: [
                                  // Category icon
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          _getCategoryColor(p.category),
                                          _getCategoryColor(p.category)
                                              .withOpacity(0.7),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: _getCategoryColor(p.category)
                                              .withOpacity(0.3),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      _getCategoryIcon(p.category),
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(p.title,
                                            style: theme.titleLarge.copyWith(
                                                fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            if (p.category != null) ...[
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: _getCategoryColor(
                                                          p.category)
                                                      .withOpacity(0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  p.category!.toUpperCase(),
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: _getCategoryColor(
                                                        p.category),
                                                    letterSpacing: 0.5,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                            ],
                                            if (p.isActive) _ActiveBadge(),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    icon: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: theme.secondaryText
                                            .withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(Icons.close_rounded,
                                          size: 18, color: theme.secondaryText),
                                    ),
                                  ),
                                ]),

                                const SizedBox(height: 24),

                                // Stats row
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: theme.primaryBackground,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: [
                                      _PulseStatItem(
                                        icon: Icons.people_rounded,
                                        value: '${p.attendeeCount}',
                                        label: 'Attending',
                                        color: theme.info,
                                      ),
                                      Container(
                                        width: 1,
                                        height: 40,
                                        color: theme.secondaryText
                                            .withOpacity(0.2),
                                      ),
                                      _PulseStatItem(
                                        icon: Icons.schedule_rounded,
                                        value: p.eventTime != null
                                            ? dateTimeFormat(
                                                'relative', p.eventTime)
                                            : 'Now',
                                        label: 'When',
                                        color: theme.warning,
                                      ),
                                      Container(
                                        width: 1,
                                        height: 40,
                                        color: theme.secondaryText
                                            .withOpacity(0.2),
                                      ),
                                      _PulseStatItem(
                                        icon: Icons.location_on_rounded,
                                        value:
                                            '${(_distanceMeters(p.lat, p.lng, 40.7128, -74.0060) / 1000).toStringAsFixed(1)}',
                                        label: 'km away',
                                        color: theme.success,
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 24),

                                // Actions
                                Row(
                                  children: [
                                    Expanded(
                                      child: _PulseActionButton(
                                        icon: Icons.person_add_rounded,
                                        label: 'Join',
                                        color: theme.primary,
                                        filled: true,
                                        onTap: () {
                                          HapticFeedback.mediumImpact();
                                          ApiService.instance.joinPulse(p.id);
                                          Navigator.pop(ctx);
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content:
                                                  const Text('Joined pulse!'),
                                              behavior:
                                                  SnackBarBehavior.floating,
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          12)),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _PulseActionButton(
                                        icon: Icons.chat_bubble_rounded,
                                        label: 'Chat',
                                        color: theme.info,
                                        onTap: () {
                                          // Open chat
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _PulseActionButton(
                                        icon: Icons.open_in_new_rounded,
                                        label: 'Details',
                                        color: theme.tertiary,
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          context.pushNamed(
                                            PulseDetailPage.routeName,
                                            pathParameters: {'id': p.id},
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 16),

                                // Share row
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: theme.secondaryText
                                            .withOpacity(0.1)),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.share_rounded,
                                          size: 20, color: theme.secondaryText),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                            'Share this pulse with friends',
                                            style: theme.bodySmall),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          // Share functionality
                                        },
                                        child: Text('Share',
                                            style: TextStyle(
                                                color: theme.primary)),
                                      ),
                                    ],
                                  ),
                                ),
                              ]),
                        ),
                      ],
                    ));
              });
        });
  }

  Color _getCategoryColor(String? category) {
    switch (category?.toLowerCase()) {
      case 'concert':
        return Colors.purple;
      case 'party':
        return Colors.orange;
      case 'meetup':
        return Colors.cyan;
      case 'sports':
        return Colors.green;
      case 'food':
        return Colors.amber;
      default:
        return Colors.pink;
    }
  }

  IconData _getCategoryIcon(String? category) {
    switch (category?.toLowerCase()) {
      case 'concert':
        return Icons.music_note_rounded;
      case 'party':
        return Icons.celebration_rounded;
      case 'meetup':
        return Icons.groups_rounded;
      case 'sports':
        return Icons.sports_rounded;
      case 'food':
        return Icons.restaurant_rounded;
      default:
        return Icons.local_fire_department_rounded;
    }
  }

  Widget _glowDot({Color color = Colors.green}) => Container(
      width: 14,
      height: 14,
      decoration:
          BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [
        BoxShadow(color: color.withOpacity(.6), blurRadius: 12, spreadRadius: 4)
      ]));

  void _openUserCard(UserBubble u) {
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) {
          final theme = FlutterFlowTheme.of(context);

          return Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            decoration: BoxDecoration(
              color: theme.secondaryBackground,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.secondaryText.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Avatar and name
                      Stack(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [theme.primary, theme.tertiary],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 44,
                              backgroundColor: theme.secondaryBackground,
                              backgroundImage: u.avatarUrl != null
                                  ? NetworkImage(u.avatarUrl!)
                                  : null,
                              child: u.avatarUrl == null
                                  ? Text(
                                      u.name.isNotEmpty
                                          ? u.name[0].toUpperCase()
                                          : '?',
                                      style: theme.headlineLarge
                                          .copyWith(color: theme.primary),
                                    )
                                  : null,
                            ),
                          ),
                          if (u.isActive)
                            Positioned(
                              right: 4,
                              bottom: 4,
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: theme.secondaryBackground,
                                      width: 3),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(u.name,
                          style: theme.titleLarge
                              .copyWith(fontWeight: FontWeight.bold)),
                      if (u.status != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          u.status!,
                          style: theme.bodyMedium
                              .copyWith(color: theme.secondaryText),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.location_on_rounded,
                              size: 14, color: theme.secondaryText),
                          const SizedBox(width: 4),
                          Text(
                            '${(_distanceMeters(u.lat, u.lng, 40.7128, -74.0060) / 1000).toStringAsFixed(1)} km away',
                            style: theme.bodySmall
                                .copyWith(color: theme.secondaryText),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: _UserActionButton(
                              icon: Icons.person_add_rounded,
                              label: 'Add Friend',
                              color: theme.primary,
                              filled: true,
                              onTap: () {
                                HapticFeedback.mediumImpact();
                                ApiService.instance.followUser(u.id);
                                Navigator.pop(ctx);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _UserActionButton(
                              icon: Icons.chat_bubble_rounded,
                              label: 'Message',
                              color: theme.info,
                              onTap: () {
                                Navigator.pop(ctx);
                                // Open DM
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: _UserActionButton(
                          icon: Icons.groups_rounded,
                          label: 'View Shared Pulses',
                          color: theme.tertiary,
                          onTap: () {
                            Navigator.pop(ctx);
                            // View shared pulses
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        });
  }

  Widget _miniButton(IconData icon, String label, VoidCallback onTap) =>
      const SizedBox.shrink(); // Deprecated

  Widget _actionChip(IconData icon, String label, VoidCallback onTap) =>
      const SizedBox.shrink(); // Deprecated

  void _onCameraIdle() async {
    if (_controller == null) return;
    final center =
        await _controller!.getLatLng(const gmaps.ScreenCoordinate(x: 0, y: 0));
    await _state.load(center: center);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ChangeNotifierProvider.value(
        value: _state,
        child: Consumer<DualLayerMapState>(builder: (context, s, _) {
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value:
                isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
            child: Scaffold(
              extendBodyBehindAppBar: true,
              body: Stack(children: [
                // Map
                Positioned.fill(
                    child: gmaps.GoogleMap(
                  initialCameraPosition: const gmaps.CameraPosition(
                      target: gmaps.LatLng(40.7128, -74.0060), zoom: 12),
                  onMapCreated: (c) {
                    _controller = c;
                    if (_mapStyleDark) {
                      _controller?.setMapStyle(_darkMapStyle);
                    }
                  },
                  markers: _markers,
                  circles: {..._circles, if (_showHeatmap) ..._heatmapCircles},
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  compassEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  onCameraIdle: _onCameraIdle,
                  onCameraMove: (pos) {
                    _currentZoom = pos.zoom;
                    _cameraMoveDebounce?.cancel();
                    _cameraMoveDebounce =
                        Timer(const Duration(milliseconds: 180), () {
                      if (mounted) {
                        _rebuildMarkers();
                        if (_showHeatmap) _rebuildHeatmap();
                      }
                    });
                  },
                  onTap: (_) {
                    if (_speedDialOpen) {
                      setState(() => _speedDialOpen = false);
                      _fabController.reverse();
                    }
                    if (_searchFocus.hasFocus) {
                      _searchFocus.unfocus();
                    }
                  },
                )),

                // Gradient overlay at top for better visibility
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 140,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          (isDark ? Colors.black : Colors.white)
                              .withOpacity(0.7),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                // Search Bar and Filters
                _buildGlassSearchBar(theme, isDark),
                _buildFilterChipsRow(theme, isDark),

                // Stats Badge
                _buildStatsBadge(theme, isDark, s),

                // Legend Panel
                if (_showLegend) _buildLegendPanel(theme, isDark),

                // Speed Dial FABs
                _buildSpeedDial(theme, isDark, s),

                // Loading indicator
                if (s.loading)
                  Positioned(
                    top: MediaQuery.viewPaddingOf(context).top + 80,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: theme.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation(Colors.white),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('Loading...',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ).animate().fadeIn().slideY(begin: -0.3),
                    ),
                  ),
              ]),
              bottomNavigationBar: const NavbarWidget(),
            ),
          );
        }));
  }

  Widget _buildGlassSearchBar(FlutterFlowTheme theme, bool isDark) {
    return Positioned(
      top: MediaQuery.viewPaddingOf(context).top + 12,
      left: 16,
      right: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: (isDark ? Colors.black : Colors.white).withOpacity(0.75),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: (isDark ? Colors.white : Colors.black).withOpacity(0.1),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _isSearching
                        ? theme.primary.withOpacity(0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.search_rounded,
                    color: _isSearching ? theme.primary : theme.secondaryText,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    decoration: InputDecoration(
                      hintText: 'Search pulses, people, places...',
                      hintStyle: TextStyle(
                        color: theme.secondaryText.withOpacity(0.6),
                        fontSize: 15,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: TextStyle(fontSize: 15, color: theme.primaryText),
                    onTap: () => setState(() => _isSearching = true),
                    onChanged: (v) {
                      // Future: implement search
                    },
                  ),
                ),
                if (_searchController.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: theme.secondaryText.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.close,
                          size: 16, color: theme.secondaryText),
                    ),
                  ),
                const SizedBox(width: 4),
                _GlassIconButton(
                  icon: Icons.tune_rounded,
                  onTap: _openFiltersSheet,
                  color: theme.primary,
                ),
              ],
            ),
          ),
        ),
      ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.2),
    );
  }

  Widget _buildFilterChipsRow(FlutterFlowTheme theme, bool isDark) {
    return Positioned(
      top: MediaQuery.viewPaddingOf(context).top + 76,
      left: 0,
      right: 0,
      child: SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            _ModernFilterChip(
              label: 'Events',
              icon: Icons.local_fire_department_rounded,
              selected: _state.showPulses,
              count: _state.pulses.length,
              color: theme.tertiary,
              onSelected: (v) => _state.setFilters(pulsesLayer: v),
            ),
            const SizedBox(width: 8),
            _ModernFilterChip(
              label: 'People',
              icon: Icons.people_rounded,
              selected: _state.showPeople,
              count: _state.users.length,
              color: theme.info,
              onSelected: (v) => _state.setFilters(peopleLayer: v),
            ),
            const SizedBox(width: 8),
            _ModernFilterChip(
              label: '${_state.radiusKm.toInt()}km',
              icon: Icons.radar_rounded,
              selected: true,
              color: theme.success,
              onSelected: (_) => _cycleRadius(),
            ),
            const SizedBox(width: 8),
            _ModernFilterChip(
              label: 'Cluster',
              icon: Icons.bubble_chart_rounded,
              selected: _enableClustering,
              color: theme.secondary,
              onSelected: (v) {
                setState(() => _enableClustering = v);
                _rebuildMarkers();
              },
            ),
            const SizedBox(width: 8),
            _ModernFilterChip(
              label: 'Heatmap',
              icon: Icons.whatshot_rounded,
              selected: _showHeatmap,
              color: theme.warning,
              onSelected: (v) {
                setState(() => _showHeatmap = v);
                if (v)
                  _rebuildHeatmap();
                else
                  _heatmapCircles.clear();
              },
            ),
          ],
        ),
      ).animate().fadeIn(delay: 100.ms, duration: 300.ms).slideY(begin: -0.2),
    );
  }

  Widget _buildStatsBadge(
      FlutterFlowTheme theme, bool isDark, DualLayerMapState s) {
    final activePulses = s.pulses.where((p) => p.isActive).length;
    final activeUsers = s.users.where((u) => u.isActive).length;

    return Positioned(
      top: MediaQuery.viewPaddingOf(context).top + 130,
      left: 16,
      child: GestureDetector(
        onTap: () => setState(() => _showLegend = !_showLegend),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (isDark ? Colors.black : Colors.white).withOpacity(0.7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color:
                      (isDark ? Colors.white : Colors.black).withOpacity(0.1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StatItem(
                    icon: Icons.local_fire_department_rounded,
                    value: '${s.pulses.length}',
                    color: theme.tertiary,
                    active: activePulses > 0,
                  ),
                  Container(
                    width: 1,
                    height: 20,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    color: theme.secondaryText.withOpacity(0.3),
                  ),
                  _StatItem(
                    icon: Icons.people_rounded,
                    value: '${s.users.length}',
                    color: theme.info,
                    active: activeUsers > 0,
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _showLegend
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: theme.secondaryText,
                  ),
                ],
              ),
            ),
          ),
        ),
      ).animate().fadeIn(delay: 200.ms, duration: 300.ms).slideX(begin: -0.3),
    );
  }

  Widget _buildLegendPanel(FlutterFlowTheme theme, bool isDark) {
    return Positioned(
      top: MediaQuery.viewPaddingOf(context).top + 180,
      left: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            width: 200,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: (isDark ? Colors.black : Colors.white).withOpacity(0.85),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: (isDark ? Colors.white : Colors.black).withOpacity(0.1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Legend',
                    style:
                        theme.titleSmall.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _LegendItem(color: Colors.pink, label: 'Active Pulses'),
                _LegendItem(color: Colors.orange, label: 'Parties'),
                _LegendItem(color: Colors.purple, label: 'Concerts'),
                _LegendItem(color: Colors.cyan, label: 'Meetups'),
                _LegendItem(color: Colors.blueAccent, label: 'People'),
                if (_showHeatmap) ...[
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text('Heatmap Intensity', style: theme.labelSmall),
                  const SizedBox(height: 6),
                  Container(
                    height: 12,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF0D47A1),
                          Color(0xFF26C6DA),
                          Color(0xFF66BB6A),
                          Color(0xFFFFEE58),
                          Color(0xFFD32F2F),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Low',
                          style: theme.labelSmall.copyWith(fontSize: 10)),
                      Text('High',
                          style: theme.labelSmall.copyWith(fontSize: 10)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ).animate().fadeIn(duration: 200.ms).slideX(begin: -0.3),
    );
  }

  Widget _buildSpeedDial(
      FlutterFlowTheme theme, bool isDark, DualLayerMapState s) {
    return Positioned(
      right: 16,
      bottom: 100,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Speed dial items (shown when open)
          if (_speedDialOpen) ...[
            _SpeedDialItem(
              icon: Icons.map_rounded,
              label: 'Map Style',
              color: theme.info,
              onTap: () {
                setState(() => _mapStyleDark = !_mapStyleDark);
                _controller?.setMapStyle(_mapStyleDark ? _darkMapStyle : null);
              },
            ).animate().fadeIn(duration: 150.ms).slideX(begin: 0.5),
            const SizedBox(height: 12),
            _SpeedDialItem(
              icon: Icons.my_location_rounded,
              label: 'My Location',
              color: theme.success,
              onTap: () async {
                if (s.currentCenter != null) {
                  await _controller?.animateCamera(
                    gmaps.CameraUpdate.newLatLng(s.currentCenter!),
                  );
                }
              },
            )
                .animate()
                .fadeIn(delay: 50.ms, duration: 150.ms)
                .slideX(begin: 0.5),
            const SizedBox(height: 12),
            _SpeedDialItem(
              icon: Icons.refresh_rounded,
              label: 'Refresh',
              color: theme.warning,
              onTap: () {
                if (s.currentCenter != null) {
                  s.load(center: s.currentCenter!);
                }
              },
            )
                .animate()
                .fadeIn(delay: 100.ms, duration: 150.ms)
                .slideX(begin: 0.5),
            const SizedBox(height: 12),
          ],

          // Create Pulse FAB
          _MainFab(
            icon: Icons.add_rounded,
            color: theme.tertiary,
            onTap: () {
              context.pushNamed(CreatePulseWidget.routeName);
            },
          )
              .animate()
              .fadeIn(delay: 150.ms)
              .scale(begin: const Offset(0.5, 0.5)),

          const SizedBox(height: 12),

          // Main Speed Dial Toggle
          _MainFab(
            icon: _speedDialOpen ? Icons.close_rounded : Icons.apps_rounded,
            color: theme.primary,
            onTap: () {
              setState(() => _speedDialOpen = !_speedDialOpen);
              if (_speedDialOpen) {
                _fabController.forward();
              } else {
                _fabController.reverse();
              }
            },
          )
              .animate()
              .fadeIn(delay: 200.ms)
              .scale(begin: const Offset(0.5, 0.5)),
        ],
      ),
    );
  }

  Widget _buildTopSearchBar(theme) =>
      const SizedBox.shrink(); // Deprecated - using _buildGlassSearchBar

  Widget _buildFilterChips(theme) =>
      const SizedBox.shrink(); // Deprecated - using _buildFilterChipsRow

  void _cycleRadius() {
    final options = [2.0, 5.0, 10.0, 25.0, 50.0];
    final idx = options.indexWhere((e) => e == _state.radiusKm);
    final next = options[(idx + 1) % options.length];
    _state.setFilters(radius: next);
    if (_state.currentCenter != null) {
      _state.load(center: _state.currentCenter!);
    }
    // Haptic feedback
    HapticFeedback.selectionClick();
  }

  void _openFiltersSheet() {
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) {
          final theme = FlutterFlowTheme.of(context);
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return StatefulBuilder(builder: (context, setModalState) {
            return Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              decoration: BoxDecoration(
                color: theme.secondaryBackground,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.secondaryText.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: theme.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.tune_rounded,
                                  color: theme.primary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Map Filters',
                                      style: theme.titleMedium.copyWith(
                                          fontWeight: FontWeight.bold)),
                                  Text('Customize your map view',
                                      style: theme.bodySmall),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(ctx),
                              icon: Icon(Icons.close_rounded,
                                  color: theme.secondaryText),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Layer toggles
                        Text('Layers',
                            style: theme.labelLarge
                                .copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        _FilterToggleRow(
                          icon: Icons.local_fire_department_rounded,
                          title: 'Show Events',
                          subtitle: '${_state.pulses.length} pulses nearby',
                          value: _state.showPulses,
                          color: theme.tertiary,
                          onChanged: (v) {
                            setModalState(
                                () => _state.setFilters(pulsesLayer: v));
                          },
                        ),
                        const SizedBox(height: 8),
                        _FilterToggleRow(
                          icon: Icons.people_rounded,
                          title: 'Show People',
                          subtitle: '${_state.users.length} users nearby',
                          value: _state.showPeople,
                          color: theme.info,
                          onChanged: (v) {
                            setModalState(
                                () => _state.setFilters(peopleLayer: v));
                          },
                        ),

                        const SizedBox(height: 24),

                        // Radius slider
                        Text('Search Radius',
                            style: theme.labelLarge
                                .copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.radar_rounded,
                                size: 20, color: theme.success),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: theme.success,
                                  inactiveTrackColor:
                                      theme.success.withOpacity(0.2),
                                  thumbColor: theme.success,
                                  overlayColor: theme.success.withOpacity(0.1),
                                ),
                                child: Slider(
                                  value: _state.radiusKm,
                                  min: 1,
                                  max: 100,
                                  divisions: 99,
                                  label:
                                      '${_state.radiusKm.toStringAsFixed(0)} km',
                                  onChanged: (v) {
                                    setModalState(
                                        () => _state.setFilters(radius: v));
                                  },
                                  onChangeEnd: (v) {
                                    if (_state.currentCenter != null) {
                                      _state.load(
                                          center: _state.currentCenter!);
                                    }
                                  },
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: theme.success.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_state.radiusKm.toInt()} km',
                                style: TextStyle(
                                    color: theme.success,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Display options
                        Text('Display Options',
                            style: theme.labelLarge
                                .copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        _FilterToggleRow(
                          icon: Icons.bubble_chart_rounded,
                          title: 'Enable Clustering',
                          subtitle: 'Group nearby markers',
                          value: _enableClustering,
                          color: theme.secondary,
                          onChanged: (v) {
                            setModalState(() {
                              _enableClustering = v;
                              _rebuildMarkers();
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        _FilterToggleRow(
                          icon: Icons.whatshot_rounded,
                          title: 'Show Heatmap',
                          subtitle: 'Activity density overlay',
                          value: _showHeatmap,
                          color: theme.warning,
                          onChanged: (v) {
                            setModalState(() {
                              _showHeatmap = v;
                              if (v)
                                _rebuildHeatmap();
                              else
                                _heatmapCircles.clear();
                            });
                          },
                        ),

                        const SizedBox(height: 24),

                        // Apply button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            child: const Text('Apply Filters',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          });
        });
  }

  Widget _floatingBtn(IconData icon, String tooltip, VoidCallback onTap) =>
      const SizedBox.shrink(); // Deprecated - using _buildSpeedDial
}

// ============ Custom Widgets ============

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _GlassIconButton(
      {required this.icon, required this.onTap, required this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 22, color: color),
      ),
    );
  }
}

class _ModernFilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final int? count;
  final Color color;
  final ValueChanged<bool> onSelected;

  const _ModernFilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    this.count,
    required this.color,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onSelected(!selected);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? color.withOpacity(isDark ? 0.3 : 0.15)
              : (isDark ? Colors.black : Colors.white).withOpacity(0.7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 8,
                spreadRadius: 0,
              ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: selected
                    ? color
                    : FlutterFlowTheme.of(context).secondaryText),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected
                    ? color
                    : FlutterFlowTheme.of(context).secondaryText,
              ),
            ),
            if (count != null && count! > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.bold, color: color),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;
  final bool active;

  const _StatItem({
    required this.icon,
    required this.value,
    required this.color,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          children: [
            Icon(icon, size: 18, color: color),
            if (active)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: FlutterFlowTheme.of(context).primaryText,
          ),
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: color.withOpacity(0.4),
                    blurRadius: 4,
                    spreadRadius: 1),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(label, style: FlutterFlowTheme.of(context).bodySmall),
        ],
      ),
    );
  }
}

class _SpeedDialItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SpeedDialItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ],
    );
  }
}

class _MainFab extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _MainFab(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 26),
      ),
    );
  }
}

class _FilterToggleRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final Color color;
  final ValueChanged<bool> onChanged;

  const _FilterToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: value ? color.withOpacity(0.05) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value
              ? color.withOpacity(0.2)
              : theme.secondaryText.withOpacity(0.1),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style:
                        theme.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style:
                        theme.bodySmall.copyWith(color: theme.secondaryText)),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: color,
          ),
        ],
      ),
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Colors.green.withOpacity(0.5), blurRadius: 4),
              ],
            ),
          ),
          const SizedBox(width: 4),
          const Text(
            'LIVE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.green,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseStatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _PulseStatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Column(
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.titleSmall.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: theme.labelSmall.copyWith(color: theme.secondaryText),
        ),
      ],
    );
  }
}

class _PulseActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool filled;
  final VoidCallback onTap;

  const _PulseActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.filled = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: filled ? color : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: filled ? null : Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: filled ? Colors.white : color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: filled ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool filled;
  final VoidCallback onTap;

  const _UserActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.filled = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: filled ? color : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: filled ? null : Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: filled ? Colors.white : color),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: filled ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
