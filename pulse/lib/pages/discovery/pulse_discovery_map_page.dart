import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
// Removed third-party cluster manager due to symbol conflict; using lightweight manual clustering.

import '../../backend/api_service.dart';
import 'package:geocoding/geocoding.dart' as geocoding; // if needed later
import '../../auth/firebase_auth/auth_util.dart';
import '../../components/navbar_widget.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import '../../flutter_flow/nav/nav.dart';
import '../pulse_detail/pulse_detail_page.dart';
import '../create_pulse/create_pulse_widget.dart';

/// Route metadata
class PulseDiscoveryMapPage extends ConsumerStatefulWidget {
  const PulseDiscoveryMapPage({super.key});
  static String routeName = 'PulseDiscoveryMap';
  static String routePath = '/discovery-map';

  @override
  ConsumerState<PulseDiscoveryMapPage> createState() =>
      _PulseDiscoveryMapPageState();
}

// --- Data models for clustering ---
class _PulseItem {
  // cluster manager expects ClusterItem mixin
  final Map<String, dynamic> data;
  final LatLng position;
  _PulseItem(this.data)
      : position = LatLng(
          (data['latitude'] ?? data['lat'] ?? 0).toDouble(),
          (data['longitude'] ?? data['lng'] ?? 0).toDouble(),
        );
  LatLng get location => position;
}

class _UserItem {
  final Map<String, dynamic> data;
  final LatLng position;
  _UserItem(this.data)
      : position = LatLng(
          (data['latitude'] ?? data['lat'] ?? 0).toDouble(),
          (data['longitude'] ?? data['lng'] ?? 0).toDouble(),
        );
  LatLng get location => position;
}

// --- Providers ---

final _filtersProvider =
    StateNotifierProvider<_MapFiltersNotifier, _MapFilters>(
        (ref) => _MapFiltersNotifier());

class _MapFilters {
  final bool showPulses;
  final bool showUsers;
  final double radiusKm;
  final DateTimeRange? timeRange;
  const _MapFilters({
    this.showPulses = true,
    this.showUsers = true,
    this.radiusKm = 25,
    this.timeRange,
  });
  _MapFilters copyWith(
          {bool? showPulses,
          bool? showUsers,
          double? radiusKm,
          DateTimeRange? timeRange}) =>
      _MapFilters(
        showPulses: showPulses ?? this.showPulses,
        showUsers: showUsers ?? this.showUsers,
        radiusKm: radiusKm ?? this.radiusKm,
        timeRange: timeRange ?? this.timeRange,
      );
}

class _MapFiltersNotifier extends StateNotifier<_MapFilters> {
  _MapFiltersNotifier() : super(const _MapFilters());
  void togglePulses() => state = state.copyWith(showPulses: !state.showPulses);
  void toggleUsers() => state = state.copyWith(showUsers: !state.showUsers);
  void setRadius(double v) => state = state.copyWith(radiusKm: v);
  void setTimeRange(DateTimeRange? r) => state = state.copyWith(timeRange: r);
}

// Pulses & users polling (simplified; in real app use websockets / location stream)
final _currentLocationProvider = StateProvider<LatLng?>((ref) => null);

final _pulseItemsProvider =
    FutureProvider.autoDispose<List<_PulseItem>>((ref) async {
  final filters = ref.watch(_filtersProvider);
  final center = ref.watch(_currentLocationProvider);
  if (center == null) return [];
  final pulses = await ApiService.instance.getNearbyPulses(
    latitude: center.latitude,
    longitude: center.longitude,
    radiusKm: filters.radiusKm,
  );
  // Backend returns location inside location object
  final list = (pulses ?? []).where((p) {
    final loc = p['location'];
    return loc is Map && loc['latitude'] != null && loc['longitude'] != null;
  }).map((p) {
    final loc = p['location'] as Map<String, dynamic>?;
    return _PulseItem({
      ...p,
      'latitude': loc?['latitude'],
      'longitude': loc?['longitude'],
    });
  }).toList();
  return list;
});

