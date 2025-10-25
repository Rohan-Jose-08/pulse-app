import '/backend/api_service.dart';
import '/components/navbar_widget.dart';
import '/components/joinpulse_widget.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/utils/location_formatter.dart';
import '/auth/base_auth_user_provider.dart';
import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../pulse_invitations/pulse_invitations_page.dart';
import 'search_model.dart';
export 'search_model.dart';

class SearchWidget extends StatefulWidget {
  const SearchWidget({super.key});

  static String routeName = 'Search';
  static String routePath = '/search';

  @override
  State<SearchWidget> createState() => _SearchWidgetState();
}

class _SearchWidgetState extends State<SearchWidget>
    with TickerProviderStateMixin {
  late SearchModel _model;

  // Data lists
  List<Map<String, dynamic>> _forYouPulses = [];
  List<Map<String, dynamic>> _trendingPulses = [];
  List<Map<String, dynamic>> _nearbyPulses = [];
  List<Map<String, dynamic>> _allPulses = [];
  List<String> _categories = [];
  String _selectedCategory = 'All';

  // Loading states
  bool _isLoadingForYou = true;
  bool _isLoadingTrending = true;
  bool _isLoadingNearby = true;
  bool _isLoadingAll = true;

  // Controllers
  final ScrollController _mainScrollController = ScrollController();
  final PageController _storiesController =
      PageController(viewportFraction: 0.85);
  Timer? _storiesTimer;
  int _currentStoryIndex = 0;

  // Animation controllers
  late AnimationController _headerAnimationController;
  late Animation<double> _headerAnimation;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  // Helper to derive a short human-friendly location string from the pulse data.
  String _deriveLocation(dynamic rawLoc, Map<String, dynamic> pulse) {
    try {
      if (rawLoc is Map<String, dynamic>) {
        final name = (rawLoc['name'] as String?)?.trim();
        final city = (rawLoc['city'] as String?)?.trim();
        final country = (rawLoc['country'] as String?)?.trim();
        if (name != null && name.isNotEmpty) {
          final parts = [name, city]
              .whereType<String>()
              .where((e) => e.isNotEmpty)
              .take(2)
              .join(', ');
          if (parts.isNotEmpty) return parts;
        }
        final parts = [city, country]
            .whereType<String>()
            .where((e) => e.isNotEmpty)
            .toList();
        if (parts.isNotEmpty) return parts.join(', ');
        // fallback to lat/lng inside object
        final lat = rawLoc['latitude'];
        final lng = rawLoc['longitude'];
        if (lat is num && lng is num) {
          return '${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';
        }
      } else if (rawLoc is String && rawLoc.trim().isNotEmpty) {
        return rawLoc;
      }
      // legacy flat fields
      final lat = pulse['latitude'];
      final lng = pulse['longitude'];
      if (lat is num && lng is num) {
        return '${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';
      }
    } catch (_) {
      // swallow formatting errors, provide default
    }
    return 'Location TBD';
  }

  // Helper function to check if pulse is expired
  String _getPulseStatus(Map<String, dynamic> pulse) {
    try {
      final now = DateTime.now();
      final activeFromStr = pulse['activeFrom']?.toString();
      final activeUntilStr = pulse['activeUntil']?.toString();

      if (activeUntilStr != null && activeUntilStr.isNotEmpty) {
        final activeUntil = DateTime.tryParse(activeUntilStr);
        if (activeUntil != null && now.isAfter(activeUntil)) {
          return 'ENDED';
        }
      }

      if (activeFromStr != null && activeFromStr.isNotEmpty) {
        final activeFrom = DateTime.tryParse(activeFromStr);
        if (activeFrom != null) {
          if (now.isBefore(activeFrom)) {
            return 'SOON';
          }
          if (activeUntilStr != null && activeUntilStr.isNotEmpty) {
            final activeUntil = DateTime.tryParse(activeUntilStr);
            if (activeUntil != null &&
                now.isAfter(activeFrom) &&
                now.isBefore(activeUntil)) {
              return 'LIVE';
            }
          } else {
            // If no activeUntil, check if activeFrom is in the past
            if (now.isAfter(activeFrom)) {
              return 'LIVE';
            }
          }
        }
      }
    } catch (_) {
      // Error parsing dates, return LIVE as default
    }
    return 'LIVE'; // Default status
  }

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => SearchModel());

    // Initialize animation controllers
    _headerAnimationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800),
    );

    _headerAnimation = CurvedAnimation(
      parent: _headerAnimationController,
      curve: Curves.easeOutCubic,
    );

    // Start animations
    _headerAnimationController.forward();

    // Initialize data
    _initializeData();

    // Start stories auto-scroll
    _startStoriesTimer();

    // Add scroll listener for parallax effects
    _mainScrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  void _initializeData() {
    _fetchForYouPulses();
    _fetchTrendingPulses();
    _fetchNearbyPulses();
    _fetchAllPulses();
    _fetchCategories();
  }

  void _startStoriesTimer() {
    _storiesTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_currentStoryIndex < 4) {
        setState(() {
          _currentStoryIndex++;
        });
        if (mounted && _storiesController.hasClients) {
          _storiesController.animateToPage(
            _currentStoryIndex,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      } else {
        setState(() {
          _currentStoryIndex = 0;
        });
        if (mounted && _storiesController.hasClients) {
          _storiesController.animateToPage(
            0,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      }
    });
  }

  void _onScroll() {
    // Add any scroll-based animations here
  }

  Future<void> _fetchForYouPulses() async {
    try {
      setState(() => _isLoadingForYou = true);
      final profile = await ApiService.instance.getUserProfile();
      final lat = profile != null ? profile['locationLatitude'] as num? : null;
      final lng = profile != null ? profile['locationLongitude'] as num? : null;
      final pulses = await ApiService.instance.getPulses(
        latitude: lat?.toDouble(),
        longitude: lng?.toDouble(),
        radiusKm: 50,
      );

      if (pulses != null && pulses.isNotEmpty) {
        setState(() {
          _forYouPulses = pulses.take(5).toList();
        });
      }
    } catch (e) {
      print('Error fetching for you pulses: $e');
    } finally {
      setState(() => _isLoadingForYou = false);
    }
  }

  Future<void> _fetchTrendingPulses() async {
    try {
      setState(() => _isLoadingTrending = true);
      final pulses = await ApiService.instance.getPulses(); // no coord bias

      if (pulses != null && pulses.isNotEmpty) {
        final trending = List<Map<String, dynamic>>.from(pulses)..shuffle();
        setState(() {
          _trendingPulses = trending.take(10).toList();
        });
      }
    } catch (e) {
      print('Error fetching trending pulses: $e');
    } finally {
      setState(() => _isLoadingTrending = false);
    }
  }

  Future<void> _fetchNearbyPulses() async {
    try {
      setState(() => _isLoadingNearby = true);
      // Pull structured location coordinates if available from profile (backend will create Location rows on updates)
      final profile = await ApiService.instance.getUserProfile();
      final lat = profile != null ? profile['locationLatitude'] as num? : null;
      final lng = profile != null ? profile['locationLongitude'] as num? : null;
      if (lat != null && lng != null) {
        final pulses = await ApiService.instance.getNearbyPulses(
          latitude: lat.toDouble(),
          longitude: lng.toDouble(),
          radiusKm: 10,
        );
        if (pulses != null) {
          setState(() {
            _nearbyPulses = pulses.take(12).toList();
          });
        } else {
          setState(() {
            _nearbyPulses = [];
          });
        }
      } else {
        print('No structured coordinates available; skipping nearby pulses');
        setState(() {
          _nearbyPulses = [];
        });
      }
    } catch (e) {
      print('Error fetching nearby pulses: $e');
    } finally {
      setState(() => _isLoadingNearby = false);
    }
  }

  Future<void> _fetchAllPulses() async {
    try {
      setState(() => _isLoadingAll = true);
      final profile = await ApiService.instance.getUserProfile();
      final lat = profile != null ? profile['locationLatitude'] as num? : null;
      final lng = profile != null ? profile['locationLongitude'] as num? : null;
      final pulses = await ApiService.instance.getPulses(
        tags: _selectedCategory != 'All' ? [_selectedCategory] : null,
        latitude: lat?.toDouble(),
        longitude: lng?.toDouble(),
        radiusKm: 100,
      );

      if (pulses != null) {
        setState(() {
          _allPulses = pulses;
        });
      }
    } catch (e) {
      print('Error fetching all pulses: $e');
    } finally {
      setState(() => _isLoadingAll = false);
    }
  }

  Future<void> _fetchCategories() async {
    try {
      final tags = await ApiService.instance.getTags();
      if (tags != null) {
        setState(() {
          _categories = ['All', ...tags];
        });
      }
    } catch (e) {
      print('Error fetching categories: $e');
    }
  }

  Future<void> _refreshAll() async {
    await Haptics.vibrate(HapticsType.medium);
    await Future.wait([
      _fetchForYouPulses(),
      _fetchTrendingPulses(),
      _fetchNearbyPulses(),
      _fetchAllPulses(),
    ]);
  }

  void _showSearchModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).secondaryBackground,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color:
                    FlutterFlowTheme.of(context).secondaryText.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search events, tags, or users...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (value) {
                  // Implement search functionality
                },
              ),
            ),
            Expanded(
              child: Center(
                child: Text('Search results will appear here'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerList(bool isLarge) {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: 16),
      itemCount: 3,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: FlutterFlowTheme.of(context).alternate,
          highlightColor: FlutterFlowTheme.of(context).secondaryBackground,
          child: Container(
            width: isLarge ? 300 : 160,
            height: isLarge ? 280 : 200,
            margin: EdgeInsets.only(right: isLarge ? 16 : 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(isLarge ? 24 : 16),
            ),
          ),
        );
      },
    );
  }

  Widget _buildParticipantAvatars(Map<String, dynamic> pulse) {
    final participants = pulse['participants'] as List<dynamic>? ?? [];
    final displayCount = participants.length > 3 ? 3 : participants.length;

    return Row(
      children: List.generate(displayCount, (index) {
        return Container(
          width: 24,
          height: 24,
          margin: EdgeInsets.only(left: index > 0 ? -8 : 0),
          decoration: BoxDecoration(
            color: FlutterFlowTheme.of(context).primary.withOpacity(0.3),
            shape: BoxShape.circle,
            border: Border.all(
              color: FlutterFlowTheme.of(context).secondaryBackground,
              width: 2,
            ),
          ),
          child: Center(
            child: Icon(
              Icons.person,
              size: 12,
              color: FlutterFlowTheme.of(context).primary,
            ),
          ),
        );
      }),
    );
  }

  bool _isCurrentUserParticipant(Map<String, dynamic> pulse) {
    if (currentUser?.uid == null) return false;

    final participants = pulse['participants'] as List<dynamic>? ?? [];
    return participants.any((participant) =>
        participant['id'] == currentUser?.uid ||
        participant['firebaseUid'] == currentUser?.uid);
  }

  bool _isCurrentUserAuthor(Map<String, dynamic> pulse) {
    if (currentUser?.uid == null) return false;

    final author = pulse['author'] as Map<String, dynamic>?;
    return author != null &&
        (author['id'] == currentUser?.uid ||
            author['firebaseUid'] == currentUser?.uid);
  }

  bool _shouldShowJoinButton(Map<String, dynamic> pulse) {
    // Don't show join button if user is not logged in
    if (currentUser?.uid == null) return false;

    // Don't show join button if user is already a participant
    if (_isCurrentUserParticipant(pulse)) return false;

    // Don't show join button if user is the author
    if (_isCurrentUserAuthor(pulse)) return false;

    // Only show join button for public pulses
    return pulse['isPublic'] == true;
  }

  void _showJoinPulseDialog(Map<String, dynamic> pulse) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => JoinpulseWidget(
        pulse: pulse,
        onJoinSuccess: () {
          _refreshAll();
        },
      ),
    );
  }

  void _navigateToPulseDetail(Map<String, dynamic> pulse) {
    final pulseId = pulse['id'] as String?;
    if (pulseId == null || pulseId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid pulse data'),
          backgroundColor: FlutterFlowTheme.of(context).error,
        ),
      );
      return;
    }

    // Navigate to pulse detail page
    context.goNamed(
      'PulseDetail',
      pathParameters: {'id': pulseId},
      extra: {'pulse': pulse},
    );
  }

  @override
  void dispose() {
    _storiesTimer?.cancel();
    _model.dispose();
    _mainScrollController.dispose();
    _storiesController.dispose();
    _headerAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        body: SafeArea(
          top: true,
          child: Stack(
            children: [
              // Main content
              RefreshIndicator(
                onRefresh: _refreshAll,
                color: FlutterFlowTheme.of(context).primary,
                backgroundColor:
                    FlutterFlowTheme.of(context).secondaryBackground,
                child: CustomScrollView(
                  controller: _mainScrollController,
                  physics: BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  slivers: [
                    // Header
                    SliverToBoxAdapter(
                      child: _buildHeader(),
                    ),

                    // Stories Section
                    SliverToBoxAdapter(
                      child: _buildStoriesSection(),
                    ),

                    // For You Section
                    SliverToBoxAdapter(
                      child: _buildForYouSection(),
                    ),

                    // Trending Section
                    SliverToBoxAdapter(
                      child: _buildTrendingSection(),
                    ),

                    // Nearby Section
                    SliverToBoxAdapter(
                      child: _buildNearbySection(),
                    ),

                    // Categories Filter
                    SliverToBoxAdapter(
                      child: _buildCategoriesFilter(),
                    ),

                    // All Pulses Grid
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                      sliver: _buildAllPulsesGrid(),
                    ),

                    // Bottom padding for navbar
                    SliverToBoxAdapter(
                      child: SizedBox(height: 100.0),
                    ),
                  ],
                ),
              ),
              // Navbar
              Align(
                alignment: AlignmentDirectional(0.0, 1.0),
                child: wrapWithModel(
                  model: _model.navbarModel,
                  updateCallback: () => safeSetState(() {}),
                  child: NavbarWidget(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return AnimatedBuilder(
      animation: _headerAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, -20 * (1 - _headerAnimation.value)),
          child: Opacity(
            opacity: _headerAnimation.value,
            child: Container(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Explore',
                        style:
                            FlutterFlowTheme.of(context).displaySmall.override(
                                  font: GoogleFonts.interTight(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  fontSize: 32,
                                ),
                      )
                          .animate()
                          .fadeIn(duration: 600.ms, delay: 200.ms)
                          .slideX(begin: -0.2, end: 0),
                      SizedBox(height: 4),
                      Text(
                        'Discover amazing events',
                        style: FlutterFlowTheme.of(context).bodyLarge.override(
                              font: GoogleFonts.inter(),
                              color: FlutterFlowTheme.of(context).secondaryText,
                            ),
                      )
                          .animate()
                          .fadeIn(duration: 600.ms, delay: 400.ms)
                          .slideX(begin: -0.2, end: 0),
                    ],
                  ),

                  // Actions: Invitations + Search
                  Row(
                    children: [
                      Container(
                        margin: EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color:
                              FlutterFlowTheme.of(context).secondaryBackground,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 10,
                              color: Colors.black.withOpacity(0.1),
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: Icon(
                            Icons.mail_outline_rounded,
                            color: FlutterFlowTheme.of(context).primary,
                            size: 24,
                          ),
                          tooltip: 'Invitations',
                          onPressed: () async {
                            await Haptics.vibrate(HapticsType.selection);
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const PulseInvitationsPage(),
                              ),
                            );
                          },
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color:
                              FlutterFlowTheme.of(context).secondaryBackground,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 10,
                              color: Colors.black.withOpacity(0.1),
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: Icon(
                            Icons.search_rounded,
                            color: FlutterFlowTheme.of(context).primaryText,
                            size: 24,
                          ),
                          onPressed: () async {
                            await Haptics.vibrate(HapticsType.selection);
                            _showSearchModal();
                          },
                        ),
                      ),
                    ],
                  )
                      .animate()
                      .scale(
                          begin: Offset(0, 0),
                          end: Offset(1, 1),
                          duration: 600.ms,
                          delay: 600.ms)
                      .then()
                      .shimmer(duration: 2000.ms, delay: 1000.ms),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStoriesSection() {
    return Container(
      height: 120,
      margin: EdgeInsets.only(top: 16),
      child: PageView.builder(
        controller: _storiesController,
        itemCount: 5,
        itemBuilder: (context, index) {
          return _buildStoryCard(index);
        },
      ),
    )
        .animate()
        .fadeIn(duration: 600.ms, delay: 800.ms)
        .slideY(begin: 0.1, end: 0);
  }

  Widget _buildStoryCard(int index) {
    final isActive = index == _currentStoryIndex;
    final stories = [
      {
        'title': 'Featured Events',
        'icon': Icons.star_rounded,
        'color': Colors.amber
      },
      {
        'title': 'This Weekend',
        'icon': Icons.weekend_rounded,
        'color': Colors.purple
      },
      {
        'title': 'Free Events',
        'icon': Icons.attach_money_rounded,
        'color': Colors.green
      },
      {
        'title': 'New Pulses',
        'icon': Icons.new_releases_rounded,
        'color': Colors.red
      },
      {
        'title': 'Popular Now',
        'icon': Icons.trending_up_rounded,
        'color': Colors.blue
      },
    ];

    final story = stories[index];

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 8),
      child: InkWell(
        onTap: () async {
          await Haptics.vibrate(HapticsType.selection);
          setState(() {
            _currentStoryIndex = index;
          });
          _storiesController.animateToPage(
            index,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                (story['color'] as Color).withOpacity(0.8),
                (story['color'] as Color).withOpacity(0.6),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: isActive
                ? Border.all(
                    color: Colors.white,
                    width: 3,
                  )
                : null,
            boxShadow: [
              BoxShadow(
                blurRadius: 15,
                color: (story['color'] as Color).withOpacity(0.3),
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              if (isActive)
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: LinearProgressIndicator(
                    value: 1.0,
                    backgroundColor: Colors.white.withOpacity(0.3),
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  )
                      .animate(onPlay: (controller) => controller.repeat())
                      .shimmer(duration: 5000.ms),
                ),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      story['icon'] as IconData,
                      color: Colors.white,
                      size: 40,
                    ),
                    SizedBox(height: 8),
                    Text(
                      story['title'] as String,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForYouSection() {
    return Container(
      margin: EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: FlutterFlowTheme.of(context).primary,
                      size: 24,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'For You',
                      style:
                          FlutterFlowTheme.of(context).headlineSmall.override(
                                font: GoogleFonts.interTight(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () async {
                    await Haptics.vibrate(HapticsType.selection);
                  },
                  child: Text(
                    'See all',
                    style: FlutterFlowTheme.of(context).bodyMedium.override(
                          font: GoogleFonts.inter(),
                          color: FlutterFlowTheme.of(context).primary,
                        ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16),
          Container(
            height: 280,
            child: _isLoadingForYou
                ? _buildShimmerList(true)
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _forYouPulses.length,
                    itemBuilder: (context, index) {
                      return _buildForYouCard(_forYouPulses[index], index);
                    },
                  ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 600.ms, delay: 1000.ms);
  }

  Widget _buildForYouCard(Map<String, dynamic> pulse, int index) {
    final pulseStatus = _getPulseStatus(pulse);
    final isExpired = pulseStatus == 'ENDED';

    return Container(
      width: 300,
      margin: EdgeInsets.only(right: 16),
      child: Opacity(
        opacity: isExpired ? 0.5 : 1.0,
        child: InkWell(
          onTap: () async {
            await Haptics.vibrate(HapticsType.selection);
            _navigateToPulseDetail(pulse);
          },
          borderRadius: BorderRadius.circular(24),
          child: Container(
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context).secondaryBackground,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  blurRadius: 20,
                  color: Colors.black.withOpacity(0.1),
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image with gradient overlay
                Container(
                  height: 160,
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(24),
                        ),
                        child: Container(
                          width: double.infinity,
                          height: 160,
                          color: isExpired
                              ? Colors.grey.withOpacity(0.3)
                              : FlutterFlowTheme.of(context)
                                  .primary
                                  .withOpacity(0.3),
                          child: ColorFiltered(
                            colorFilter: isExpired
                                ? ColorFilter.mode(
                                    Colors.grey,
                                    BlendMode.saturation,
                                  )
                                : ColorFilter.mode(
                                    Colors.transparent,
                                    BlendMode.multiply,
                                  ),
                            child: pulse['imageUrl'] != null
                                ? Image.network(
                                    pulse['imageUrl'],
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Center(
                                        child: Icon(
                                          Icons.event_rounded,
                                          size: 60,
                                          color: Colors.white,
                                        ),
                                      );
                                    },
                                  )
                                : Center(
                                    child: Icon(
                                      Icons.event_rounded,
                                      size: 60,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      // Gradient overlay
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(24),
                              topRight: Radius.circular(24),
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.7),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Tags on image
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isExpired
                                ? Colors.grey.withOpacity(0.9)
                                : Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isExpired
                                    ? Icons.event_busy_rounded
                                    : Icons.auto_awesome,
                                size: 16,
                                color: isExpired
                                    ? Colors.white
                                    : FlutterFlowTheme.of(context).primary,
                              ),
                              SizedBox(width: 4),
                              Text(
                                isExpired ? 'Ended' : 'Recommended',
                                style: TextStyle(
                                  color: isExpired
                                      ? Colors.white
                                      : FlutterFlowTheme.of(context).primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Save button
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: Icon(
                              Icons.bookmark_border_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            onPressed: () async {
                              await Haptics.vibrate(HapticsType.selection);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Content
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pulse['title'] ?? 'Untitled Event',
                              style: FlutterFlowTheme.of(context)
                                  .titleMedium
                                  .override(
                                    font: GoogleFonts.interTight(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on_outlined,
                                  size: 16,
                                  color: FlutterFlowTheme.of(context)
                                      .secondaryText,
                                ),
                                SizedBox(width: 4),
                                Expanded(
                                  child: FutureBuilder<String?>(
                                    future: () async {
                                      final lat = pulse['latitude'] is String
                                          ? double.tryParse(pulse['latitude'])
                                          : pulse['latitude']?.toDouble();
                                      final lng = pulse['longitude'] is String
                                          ? double.tryParse(pulse['longitude'])
                                          : pulse['longitude']?.toDouble();

                                      if (lat != null && lng != null) {
                                        return await LocationFormatter
                                            .getAddressFromCoordinates(
                                          latitude: lat,
                                          longitude: lng,
                                        );
                                      }
                                      return null;
                                    }(),
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState ==
                                          ConnectionState.waiting) {
                                        return Text(
                                          'Loading location...',
                                          style: FlutterFlowTheme.of(context)
                                              .bodySmall
                                              .override(
                                                font: GoogleFonts.inter(),
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .secondaryText,
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        );
                                      }

                                      String derivedLocationString() {
                                        final loc = pulse['location'];
                                        if (loc is Map<String, dynamic>) {
                                          final name =
                                              (loc['name'] as String?)?.trim();
                                          final city =
                                              (loc['city'] as String?)?.trim();
                                          final country =
                                              (loc['country'] as String?)
                                                  ?.trim();
                                          if (name != null && name.isNotEmpty) {
                                            final parts = [name, city]
                                                .whereType<String>()
                                                .where((e) => e.isNotEmpty)
                                                .take(2)
                                                .join(', ');
                                            if (parts.isNotEmpty) return parts;
                                          }
                                          final parts = [city, country]
                                              .whereType<String>()
                                              .where((e) => e.isNotEmpty)
                                              .toList();
                                          if (parts.isNotEmpty)
                                            return parts.join(', ');
                                        } else if (loc is String &&
                                            loc.isNotEmpty) {
                                          return loc;
                                        }
                                        return 'Location TBD';
                                      }

                                      final address = snapshot.data ??
                                          derivedLocationString();
                                      return Text(
                                        address,
                                        style: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .override(
                                              font: GoogleFonts.inter(),
                                              color:
                                                  FlutterFlowTheme.of(context)
                                                      .secondaryText,
                                            ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Participant avatars
                            Row(
                              children: [
                                _buildParticipantAvatars(pulse),
                                SizedBox(width: 8),
                                Text(
                                  '${pulse['participants']?.length ?? 0} going',
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                        font: GoogleFonts.inter(),
                                        color: FlutterFlowTheme.of(context)
                                            .secondaryText,
                                      ),
                                ),
                              ],
                            ),
                            // Join button
                            if (_shouldShowJoinButton(pulse))
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      FlutterFlowTheme.of(context).primary,
                                      FlutterFlowTheme.of(context).secondary,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () async {
                                      await Haptics.vibrate(HapticsType.medium);
                                      _showJoinPulseDialog(pulse);
                                    },
                                    borderRadius: BorderRadius.circular(20),
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 8),
                                      child: Text(
                                        'Join',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            else if (_isCurrentUserParticipant(pulse) ||
                                _isCurrentUserAuthor(pulse))
                              Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: FlutterFlowTheme.of(context)
                                      .success
                                      .withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: FlutterFlowTheme.of(context).success,
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  'Joined',
                                  style: TextStyle(
                                    color: FlutterFlowTheme.of(context).success,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 600.ms, delay: (200 * index).ms)
        .slideX(begin: 0.2, end: 0);
  }

  Widget _buildTrendingSection() {
    return Container(
      margin: EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.trending_up_rounded,
                      color: Colors.red,
                      size: 24,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Trending Now',
                      style:
                          FlutterFlowTheme.of(context).headlineSmall.override(
                                font: GoogleFonts.interTight(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () async {
                    await Haptics.vibrate(HapticsType.selection);
                  },
                  child: Text(
                    'See all',
                    style: FlutterFlowTheme.of(context).bodyMedium.override(
                          font: GoogleFonts.inter(),
                          color: FlutterFlowTheme.of(context).primary,
                        ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16),
          Container(
            height: 200,
            child: _isLoadingTrending
                ? _buildShimmerList(false)
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _trendingPulses.length,
                    itemBuilder: (context, index) {
                      return _buildTrendingCard(_trendingPulses[index], index);
                    },
                  ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 600.ms, delay: 1200.ms);
  }

  Widget _buildTrendingCard(Map<String, dynamic> pulse, int index) {
    final pulseStatus = _getPulseStatus(pulse);
    final isExpired = pulseStatus == 'ENDED';

    return Container(
      width: 160,
      margin: EdgeInsets.only(right: 12),
      child: Opacity(
        opacity: isExpired ? 0.5 : 1.0,
        child: InkWell(
          onTap: () async {
            await Haptics.vibrate(HapticsType.selection);
            _navigateToPulseDetail(pulse);
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isExpired
                    ? [
                        Colors.grey.withOpacity(0.8),
                        Colors.grey.shade700.withOpacity(0.8),
                      ]
                    : [
                        FlutterFlowTheme.of(context).primary.withOpacity(0.8),
                        FlutterFlowTheme.of(context).secondary.withOpacity(0.8),
                      ],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  blurRadius: 15,
                  color: isExpired
                      ? Colors.grey.withOpacity(0.3)
                      : FlutterFlowTheme.of(context).primary.withOpacity(0.3),
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Trending/Expired badge
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isExpired ? Colors.grey.shade700 : Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isExpired
                              ? Icons.event_busy_rounded
                              : Icons.trending_up,
                          size: 12,
                          color: Colors.white,
                        ),
                        SizedBox(width: 2),
                        Text(
                          isExpired ? 'ENDED' : 'HOT',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Content
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        pulse['title'] ?? 'Untitled Event',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: Colors.white.withOpacity(0.8),
                          ),
                          SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _deriveLocation(pulse['location'], pulse),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${pulse['participants']?.length ?? 0} going',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (_shouldShowJoinButton(pulse))
                            InkWell(
                              onTap: () async {
                                await Haptics.vibrate(HapticsType.medium);
                                _showJoinPulseDialog(pulse);
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Join',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            )
                          else if (_isCurrentUserParticipant(pulse) ||
                              _isCurrentUserAuthor(pulse))
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.green,
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                'Joined',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 600.ms, delay: (100 * index).ms)
        .slideX(begin: 0.1, end: 0);
  }

  Widget _buildNearbySection() {
    return Container(
      margin: EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      color: Colors.green,
                      size: 24,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Nearby Events',
                      style:
                          FlutterFlowTheme.of(context).headlineSmall.override(
                                font: GoogleFonts.interTight(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () async {
                    await Haptics.vibrate(HapticsType.selection);
                  },
                  child: Text(
                    'See all',
                    style: FlutterFlowTheme.of(context).bodyMedium.override(
                          font: GoogleFonts.inter(),
                          color: FlutterFlowTheme.of(context).primary,
                        ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16),
          Container(
            height: 160,
            child: _isLoadingNearby
                ? _buildShimmerList(false)
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _nearbyPulses.length,
                    itemBuilder: (context, index) {
                      return _buildNearbyCard(_nearbyPulses[index], index);
                    },
                  ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 600.ms, delay: 1400.ms);
  }

  Widget _buildNearbyCard(Map<String, dynamic> pulse, int index) {
    final pulseStatus = _getPulseStatus(pulse);
    final isExpired = pulseStatus == 'ENDED';

    return Container(
      width: 200,
      margin: EdgeInsets.only(right: 12),
      child: Opacity(
        opacity: isExpired ? 0.5 : 1.0,
        child: InkWell(
          onTap: () async {
            await Haptics.vibrate(HapticsType.selection);
            _navigateToPulseDetail(pulse);
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context).secondaryBackground,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  blurRadius: 10,
                  color: Colors.black.withOpacity(0.1),
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isExpired
                                  ? Icons.event_busy_rounded
                                  : Icons.location_on,
                              size: 12,
                              color: isExpired
                                  ? Colors.grey.shade700
                                  : Colors.green,
                            ),
                            SizedBox(width: 2),
                            Text(
                              isExpired ? 'ENDED' : '0.5 mi',
                              style: TextStyle(
                                color: isExpired
                                    ? Colors.grey.shade700
                                    : Colors.green,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.bookmark_border,
                        size: 20,
                        color: FlutterFlowTheme.of(context).secondaryText,
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    pulse['title'] ?? 'Untitled Event',
                    style: FlutterFlowTheme.of(context).titleSmall.override(
                          font: GoogleFonts.interTight(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4),
                  Text(
                    _deriveLocation(pulse['location'], pulse),
                    style: FlutterFlowTheme.of(context).bodySmall.override(
                          font: GoogleFonts.inter(),
                          color: FlutterFlowTheme.of(context).secondaryText,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          _buildParticipantAvatars(pulse),
                          SizedBox(width: 4),
                          Text(
                            '${pulse['participants']?.length ?? 0}',
                            style:
                                FlutterFlowTheme.of(context).bodySmall.override(
                                      font: GoogleFonts.inter(),
                                      color: FlutterFlowTheme.of(context)
                                          .secondaryText,
                                    ),
                          ),
                        ],
                      ),
                      if (_shouldShowJoinButton(pulse))
                        InkWell(
                          onTap: () async {
                            await Haptics.vibrate(HapticsType.medium);
                            _showJoinPulseDialog(pulse);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: FlutterFlowTheme.of(context).primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Join',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      else if (_isCurrentUserParticipant(pulse) ||
                          _isCurrentUserAuthor(pulse))
                        Container(
                          padding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: FlutterFlowTheme.of(context)
                                .success
                                .withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: FlutterFlowTheme.of(context).success,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            'Joined',
                            style: TextStyle(
                              color: FlutterFlowTheme.of(context).success,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 600.ms, delay: (100 * index).ms)
        .slideX(begin: 0.1, end: 0);
  }

  Widget _buildCategoriesFilter() {
    return Container(
      margin: EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Browse by Category',
              style: FlutterFlowTheme.of(context).headlineSmall.override(
                    font: GoogleFonts.interTight(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
            ),
          ),
          SizedBox(height: 16),
          Container(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = category == _selectedCategory;

                return Container(
                  margin: EdgeInsets.only(right: 12),
                  child: FilterChip(
                    label: Text(category),
                    selected: isSelected,
                    onSelected: (selected) async {
                      await Haptics.vibrate(HapticsType.selection);
                      setState(() {
                        _selectedCategory = category;
                      });
                      _fetchAllPulses();
                    },
                    backgroundColor:
                        FlutterFlowTheme.of(context).secondaryBackground,
                    selectedColor:
                        FlutterFlowTheme.of(context).primary.withOpacity(0.2),
                    checkmarkColor: FlutterFlowTheme.of(context).primary,
                    labelStyle: FlutterFlowTheme.of(context).bodySmall.override(
                          font: GoogleFonts.inter(),
                          color: isSelected
                              ? FlutterFlowTheme.of(context).primary
                              : FlutterFlowTheme.of(context).secondaryText,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                    side: BorderSide(
                      color: isSelected
                          ? FlutterFlowTheme.of(context).primary
                          : FlutterFlowTheme.of(context).alternate,
                      width: isSelected ? 2 : 1,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: isSelected ? 4 : 0,
                    pressElevation: 8,
                  ).animate().scale(
                        begin: Offset(0.95, 0.95),
                        end: Offset(1, 1),
                        duration: 200.ms,
                      ),
                );
              },
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 600.ms, delay: 1600.ms);
  }

  Widget _buildAllPulsesGrid() {
    if (_isLoadingAll) {
      return SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.8,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            return Shimmer.fromColors(
              baseColor: FlutterFlowTheme.of(context).alternate,
              highlightColor: FlutterFlowTheme.of(context).secondaryBackground,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            );
          },
          childCount: 6,
        ),
      );
    }

    if (_allPulses.isEmpty) {
      return SliverToBoxAdapter(
        child: Container(
          height: 200,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.search_off_rounded,
                  size: 60,
                  color: FlutterFlowTheme.of(context).secondaryText,
                ),
                SizedBox(height: 16),
                Text(
                  'No events found',
                  style: FlutterFlowTheme.of(context).titleMedium,
                ),
                SizedBox(height: 8),
                Text(
                  'Try adjusting your filters',
                  style: FlutterFlowTheme.of(context).bodySmall.override(
                        font: GoogleFonts.inter(),
                        color: FlutterFlowTheme.of(context).secondaryText,
                      ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.8,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final pulse = _allPulses[index];
          return AnimationConfiguration.staggeredGrid(
            position: index,
            duration: const Duration(milliseconds: 600),
            columnCount: 2,
            child: SlideAnimation(
              verticalOffset: 50.0,
              child: FadeInAnimation(
                child: _buildGridPulseCard(pulse, index),
              ),
            ),
          );
        },
        childCount: _allPulses.length,
      ),
    );
  }

  Widget _buildGridPulseCard(Map<String, dynamic> pulse, int index) {
    final pulseStatus = _getPulseStatus(pulse);
    final isExpired = pulseStatus == 'ENDED';

    return Opacity(
      opacity: isExpired ? 0.5 : 1.0,
      child: InkWell(
        onTap: () async {
          await Haptics.vibrate(HapticsType.selection);
          _navigateToPulseDetail(pulse);
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: FlutterFlowTheme.of(context).secondaryBackground,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                blurRadius: 10,
                color: Colors.black.withOpacity(0.1),
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image
              Expanded(
                flex: 3,
                child: Container(
                  width: double.infinity,
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                        child: Container(
                          width: double.infinity,
                          height: double.infinity,
                          color: isExpired
                              ? Colors.grey.withOpacity(0.3)
                              : FlutterFlowTheme.of(context)
                                  .primary
                                  .withOpacity(0.3),
                          child: ColorFiltered(
                            colorFilter: isExpired
                                ? ColorFilter.mode(
                                    Colors.grey,
                                    BlendMode.saturation,
                                  )
                                : ColorFilter.mode(
                                    Colors.transparent,
                                    BlendMode.multiply,
                                  ),
                            child: pulse['imageUrl'] != null
                                ? Image.network(
                                    pulse['imageUrl'],
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Center(
                                        child: Icon(
                                          Icons.event_rounded,
                                          size: 40,
                                          color: Colors.white,
                                        ),
                                      );
                                    },
                                  )
                                : Center(
                                    child: Icon(
                                      Icons.event_rounded,
                                      size: 40,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      // Expired badge
                      if (isExpired)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade700,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.event_busy_rounded,
                                  size: 12,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'ENDED',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // Content
              Expanded(
                flex: 2,
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pulse['title'] ?? 'Untitled Event',
                            style: FlutterFlowTheme.of(context)
                                .titleSmall
                                .override(
                                  font: GoogleFonts.interTight(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 12,
                                color:
                                    FlutterFlowTheme.of(context).secondaryText,
                              ),
                              SizedBox(width: 2),
                              Expanded(
                                child: Text(
                                  _deriveLocation(pulse['location'], pulse),
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                        font: GoogleFonts.inter(),
                                        color: FlutterFlowTheme.of(context)
                                            .secondaryText,
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${pulse['participants']?.length ?? 0} going',
                            style:
                                FlutterFlowTheme.of(context).bodySmall.override(
                                      font: GoogleFonts.inter(),
                                      color: FlutterFlowTheme.of(context)
                                          .secondaryText,
                                    ),
                          ),
                          if (_shouldShowJoinButton(pulse))
                            InkWell(
                              onTap: () async {
                                await Haptics.vibrate(HapticsType.medium);
                                _showJoinPulseDialog(pulse);
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: FlutterFlowTheme.of(context).primary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Join',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            )
                          else if (_isCurrentUserParticipant(pulse) ||
                              _isCurrentUserAuthor(pulse))
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: FlutterFlowTheme.of(context)
                                    .success
                                    .withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: FlutterFlowTheme.of(context).success,
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                'Joined',
                                style: TextStyle(
                                  color: FlutterFlowTheme.of(context).success,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
