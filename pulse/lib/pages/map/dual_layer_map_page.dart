import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:provider/provider.dart';
import '../../backend/api_service.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import '../../flutter_flow/flutter_flow_util.dart';
import '../../main.dart';
import '../../components/navbar_widget.dart';

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
  final Map<String, DateTime> _activeBounces = {}; // markerId -> start time
  static const Duration _bounceDuration = Duration(milliseconds: 650);
  double _currentZoom = 12;
  bool _enableClustering = true;
  Timer? _cameraMoveDebounce;
  bool _showHeatmap = false;

  @override
  void initState() {
    super.initState();
    _pulseController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..addListener(_updatePulseAnimation)
          ..repeat();
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
    super.dispose();
  }

  void _openPulseSheet(PulseMarker p) {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final theme = FlutterFlowTheme.of(context);
          return DraggableScrollableSheet(
              initialChildSize: .35,
              minChildSize: .2,
              maxChildSize: .85,
              builder: (_, scroll) {
                return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: theme.secondaryBackground,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24))),
                    child: ListView(controller: scroll, children: [
                      Row(children: [
                        Expanded(
                            child: Text(p.title, style: theme.headlineSmall)),
                        if (p.isActive) _glowDot(color: theme.primary)
                      ]),
                      const SizedBox(height: 8),
                      Text('Attendees: ${p.attendeeCount}',
                          style: theme.labelLarge),
                      if (p.eventTime != null)
                        Text(
                            'When: ${dateTimeFormat('relative', p.eventTime)}'),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, children: [
                        _actionChip(Icons.person_add, 'Join Pulse', () {
                          ApiService.instance.joinPulse(p.id);
                        }),
                        _actionChip(Icons.chat_bubble, 'Message Group', () {}),
                        _actionChip(Icons.info_outline, 'View Details', () {}),
                      ])
                    ]));
              });
        });
  }

  Widget _glowDot({Color color = Colors.green}) => Container(
      width: 14,
      height: 14,
      decoration:
          BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [
        BoxShadow(color: color.withOpacity(.6), blurRadius: 12, spreadRadius: 4)
      ]));

  void _openUserCard(UserBubble u) {
    showDialog(
        context: context,
        builder: (ctx) {
          final theme = FlutterFlowTheme.of(context);
          return Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircleAvatar(
                        radius: 32,
                        backgroundImage: u.avatarUrl != null
                            ? NetworkImage(u.avatarUrl!)
                            : null,
                        child: u.avatarUrl == null
                            ? Text(u.name.isNotEmpty ? u.name[0] : '?')
                            : null),
                    const SizedBox(height: 8),
                    Text(u.name, style: theme.titleMedium),
                    if (u.status != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(u.status!,
                              style: theme.bodySmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis)),
                    const SizedBox(height: 12),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _miniButton(Icons.person_add_alt, 'Add', () {
                            ApiService.instance.followUser(u.id);
                            Navigator.pop(ctx);
                          }),
                          _miniButton(Icons.chat, 'Message', () {
                            Navigator.pop(ctx);
                          }),
                          _miniButton(Icons.group, 'Shared', () {
                            Navigator.pop(ctx);
                          }),
                        ])
                  ])));
        });
  }

  Widget _miniButton(IconData icon, String label, VoidCallback onTap) =>
      InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(.1),
                  borderRadius: BorderRadius.circular(12)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 20),
                Text(label, style: const TextStyle(fontSize: 11))
              ])));

  Widget _actionChip(IconData icon, String label, VoidCallback onTap) =>
      ActionChip(
          avatar: Icon(icon, size: 18), label: Text(label), onPressed: onTap);

  void _onCameraIdle() async {
    if (_controller == null) return;
    final center =
        await _controller!.getLatLng(const gmaps.ScreenCoordinate(x: 0, y: 0));
    await _state.load(center: center);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return ChangeNotifierProvider.value(
        value: _state,
        child: Consumer<DualLayerMapState>(builder: (context, s, _) {
          return Scaffold(
            body: Stack(children: [
              Positioned.fill(
                  child: gmaps.GoogleMap(
                initialCameraPosition: const gmaps.CameraPosition(
                    target: gmaps.LatLng(40.7128, -74.0060), zoom: 12),
                onMapCreated: (c) {
                  _controller = c;
                },
                markers: _markers,
                // Combine animated circles + heatmap circles
                circles: {..._circles, if (_showHeatmap) ..._heatmapCircles},
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
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
                onTap: (_) {},
              )),
              _buildTopSearchBar(theme),
              _buildFilterChips(theme),
              Positioned(
                  bottom: 24,
                  right: 16,
                  child: Column(children: [
                    _floatingBtn(Icons.center_focus_strong, 'Recenter',
                        () async {
                      if (_controller != null && s.currentCenter != null) {
                        _controller!.animateCamera(
                            gmaps.CameraUpdate.newLatLng(s.currentCenter!));
                      }
                    }),
                    const SizedBox(height: 12),
                    _floatingBtn(Icons.add_location_alt, 'Create', () {}),
                  ])),
              if (s.loading)
                const Positioned(
                    top: 8, right: 8, child: CircularProgressIndicator()),
            ]),
            bottomNavigationBar: const NavbarWidget(),
          );
        }));
  }

  Widget _buildTopSearchBar(theme) => Positioned(
      top: MediaQuery.viewPaddingOf(context).top + 12,
      left: 16,
      right: 16,
      child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(32),
          color: theme.secondaryBackground,
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                const Icon(Icons.search),
                const SizedBox(width: 8),
                Expanded(
                    child: GestureDetector(
                        onTap: () {},
                        child: const Text('Search pulses or friends',
                            style: TextStyle(fontSize: 14)))),
                IconButton(
                    icon: const Icon(Icons.filter_alt),
                    onPressed: () {
                      _openFiltersSheet();
                    }),
                IconButton(
                    icon: const Icon(Icons.brightness_6),
                    onPressed: () {
                      final mode =
                          Theme.of(context).brightness == Brightness.dark
                              ? ThemeMode.light
                              : ThemeMode.dark;
                      MyApp.of(context).setThemeMode(mode);
                    }),
              ]))));

  Widget _buildFilterChips(theme) => Positioned(
      top: MediaQuery.viewPaddingOf(context).top + 70,
      left: 8,
      right: 8,
      child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            FilterChip(
                label: const Text('Events'),
                selected: _state.showPulses,
                onSelected: (v) {
                  _state.setFilters(pulsesLayer: v);
                }),
            const SizedBox(width: 8),
            FilterChip(
                label: const Text('People'),
                selected: _state.showPeople,
                onSelected: (v) {
                  _state.setFilters(peopleLayer: v);
                }),
            const SizedBox(width: 8),
            FilterChip(
                label: Text('${_state.radiusKm.toStringAsFixed(0)}km'),
                selected: true,
                onSelected: (_) {
                  _cycleRadius();
                }),
            const SizedBox(width: 8),
            FilterChip(
                label: const Text('Cluster'),
                selected: _enableClustering,
                onSelected: (v) {
                  setState(() => _enableClustering = v);
                  _rebuildMarkers();
                }),
            const SizedBox(width: 8),
            FilterChip(
                label: const Text('Heat'),
                selected: _showHeatmap,
                onSelected: (v) {
                  setState(() => _showHeatmap = v);
                  if (v) {
                    _rebuildHeatmap();
                  } else {
                    _heatmapCircles.clear();
                  }
                }),
          ])));

  void _cycleRadius() {
    final options = [2.0, 5.0, 10.0, 25.0];
    final idx = options.indexWhere((e) => e == _state.radiusKm);
    final next = options[(idx + 1) % options.length];
    _state.setFilters(radius: next);
    if (_state.currentCenter != null)
      _state.load(center: _state.currentCenter!);
  }

  void _openFiltersSheet() {
    showModalBottomSheet(
        context: context,
        builder: (ctx) {
          return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Filters',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                SwitchListTile(
                    title: const Text('Show Events'),
                    value: _state.showPulses,
                    onChanged: (v) {
                      Navigator.pop(ctx);
                      _state.setFilters(pulsesLayer: v);
                    }),
                SwitchListTile(
                    title: const Text('Show People'),
                    value: _state.showPeople,
                    onChanged: (v) {
                      Navigator.pop(ctx);
                      _state.setFilters(peopleLayer: v);
                    }),
                ListTile(
                    title: Text('Radius: ${_state.radiusKm} km'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      _cycleRadius();
                    }),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                    label: const Text('Close'))
              ]));
        });
  }

  Widget _floatingBtn(IconData icon, String tooltip, VoidCallback onTap) =>
      FloatingActionButton(
          heroTag: tooltip, onPressed: onTap, child: Icon(icon));
}