// For user discovery we repurpose followers / following for demo
final _userItemsProvider =
    FutureProvider.autoDispose<List<_UserItem>>((ref) async {
  final filters = ref.watch(_filtersProvider);
  final center = ref.watch(_currentLocationProvider);
  if (center == null) return [];
  final users = await ApiService.instance.getNearbyUsers(
    latitude: center.latitude,
    longitude: center.longitude,
    radiusKm: filters.radiusKm,
  );
  return (users ?? []).where((u) => u['location'] is Map).map((u) {
    final loc = u['location'] as Map<String, dynamic>?;
    return _UserItem({
      ...u,
      'latitude': loc?['latitude'],
      'longitude': loc?['longitude'],
    });
  }).toList();
});

class _PulseDiscoveryMapPageState extends ConsumerState<PulseDiscoveryMapPage> {
  GoogleMapController? _controller;
  final Set<Marker> _markers = {};
  bool _darkMode = false;
  // bool _searching = false; // reserved for future textual filtering of markers
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  LatLng _center = const LatLng(37.7749, -122.4194); // default SF
  StreamSubscription? _pulseRefreshTimer;

  @override
  void initState() {
    super.initState();
    _initTimers();
    _initLocation();
  }

  void _initTimers() {
    // periodic refresh every 30s
    _pulseRefreshTimer =
        Stream.periodic(const Duration(seconds: 30)).listen((_) {
      if (!mounted) return;
      ref.invalidate(_pulseItemsProvider);
      ref.invalidate(_userItemsProvider);
    });
  }

