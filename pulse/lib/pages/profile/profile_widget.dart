import '/backend/api_service.dart';
import '/components/pulse_card_widget_material.dart';
import '/components/navbar_widget.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'profile_model.dart';
import '/auth/firebase_auth/auth_util.dart';
import '/backend/storage_service.dart';
export 'profile_model.dart';

class ProfileWidget extends StatefulWidget {
  const ProfileWidget({super.key});

  static String routeName = 'Profile';
  static String routePath = '/profile';

  @override
  State<ProfileWidget> createState() => _ProfileWidgetState();
}

class _ProfileWidgetState extends State<ProfileWidget>
    with TickerProviderStateMixin {
  late ProfileModel _model;
  final scaffoldKey = GlobalKey<ScaffoldState>();
  late TabController _tabController;

  // Data states
  bool _loadingCreated = true;
  bool _loadingJoined = true;
  bool _loadingProfile = true;
  bool _loadingPosts = true;
  bool _loadingFollowers = true;
  bool _loadingFollowing = true;
  List<Map<String, dynamic>> _created = [];
  List<Map<String, dynamic>> _joined = [];
  List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _followers = [];
  List<Map<String, dynamic>> _following = [];

  // Profile data
  String? _displayName;
  String? _bio;
  String? _photoUrl;
  List<String> _interests = [];
  String? _location;
  DateTime? _joinDate;
  String? _phoneNumber;
  String? _gender;
  String? _occupation;
  String? _company;
  String? _education;
  List<String> _languages = [];
  String? _timezone;

  // Stats
  int _totalEvents = 0;
  int _totalConnections = 0;
  int _totalPosts = 0;
  int _followersCount = 0;
  int _followingCount = 0;

  // UI states
  bool _isEditing = false;
  bool _isFollowing = false;
  final ImagePicker _picker = ImagePicker();
  int _eventsFilterIndex = 0; // 0: Created, 1: Joined

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => ProfileModel());
    _tabController = TabController(length: 3, vsync: this);
    _initializeProfile();
  }

  Widget _buildSettingsDrawer(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Settings',
                style: theme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Log out'),
              onTap: () async {
                try {
                  await authManager.signOut();
                } catch (_) {}
                if (!mounted) return;
                // Close drawer first
                Navigator.of(context).pop();
                // Navigate to login
                context.go('/loginPage');
              },
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Text(
                'v1.0',
                style: theme.labelSmall,
              ),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _initializeProfile() async {
    setState(() => _loadingProfile = true);

    try {
      final user = currentUser;
      if (user != null) {
        _displayName =
            user.displayName ?? user.email?.split('@').first ?? 'Your Name';
        // Note: Firebase Auth doesn't provide creation time directly
        // We'll use current time as placeholder
        _joinDate = DateTime.now();

        // Load user profile from backend (includes Prisma profileImageUrl)
        await _loadUserProfile();
      }
    } catch (e) {
      print('Error initializing profile: $e');
    } finally {
      setState(() => _loadingProfile = false);
    }

    await Future.wait([
      _fetchCreatedPulses(),
      _fetchJoinedPulses(),
      _fetchMyPosts(),
      _fetchFollowers(),
      _fetchFollowing(),
    ]);
  }

  Future<void> _loadUserProfile() async {
    try {
      final profileData = await ApiService.instance.getUserProfile();
      if (profileData != null) {
        setState(() {
          _bio = profileData['bio'] as String?;
          _interests = (profileData['interests'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];
          // Backend changed: legacy 'location' string now 'locationLabel'; structured location in 'location'
          if (profileData['location'] is Map<String, dynamic>) {
            final loc = profileData['location'] as Map<String, dynamic>;
            final name = (loc['name'] as String?)?.trim();
            final city = (loc['city'] as String?)?.trim();
            final country = (loc['country'] as String?)?.trim();
            _location = name?.isNotEmpty == true
                ? [name, city]
                    .whereType<String>()
                    .where((e) => e.isNotEmpty)
                    .take(2)
                    .join(', ')
                : [city, country]
                    .whereType<String>()
                    .where((e) => e.isNotEmpty)
                    .join(', ');
          } else {
            _location = profileData['locationLabel'] as String? ??
                profileData['location'] as String?;
          }
          _phoneNumber = profileData['phoneNumber'] as String?;
          _gender = profileData['gender'] as String?;
          _occupation = profileData['occupation'] as String?;
          _company = profileData['company'] as String?;
          _education = profileData['education'] as String?;
          _languages = (profileData['languages'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];
          _timezone = profileData['timezone'] as String?;

          // Fetch profile image from Prisma
          final fetchedUrl = profileData['profileImageUrl'] as String?;
          _photoUrl =
              (fetchedUrl != null && fetchedUrl.isNotEmpty) ? fetchedUrl : null;

          // Get counts from profile data
          final counts = profileData['_count'] as Map<String, dynamic>?;
          if (counts != null) {
            // Note: In the Prisma schema, the relation names map such that
            // counts['followers'] corresponds to how many users this user follows,
            // and counts['following'] corresponds to how many users follow this user.
            _followersCount =
                counts['following'] as int? ?? 0; // people who follow me
            _followingCount =
                counts['followers'] as int? ?? 0; // people I follow
            _totalPosts = counts['posts'] as int? ?? 0;
          }
        });
      } else {
        // Fallback to placeholder data if profile not found
        _bio = 'Passionate about connecting people through amazing events!';
        _interests = ['Technology', 'Music', 'Sports', 'Food'];
        _location = 'San Francisco, CA';
        _phoneNumber = null;
        _gender = null;
        _occupation = null;
        _company = null;
        _education = null;
        _languages = [];
        _timezone = null;
        _followersCount = 0;
        _followingCount = 0;
        _totalPosts = 0;
      }

      // Load user stats from backend
      final uid = currentUserUid;
      if (uid.isNotEmpty) {
        final statsData = await ApiService.instance.getUserStats(uid);
        if (statsData != null) {
          setState(() {
            _totalEvents = statsData['totalEventsCount'] as int? ?? 0;
            _totalConnections = statsData['followersCount'] as int? ?? 0;
          });
        } else {
          setState(() {
            _totalEvents = _created.length + _joined.length;
            _totalConnections = _followersCount;
          });
        }
      }
    } catch (e) {
      print('Error loading user profile: $e');
      // Fallback to placeholder data
      _bio = 'Passionate about connecting people through amazing events!';
      _interests = ['Technology', 'Music', 'Sports', 'Food'];
      _location = 'San Francisco, CA';
      _phoneNumber = null;
      _gender = null;
      _occupation = null;
      _company = null;
      _education = null;
      _languages = [];
      _timezone = null;
      _totalEvents = 0;
      _totalConnections = 0;
      _totalPosts = 0;
      _followersCount = 0;
      _followingCount = 0;
    }
  }

  Future<void> _fetchCreatedPulses() async {
    try {
      setState(() => _loadingCreated = true);
      final items = await ApiService.instance.getCreatedPulses();
      if (mounted) {
        setState(() => _created = items ?? []);
      }
    } catch (e) {
      print('Error fetching created pulses: $e');
      if (mounted) setState(() => _created = []);
    } finally {
      if (mounted) setState(() => _loadingCreated = false);
    }
  }

  Future<void> _fetchJoinedPulses() async {
    try {
      setState(() => _loadingJoined = true);
      final items = await ApiService.instance.getParticipatingPulses();
      if (mounted) {
        setState(() => _joined = items ?? []);
      }
    } catch (e) {
      print('Error fetching joined pulses: $e');
      if (mounted) setState(() => _joined = []);
    } finally {
      if (mounted) setState(() => _loadingJoined = false);
    }
  }

  Future<void> _fetchMyPosts() async {
    try {
      setState(() => _loadingPosts = true);
      final items = await ApiService.instance.getMyPosts();
      if (mounted) {
        setState(() => _posts = items ?? []);
      }
    } catch (e) {
      print('Error fetching posts: $e');
      if (mounted) setState(() => _posts = []);
    } finally {
      if (mounted) setState(() => _loadingPosts = false);
    }
  }

  Future<void> _fetchFollowers() async {
    try {
      setState(() => _loadingFollowers = true);
      final uid = currentUserUid;
      if (uid.isEmpty) {
        if (mounted) setState(() => _followers = []);
        return;
      }
      final items = await ApiService.instance.getUserFollowers(uid);
      if (mounted) {
        setState(() => _followers = items ?? []);
      }
    } catch (e) {
      print('Error fetching followers: $e');
      if (mounted) setState(() => _followers = []);
    } finally {
      if (mounted) setState(() => _loadingFollowers = false);
    }
  }

  Future<void> _fetchFollowing() async {
    try {
      setState(() => _loadingFollowing = true);
      final uid = currentUserUid;
      if (uid.isEmpty) {
        if (mounted) setState(() => _following = []);
        return;
      }
      final items = await ApiService.instance.getUserFollowing(uid);
      if (mounted) {
        setState(() => _following = items ?? []);
      }
    } catch (e) {
      print('Error fetching following: $e');
      if (mounted) setState(() => _following = []);
    } finally {
      if (mounted) setState(() => _loadingFollowing = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (image != null) {
        await _uploadProfileImage(File(image.path));
      }
    } catch (e) {
      print('Error picking image: $e');
      _showSnackBar('Failed to pick image');
    }
  }

  Future<void> _uploadProfileImage(File imageFile) async {
    try {
      setState(() => _loadingProfile = true);

      final storageService = StorageService();
      final imageUrl = await storageService.uploadProfileImage(imageFile);
      if (imageUrl != null) {
        // Update the profile in the backend
        final updatedProfile = await ApiService.instance.updateUserProfile(
          profileImageUrl: imageUrl,
        );

        if (updatedProfile != null) {
          setState(() => _photoUrl = imageUrl);
          _showSnackBar('Profile picture updated!');
        } else {
          _showSnackBar('Failed to update profile');
        }
      } else {
        _showSnackBar('Failed to upload image');
      }
    } catch (e) {
      print('Error uploading image: $e');
      _showSnackBar('Failed to upload image');
    } finally {
      setState(() => _loadingProfile = false);
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  void dispose() {
    _model.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: theme.primaryBackground,
        endDrawer: _buildSettingsDrawer(context),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    await Haptics.vibrate(HapticsType.medium);
                    await _initializeProfile();
                    // Refresh profile data from backend
                    await _loadUserProfile();
                  },
                  color: theme.primary,
                  backgroundColor: theme.secondaryBackground,
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(child: _buildHeader(context)),
                      SliverToBoxAdapter(child: _buildStats(context)),
                      SliverToBoxAdapter(child: _buildProfileInfo(context)),
                      SliverAppBar(
                        pinned: true,
                        backgroundColor: theme.primaryBackground,
                        elevation: 0,
                        toolbarHeight: 0,
                        bottom: PreferredSize(
                          preferredSize: const Size.fromHeight(56),
                          child: _buildTabs(context),
                        ),
                      ),
                      SliverToBoxAdapter(child: _buildTabContent(context)),
                      const SliverToBoxAdapter(child: SizedBox(height: 100)),
                    ],
                  ),
                ),
              ),
              wrapWithModel(
                model: _model.navbarModel,
                updateCallback: () => safeSetState(() {}),
                child: const NavbarWidget(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: theme.primary,
        boxShadow: [
          BoxShadow(
            color: theme.primary.withOpacity(0.25),
            blurRadius: 24.0,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  children: [
                    _buildAvatar(context),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayName ?? 'Your Name',
                            style: theme.titleLarge.override(
                              font: GoogleFonts.interTight(
                                fontWeight: FontWeight.w800,
                                fontSize: 24,
                              ),
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          if (_location != null) ...[
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on_rounded,
                                  color: Colors.white.withOpacity(0.8),
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _location!,
                                  style: theme.bodyMedium.override(
                                    font: GoogleFonts.inter(),
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (_joinDate != null) ...[
                            Text(
                              'Member since ${_formatJoinDate(_joinDate!)}',
                              style: theme.bodySmall.override(
                                font: GoogleFonts.inter(),
                                color: Colors.white.withOpacity(0.7),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    _buildEditButton(context),
                    const SizedBox(width: 8),
                    Material(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => scaffoldKey.currentState?.openEndDrawer(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: const Icon(
                            Icons.settings_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_bio != null && _bio!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      _bio!,
                      style: theme.bodyMedium.override(
                        font: GoogleFonts.inter(),
                        color: Colors.white,
                        lineHeight: 1.4,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return GestureDetector(
      onTap: _isEditing ? _pickImage : null,
      child: Stack(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [theme.secondary, theme.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.secondary.withOpacity(0.3),
                  blurRadius: 16.0,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
          ),
          Container(
            width: 74,
            height: 74,
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              image: _photoUrl != null && _photoUrl!.isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(_photoUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8.0,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: (_photoUrl == null || _photoUrl?.isEmpty == true)
                ? Icon(
                    Icons.person_rounded,
                    color: theme.primary.withOpacity(0.6),
                    size: 36,
                  )
                : null,
          ),
          if (_isEditing)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: theme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Icon(
                  Icons.camera_alt_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEditButton(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Material(
      color: Colors.white.withOpacity(0.2),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          await Haptics.vibrate(HapticsType.selection);
          setState(() => _isEditing = !_isEditing);
          if (_isEditing) {
            _showEditProfileSheet(context);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isEditing ? Icons.check_rounded : Icons.edit_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                _isEditing ? 'Done' : 'Edit',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStats(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.alternate.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10.0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildStatItem(
              context,
              icon: Icons.event_rounded,
              value: _totalEvents.toString(),
              label: 'Events',
              color: theme.primary,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: theme.alternate.withOpacity(0.3),
          ),
          Expanded(
            child: _buildStatItem(
              context,
              icon: Icons.people_rounded,
              value: _followersCount.toString(),
              label: 'Followers',
              color: Colors.teal,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: theme.alternate.withOpacity(0.3),
          ),
          Expanded(
            child: _buildStatItem(
              context,
              icon: Icons.person_add_rounded,
              value: _followingCount.toString(),
              label: 'Following',
              color: Colors.indigo,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: theme.alternate.withOpacity(0.3),
          ),
          Expanded(
            child: _buildStatItem(
              context,
              icon: Icons.post_add_rounded,
              value: _totalPosts.toString(),
              label: 'Posts',
              color: Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    final theme = FlutterFlowTheme.of(context);

    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: theme.titleMedium.override(
            font: GoogleFonts.interTight(fontWeight: FontWeight.w700),
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.bodySmall.override(
            font: GoogleFonts.inter(),
            color: theme.secondaryText,
          ),
        ),
      ],
    );
  }

  Widget _buildProfileInfo(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    if (_interests.isEmpty) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.alternate.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.tag_rounded,
                color: theme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add your interests',
                    style: theme.titleSmall.override(
                      font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Help us personalize your experience',
                    style: theme.bodySmall.override(
                      font: GoogleFonts.inter(),
                      color: theme.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.alternate.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: theme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.tag_rounded,
                  color: theme.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Interests',
                style: theme.titleSmall.override(
                  font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _interests
                .map(
                  (interest) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.primary.withOpacity(0.2),
                      ),
                    ),
                    child: Text(
                      interest,
                      style: theme.bodySmall.override(
                        font: GoogleFonts.inter(fontWeight: FontWeight.w500),
                        color: theme.primary,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.alternate.withOpacity(0.3)),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: LinearGradient(
            colors: [theme.primary, theme.secondary],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: theme.secondaryText,
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500),
        tabs: const [
          Tab(text: 'My Events'),
          Tab(text: 'My Posts'),
          Tab(text: 'Connections'),
        ],
      ),
    );
  }

  Widget _buildTabContent(BuildContext context) {
    return SizedBox(
      height: 600, // Fixed height for TabBarView
      child: TabBarView(
        controller: _tabController,
        children: [
          _buildMyEventsTab(context),
          _buildMyPostsTab(context),
          _buildConnectionsTab(context),
        ],
      ),
    );
  }

  Widget _buildMyEventsTab(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    if (_loadingCreated && _loadingJoined) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(theme.primary),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading your events...',
              style: theme.bodyMedium.override(
                font: GoogleFonts.inter(),
                color: theme.secondaryText,
              ),
            ),
          ],
        ),
      );
    }

    final bool showCreated = _eventsFilterIndex == 0;
    final List<Map<String, dynamic>> visible = showCreated ? _created : _joined;

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        _buildEventsFilter(context),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          _buildEmptyState(
            context,
            icon: Icons.event_busy_rounded,
            title: showCreated ? 'No created events' : 'No joined events',
            subtitle: showCreated
                ? 'Create an event to see it here'
                : 'Join an event to see it here',
            actionText: 'Explore Events',
            onAction: () {
              // Navigate to events page
            },
          )
        else ...[
          _buildSectionHeader(
            context,
            icon:
                showCreated ? Icons.auto_awesome_rounded : Icons.group_rounded,
            title: showCreated ? 'Created by you' : 'You joined',
            color: showCreated ? theme.primary : Colors.teal,
          ),
          ...visible
              .map(
                (pulse) => PulseCardWidgetMaterial(
                  pulse: pulse,
                  onTap: () async {
                    await Haptics.vibrate(HapticsType.selection);
                    // Navigate to pulse details
                  },
                )
                    .animate()
                    .fadeIn(duration: 300.ms)
                    .slideX(begin: 0.05, end: 0),
              )
              .toList(),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildEventsFilter(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.alternate.withOpacity(0.3)),
      ),
      child: ToggleButtons(
        isSelected: [
          _eventsFilterIndex == 0,
          _eventsFilterIndex == 1,
        ],
        onPressed: (index) async {
          await Haptics.vibrate(HapticsType.selection);
          setState(() => _eventsFilterIndex = index);
        },
        borderRadius: BorderRadius.circular(10),
        constraints: const BoxConstraints(minHeight: 40, minWidth: 120),
        selectedColor: Colors.white,
        color: theme.secondaryText,
        fillColor: theme.primary,
        children: const [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded, size: 18),
                SizedBox(width: 6),
                Text('Created'),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.group_rounded, size: 18),
                SizedBox(width: 6),
                Text('Joined'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyPostsTab(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    if (_loadingPosts) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(theme.primary),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading your posts...',
              style: theme.bodyMedium.override(
                font: GoogleFonts.inter(),
                color: theme.secondaryText,
              ),
            ),
          ],
        ),
      );
    }

    if (_posts.isEmpty) {
      return _buildEmptyState(
        context,
        icon: Icons.post_add_rounded,
        title: 'No posts yet',
        subtitle: 'Share updates and moments from your events.',
        actionText: 'Create Post',
        onAction: () {
          _showCreatePostSheet(context);
        },
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.create_rounded),
              label: Text('Create Post',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              onPressed: () => _showCreatePostSheet(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
        ..._posts.map((post) => _buildPostCard(context, post)).toList(),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildPostCard(BuildContext context, Map<String, dynamic> post) {
    final theme = FlutterFlowTheme.of(context);
    final createdAtStr = post['createdAt'] as String?;
    DateTime? createdAt;
    if (createdAtStr != null) {
      try {
        createdAt = DateTime.parse(createdAtStr);
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.alternate.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10.0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((post['imageUrl'] as String?)?.isNotEmpty == true)
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              child: Image.network(
                post['imageUrl'],
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (post['content'] as String? ?? '').trim(),
                  style: theme.bodyMedium.override(
                    font: GoogleFonts.inter(),
                    color: theme.primaryText,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      createdAt != null ? timeAgo(createdAt) : '',
                      style: theme.bodySmall.override(
                        font: GoogleFonts.inter(),
                        color: theme.secondaryText,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline_rounded,
                          color: theme.secondaryText),
                      onPressed: () async {
                        await Haptics.vibrate(HapticsType.selection);
                        final ok = await ApiService.instance
                            .deletePost(post['id'] as String);
                        if (ok) {
                          setState(() {
                            _posts.removeWhere((p) => p['id'] == post['id']);
                            _totalPosts = (_totalPosts - 1).clamp(0, 1 << 31);
                          });
                          _showSnackBar('Post deleted');
                        } else {
                          _showSnackBar('Failed to delete post');
                        }
                      },
                    )
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  void _showCreatePostSheet(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final contentController = TextEditingController();
    File? selectedImageFile;
    bool isPublic = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: theme.secondaryBackground,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Create Post',
                          style: theme.titleLarge.override(
                            font: GoogleFonts.interTight(
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(Icons.close_rounded,
                              color: theme.secondaryText),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: contentController,
                      label: 'What\'s on your mind? (optional image)',
                      icon: Icons.edit_rounded,
                      maxLines: 4,
                    ),
                    const SizedBox(height: 12),
                    if (selectedImageFile != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          selectedImageFile!,
                          width: double.infinity,
                          height: 180,
                          fit: BoxFit.cover,
                        ),
                      ),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () async {
                            final XFile? picked = await _picker.pickImage(
                              source: ImageSource.gallery,
                              maxWidth: 1200,
                              imageQuality: 85,
                            );
                            if (picked != null) {
                              setModalState(() {
                                selectedImageFile = File(picked.path);
                              });
                            }
                          },
                          icon: const Icon(Icons.image_rounded),
                          label: const Text('Add image'),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Switch(
                              value: isPublic,
                              onChanged: (v) =>
                                  setModalState(() => isPublic = v),
                            ),
                            Text('Public',
                                style: theme.bodyMedium
                                    .override(font: GoogleFonts.inter())),
                          ],
                        )
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          await Haptics.vibrate(HapticsType.medium);
                          final content = contentController.text.trim();
                          if (content.isEmpty && selectedImageFile == null) {
                            _showSnackBar('Please add some text or an image');
                            return;
                          }

                          setModalState(() {});

                          String? imageUrl;
                          if (selectedImageFile != null) {
                            final storageService = StorageService();
                            imageUrl = await storageService
                                .uploadPostImage(selectedImageFile!);
                            if (imageUrl == null) {
                              _showSnackBar('Failed to upload image');
                              return;
                            }
                          }

                          final created = await ApiService.instance.createPost(
                            content: content,
                            imageUrl: imageUrl,
                            isPublic: isPublic,
                          );

                          if (created != null) {
                            setState(() {
                              _posts.insert(0, created);
                              _totalPosts += 1;
                            });
                            _showSnackBar('Post created');
                            if (mounted) Navigator.pop(context);
                          } else {
                            _showSnackBar('Failed to create post');
                          }
                        },
                        child: Text(
                          'Post',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String timeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Widget _buildConnectionsTab(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Followers section
        _buildSectionHeader(
          context,
          icon: Icons.people_rounded,
          title: 'Followers ($_followersCount)',
          color: Colors.teal,
        ),
        const SizedBox(height: 12),
        _buildFollowersGrid(context),

        const SizedBox(height: 24),

        // Following section
        _buildSectionHeader(
          context,
          icon: Icons.person_add_rounded,
          title: 'Following ($_followingCount)',
          color: theme.primary,
        ),
        const SizedBox(height: 12),
        _buildFollowingGrid(context),
      ],
    );
  }

  Widget _buildFollowersGrid(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    if (_loadingFollowers) {
      return const Center(
          child: Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: CircularProgressIndicator(),
      ));
    }

    if (_followers.isEmpty) {
      return _buildEmptyConnectionCard(
        context,
        icon: Icons.people_outline_rounded,
        title: 'No followers yet',
        subtitle: 'Start creating events to attract followers',
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: _followers.length,
      itemBuilder: (context, index) {
        final user = _followers[index];
        final name = (user['displayName'] as String?)?.trim();
        final avatar = (user['profileImageUrl'] as String?)?.trim();
        // Adapt follower location: may have structured location object
        String? location;
        final rawLoc = user['location'];
        if (rawLoc is Map<String, dynamic>) {
          final name = (rawLoc['name'] as String?)?.trim();
          final city = (rawLoc['city'] as String?)?.trim();
          final country = (rawLoc['country'] as String?)?.trim();
          location = name?.isNotEmpty == true
              ? [name, city]
                  .whereType<String>()
                  .where((e) => e.isNotEmpty)
                  .take(2)
                  .join(', ')
              : [city, country]
                  .whereType<String>()
                  .where((e) => e.isNotEmpty)
                  .join(', ');
        } else {
          location = (rawLoc as String?)?.trim() ??
              (user['locationLabel'] as String?)?.trim();
        }

        return Container(
          decoration: BoxDecoration(
            color: theme.secondaryBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.alternate.withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10.0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: theme.primary.withOpacity(0.1),
                backgroundImage: (avatar != null && avatar.isNotEmpty)
                    ? NetworkImage(avatar)
                    : null,
                child: (avatar == null || avatar.isEmpty)
                    ? Icon(Icons.person_rounded, color: theme.primary, size: 32)
                    : null,
              ),
              const SizedBox(height: 12),
              Text(
                name?.isNotEmpty == true ? name! : 'Unnamed',
                style: theme.titleSmall.override(
                  font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                location?.isNotEmpty == true ? location! : 'Follower',
                style: theme.bodySmall.override(
                  font: GoogleFonts.inter(),
                  color: theme.secondaryText,
                ),
              ),
            ],
          ),
        ).animate().fadeIn(duration: 300.ms).scale(
              begin: const Offset(0.95, 0.95),
              end: const Offset(1, 1),
              duration: 200.ms,
            );
      },
    );
  }

  Widget _buildFollowingGrid(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    if (_loadingFollowing) {
      return const Center(
          child: Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: CircularProgressIndicator(),
      ));
    }

    if (_following.isEmpty) {
      return _buildEmptyConnectionCard(
        context,
        icon: Icons.person_add_outlined,
        title: 'Not following anyone',
        subtitle: 'Discover and follow interesting people',
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: _following.length,
      itemBuilder: (context, index) {
        final user = _following[index];
        final name = (user['displayName'] as String?)?.trim();
        final avatar = (user['profileImageUrl'] as String?)?.trim();
        String? location;
        final rawLoc2 = user['location'];
        if (rawLoc2 is Map<String, dynamic>) {
          final name = (rawLoc2['name'] as String?)?.trim();
          final city = (rawLoc2['city'] as String?)?.trim();
          final country = (rawLoc2['country'] as String?)?.trim();
          location = name?.isNotEmpty == true
              ? [name, city]
                  .whereType<String>()
                  .where((e) => e.isNotEmpty)
                  .take(2)
                  .join(', ')
              : [city, country]
                  .whereType<String>()
                  .where((e) => e.isNotEmpty)
                  .join(', ');
        } else {
          location = (rawLoc2 as String?)?.trim() ??
              (user['locationLabel'] as String?)?.trim();
        }

        return Container(
          decoration: BoxDecoration(
            color: theme.secondaryBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.alternate.withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10.0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: theme.primary.withOpacity(0.1),
                backgroundImage: (avatar != null && avatar.isNotEmpty)
                    ? NetworkImage(avatar)
                    : null,
                child: (avatar == null || avatar.isEmpty)
                    ? Icon(Icons.person_rounded, color: theme.primary, size: 32)
                    : null,
              ),
              const SizedBox(height: 12),
              Text(
                name?.isNotEmpty == true ? name! : 'Unnamed',
                style: theme.titleSmall.override(
                  font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                location?.isNotEmpty == true ? location! : 'Following',
                style: theme.bodySmall.override(
                  font: GoogleFonts.inter(),
                  color: theme.secondaryText,
                ),
              ),
            ],
          ),
        ).animate().fadeIn(duration: 300.ms).scale(
              begin: const Offset(0.95, 0.95),
              end: const Offset(1, 1),
              duration: 200.ms,
            );
      },
    );
  }

  Widget _buildEmptyConnectionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.alternate.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 48,
            color: theme.secondaryText,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: theme.titleSmall.override(
              font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.bodySmall.override(
              font: GoogleFonts.inter(),
              color: theme.secondaryText,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Color color,
  }) {
    final theme = FlutterFlowTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: theme.titleSmall.override(
              font: GoogleFonts.interTight(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionText,
    required VoidCallback onAction,
  }) {
    final theme = FlutterFlowTheme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: theme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(icon, size: 40, color: theme.primary),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: theme.titleMedium.override(
                font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.bodyMedium.override(
                font: GoogleFonts.inter(),
                color: theme.secondaryText,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                actionText,
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditProfileSheet(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final nameController = TextEditingController(text: _displayName ?? '');
    final bioController = TextEditingController(text: _bio ?? '');
    final locationController = TextEditingController(text: _location ?? '');
    final interestsController = TextEditingController(
      text: _interests.join(', '),
    );
    final phoneController = TextEditingController(text: _phoneNumber ?? '');
    final occupationController = TextEditingController(text: _occupation ?? '');
    final companyController = TextEditingController(text: _company ?? '');
    final educationController = TextEditingController(text: _education ?? '');
    final languagesController = TextEditingController(
      text: _languages.join(', '),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: theme.secondaryBackground,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Edit Profile',
                      style: theme.titleLarge.override(
                        font:
                            GoogleFonts.interTight(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon:
                          Icon(Icons.close_rounded, color: theme.secondaryText),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildTextField(
                  controller: nameController,
                  label: 'Display Name',
                  icon: Icons.person_rounded,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: bioController,
                  label: 'Bio',
                  icon: Icons.description_rounded,
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: locationController,
                  label: 'Location',
                  icon: Icons.location_on_rounded,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: interestsController,
                  label: 'Interests (comma separated)',
                  icon: Icons.tag_rounded,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: phoneController,
                  label: 'Phone Number',
                  icon: Icons.phone_rounded,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: occupationController,
                  label: 'Occupation',
                  icon: Icons.work_rounded,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: companyController,
                  label: 'Company',
                  icon: Icons.business_rounded,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: educationController,
                  label: 'Education',
                  icon: Icons.school_rounded,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: languagesController,
                  label: 'Languages (comma separated)',
                  icon: Icons.language_rounded,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      await Haptics.vibrate(HapticsType.medium);

                      final newDisplayName = nameController.text.trim().isEmpty
                          ? _displayName
                          : nameController.text.trim();
                      final newBio = bioController.text.trim();
                      final newLocation = locationController.text.trim();
                      final newInterests = interestsController.text
                          .split(',')
                          .map((e) => e.trim())
                          .where((e) => e.isNotEmpty)
                          .toList();
                      final newPhoneNumber = phoneController.text.trim();
                      final newOccupation = occupationController.text.trim();
                      final newCompany = companyController.text.trim();
                      final newEducation = educationController.text.trim();
                      final newLanguages = languagesController.text
                          .split(',')
                          .map((e) => e.trim())
                          .where((e) => e.isNotEmpty)
                          .toList();

                      // Update profile in backend
                      final updatedProfile =
                          await ApiService.instance.updateUserProfile(
                        displayName: newDisplayName,
                        bio: newBio,
                        location: newLocation,
                        interests: newInterests,
                        phoneNumber:
                            newPhoneNumber.isEmpty ? null : newPhoneNumber,
                        occupation:
                            newOccupation.isEmpty ? null : newOccupation,
                        company: newCompany.isEmpty ? null : newCompany,
                        education: newEducation.isEmpty ? null : newEducation,
                        languages: newLanguages,
                      );

                      if (updatedProfile != null) {
                        setState(() {
                          _displayName = newDisplayName;
                          _bio = newBio;
                          _location = newLocation;
                          _interests = newInterests;
                          _phoneNumber =
                              newPhoneNumber.isEmpty ? null : newPhoneNumber;
                          _occupation =
                              newOccupation.isEmpty ? null : newOccupation;
                          _company = newCompany.isEmpty ? null : newCompany;
                          _education =
                              newEducation.isEmpty ? null : newEducation;
                          _languages = newLanguages;
                        });
                        _showSnackBar('Profile updated successfully!');
                      } else {
                        _showSnackBar('Failed to update profile');
                      }

                      if (mounted) Navigator.pop(context);
                    },
                    child: Text(
                      'Save Changes',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
  }) {
    final theme = FlutterFlowTheme.of(context);

    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: theme.secondaryText),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.alternate),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.alternate),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.primary, width: 2),
        ),
        filled: true,
        fillColor: theme.primaryBackground,
      ),
    );
  }

  String _formatJoinDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays < 30) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months month${months > 1 ? 's' : ''} ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return '$years year${years > 1 ? 's' : ''} ago';
    }
  }
}