  Future<void> _initLocation() async {
    // Placeholder: Use a default center until device location service integrated.
    // TODO: Integrate proper geolocation package (e.g., geolocator) with permissions.
    if (!mounted) return;
    // Hard-coded fallback center can be replaced by stored profile location.
    ref.read(_currentLocationProvider.notifier).state = _center;
    // Trigger initial loads
    await _rebuildClusters();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _pulseRefreshTimer?.cancel();
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _rebuildClusters() async {
    // Naive grid-based clustering to avoid dependency conflicts.
    final pulses = await ref.read(_pulseItemsProvider.future);
    final users = await ref.read(_userItemsProvider.future);
    final filters = ref.read(_filtersProvider);
    final List<dynamic> all = [];
    if (filters.showPulses) all.addAll(pulses);
    if (filters.showUsers) all.addAll(users);

    // Determine zoom-based bucket size
    final zoom = await _controller?.getZoomLevel() ?? 11.0;
    final bucketDeg = (14 - zoom).clamp(0, 12); // smaller at higher zoom
    final cellSize = 1 / math.pow(2, bucketDeg); // rough heuristic

    Map<String, List<dynamic>> buckets = {};
    for (final item in all) {
      final lat = item.location.latitude;
      final lng = item.location.longitude;
      final key = '${(lat / cellSize).floor()}_${(lng / cellSize).floor()}';
      buckets.putIfAbsent(key, () => []).add(item);
    }

    final Set<Marker> newMarkers = {};
    for (final entry in buckets.entries) {
      final items = entry.value;
      if (items.isEmpty) continue;
      if (items.length == 1) {
        final single = items.first;
        final isPulse = single is _PulseItem;
        final data = isPulse ? single.data : (single as _UserItem).data;
        final pos = single.location;
        final hue =
            isPulse ? BitmapDescriptor.hueRose : BitmapDescriptor.hueAzure;
        newMarkers.add(Marker(
          markerId: MarkerId('single_${data['id'] ?? data.hashCode}'),
          position: pos,
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          onTap: () => isPulse ? _openPulseSheet(data) : _openUserSheet(data),
        ));
      } else {
        // cluster marker
        double latSum = 0, lngSum = 0;
        for (final it in items) {
          latSum += it.location.latitude;
          lngSum += it.location.longitude;
        }
        final center = LatLng(latSum / items.length, lngSum / items.length);
        newMarkers.add(Marker(
          markerId: MarkerId('cluster_${entry.key}_${items.length}'),
          position: center,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          infoWindow: InfoWindow(title: '${items.length} nearby'),
          onTap: () async {
            // Zoom in when tapping a cluster
            final currentZoom = await _controller?.getZoomLevel() ?? 11;
            _controller?.animateCamera(CameraUpdate.newCameraPosition(
              CameraPosition(target: center, zoom: currentZoom + 2),
            ));
          },
        ));
      }
    }
    setState(() {
      _markers
        ..clear()
        ..addAll(newMarkers);
    });
  }

  void _openPulseSheet(Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final attendees = (data['participants'] as List?)?.length ??
            (data['participantCount'] ?? 0);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      data['title']?.toString() ?? 'Pulse',
                      style: FlutterFlowTheme.of(context).titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.open_in_new_rounded),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      context.pushNamed(
                        PulseDetailPage.routeName,
                        pathParameters: {'id': data['id']?.toString() ?? ''},
                        extra: {'pulse': data},
                      );
                    },
                  )
                ],
              ),
              const SizedBox(height: 4),
              Text('${data['location'] ?? 'Unknown location'}'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                children: [
                  _ActionChip(
                      icon: Icons.group_add_rounded,
                      label: 'Join',
                      onTap: () async {
                        final id = data['id']?.toString();
                        if (id != null) await ApiService.instance.joinPulse(id);
                      }),
                  _ActionChip(
                      icon: Icons.forum_rounded,
                      label: 'Message',
                      onTap: () async {
                        final id = data['id']?.toString();
                        if (id != null) {
                          final chat =
                              await ApiService.instance.getPulseChat(id);
                          if (chat != null) {
                            // navigate to messages hub then open chat? Out of scope minimal stub.
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Pulse chat opened (stub)')));
                          }
                        }
                      }),
                  _ActionChip(
                      icon: Icons.info_outline_rounded,
                      label: 'Details',
                      onTap: () {
                        context.pushNamed(
                          PulseDetailPage.routeName,
                          pathParameters: {'id': data['id']?.toString() ?? ''},
                          extra: {'pulse': data},
                        );
                      }),
                ],
              ),
              const SizedBox(height: 12),
              Row(children: [
                Icon(Icons.local_fire_department_rounded,
                    color: Colors.orangeAccent),
                const SizedBox(width: 6),
                Text('$attendees active')
              ]),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _openUserSheet(Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final photo = data['profileImageUrl']?.toString() ?? '';
        final name = data['displayName']?.toString() ??
            (data['id']?.toString() ?? 'User');
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(
                    radius: 28,
                    backgroundImage: photo.isNotEmpty
                        ? CachedNetworkImageProvider(photo)
                        : null,
                    child: photo.isEmpty ? const Icon(Icons.person) : null),
                const SizedBox(width: 16),
                Expanded(
                    child: Text(name,
                        style: FlutterFlowTheme.of(context).titleMedium)),
                IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close_rounded))
              ]),
              const SizedBox(height: 12),
              if ((data['bio']?.toString() ?? '').isNotEmpty)
                Text(data['bio'].toString(),
                    style: FlutterFlowTheme.of(context).bodyMedium),
              const SizedBox(height: 12),
              Wrap(spacing: 12, children: [
                _ActionChip(
                    icon: Icons.person_add_alt_1_rounded,
                    label: 'Add Friend',
                    onTap: () {}),
                _ActionChip(
                    icon: Icons.message_rounded,
                    label: 'Message',
                    onTap: () {/* open DM */}),
                _ActionChip(
                    icon: Icons.share_location_rounded,
                    label: 'Shared Pulses',
                    onTap: () {/* future */}),
              ])
            ],
          ),
        );
      },
    );
  }

  void _onMapCreated(GoogleMapController c) async {
    _controller = c;
    await _rebuildClusters();
  }

  void _onCameraMove(CameraPosition p) {
    // Rebuild markers lazily while moving? skip for perf
  }

  void _onCameraIdle() {
    _rebuildClusters();
  }

  void _toggleTheme() {
    setState(() => _darkMode = !_darkMode);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      // reserved; could trigger backend search + recalc clusters
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final pulsesAsync = ref.watch(_pulseItemsProvider);
    final usersAsync = ref.watch(_userItemsProvider);
    final filters = ref.watch(_filtersProvider);

    // Rebuild cluster data when async data changes
    pulsesAsync.whenData((_) => _rebuildClusters());
    usersAsync.whenData((_) => _rebuildClusters());

    return Scaffold(
      backgroundColor: theme.primaryBackground,
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: _center, zoom: 11),
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              compassEnabled: false,
              zoomControlsEnabled: false,
              mapType: MapType.normal,
              onMapCreated: _onMapCreated,
              markers: _markers,
              onCameraMove: _onCameraMove,
              onCameraIdle: _onCameraIdle,
              trafficEnabled: false,
            ),
          ),
          // Search + filters bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  _buildTopBar(theme, filters),
                  const SizedBox(height: 8),
                  _buildChips(theme, filters),
                ],
              ),
            ),
          ),
          // Floating buttons
          Positioned(
            right: 16,
            bottom: 120,
            child: Column(
              children: [
                _RoundFab(
                    icon: Icons.center_focus_strong_rounded,
                    onTap: () async {
                      if (_controller == null) return;
                      await _controller!
                          .animateCamera(CameraUpdate.newLatLng(_center));
                    }),
                const SizedBox(height: 12),
                _RoundFab(
                    icon: _darkMode
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                    onTap: _toggleTheme),
                const SizedBox(height: 12),
                _RoundFab(
                    icon: Icons.add_location_alt_rounded,
                    onTap: () =>
                        context.pushNamed(CreatePulseWidget.routeName)),
              ],
            ),
          ),
          // Loading overlay
          if (pulsesAsync.isLoading || usersAsync.isLoading)
            const Positioned.fill(
                child: IgnorePointer(
                    child: Center(child: CircularProgressIndicator()))),
        ],
      ),
      bottomNavigationBar: const NavbarWidget(),
    );
  }

  Widget _buildTopBar(FlutterFlowTheme theme, _MapFilters filters) {
    return Container(
      decoration: BoxDecoration(
        color: theme.secondaryBackground.withOpacity(0.95),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                  hintText: 'Search pulses or friends',
                  border: InputBorder.none),
              onChanged: _onSearchChanged,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.filter_list_rounded),
            tooltip: 'Filters',
            onPressed: () => _openFiltersSheet(),
          ),
        ],
      ),
    );
  }

  Widget _buildChips(FlutterFlowTheme theme, _MapFilters filters) {
    return Row(
      children: [
        FilterChip(
          label: const Text('Events'),
          selected: filters.showPulses,
          onSelected: (_) => ref.read(_filtersProvider.notifier).togglePulses(),
        ),
        const SizedBox(width: 8),
        FilterChip(
          label: const Text('People'),
          selected: filters.showUsers,
          onSelected: (_) => ref.read(_filtersProvider.notifier).toggleUsers(),
        ),
        const SizedBox(width: 8),
        FilterChip(
          label: Text('${filters.radiusKm.toInt()} km'),
          selected: true,
          onSelected: (_) => _openFiltersSheet(),
        ),
      ],
    );
  }

  void _openFiltersSheet() {
    final filters = ref.read(_filtersProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        double radius = filters.radiusKm;
        return StatefulBuilder(builder: (ctx, setModal) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.filter_list_rounded),
                  const SizedBox(width: 8),
                  Text('Filters',
                      style: FlutterFlowTheme.of(context).titleMedium),
                  const Spacer(),
                  IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded))
                ]),
                const SizedBox(height: 12),
                Text('Distance radius (${radius.toStringAsFixed(0)} km)'),
                Slider(
                  value: radius,
                  min: 1,
                  max: 100,
                  divisions: 99,
                  label: '${radius.toStringAsFixed(0)} km',
                  onChanged: (v) => setModal(() => radius = v),
                  onChangeEnd: (v) =>
                      ref.read(_filtersProvider.notifier).setRadius(v),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Apply'),
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16))),
                )
              ],
            ),
          );
        });
      },
    );
  }
}

class _RoundFab extends StatelessWidget {
  const _RoundFab({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.primary,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 4))
          ],
        ),
        child: Icon(icon, color: Colors.white),
      ).animate().scale(duration: 300.ms, curve: Curves.easeOutBack),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
