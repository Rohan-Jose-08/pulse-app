import '/backend/api_service.dart';
import '/components/pulse_card_widget_material.dart';
import '/components/navbar_widget.dart';
import '/components/highlights_row.dart';
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
import '../highlights/highlight_viewer_page.dart';
import '../highlights/manage_highlight_page.dart';
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
  Map<String, String> _activityStatuses = {}; // userId -> status

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

  // Settings states
  bool _loadingSettings = true;
  bool _activityStatusVisible = true;
  bool _hapticFeedbackEnabled = true;
  bool _pushNotificationsEnabled = true;
  bool _notifyNewPulsesNearby = true;
  bool _notifyPulseInvitations = true;
  bool _notifyPulseUpdates = true;
  bool _notifyNewMessages = true;
  bool _notifyNewFollowers = true;
  bool _notifyFriendRequests = true;
  bool _notifyPostReactions = true;
  String _themePreference = 'system';
  String _languagePreference = 'en_US';
  double _textSizeScale = 1.0;

  // Activity status states
  String _currentActivityStatus = 'online'; // online, away, offline
  bool _appearOffline = false; // Manual offline mode

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => ProfileModel());
    _tabController = TabController(length: 3, vsync: this);
    // Listen to tab changes to rebuild content
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    _initializeProfile();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _loadingSettings = true);
    try {
      final settings = await ApiService.instance.getUserSettings();
      if (settings != null && mounted) {
        setState(() {
          _activityStatusVisible = settings['activityStatusVisible'] ?? true;
          _hapticFeedbackEnabled = settings['hapticFeedbackEnabled'] ?? true;
          _pushNotificationsEnabled =
              settings['pushNotificationsEnabled'] ?? true;
          _notifyNewPulsesNearby = settings['notifyNewPulsesNearby'] ?? true;
          _notifyPulseInvitations = settings['notifyPulseInvitations'] ?? true;
          _notifyPulseUpdates = settings['notifyPulseUpdates'] ?? true;
          _notifyNewMessages = settings['notifyNewMessages'] ?? true;
          _notifyNewFollowers = settings['notifyNewFollowers'] ?? true;
          _notifyFriendRequests = settings['notifyFriendRequests'] ?? true;
          _notifyPostReactions = settings['notifyPostReactions'] ?? true;
          _themePreference = settings['themePreference'] ?? 'system';
          _languagePreference = settings['languagePreference'] ?? 'en_US';
          _textSizeScale =
              (settings['textSizeScale'] as num?)?.toDouble() ?? 1.0;
        });
      }
    } catch (e) {
      print('Error loading settings: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingSettings = false);
      }
    }
  }

  Future<void> _updateSetting(Map<String, dynamic> setting) async {
    try {
      await ApiService.instance.updateUserSettings(setting);
    } catch (e) {
      print('Error updating setting: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update setting: $e')),
        );
      }
    }
  }

  Widget _buildSettingsDrawer(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Drawer(
      backgroundColor: theme.secondaryBackground,
      elevation: 16,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Simple Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  Icon(
                    Icons.settings_rounded,
                    color: theme.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Settings',
                    style: theme.headlineMedium.override(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.alternate),

            // Settings Content with improved scrolling
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                physics: const BouncingScrollPhysics(),
                children: [
                  // Privacy Section
                  _buildSettingsSectionHeader(context, 'Privacy'),
                  _buildSettingsTile(
                    context,
                    icon: Icons.lock_outline_rounded,
                    title: 'Privacy Settings',
                    subtitle: 'Control who can see your information',
                    onTap: () => _showPrivacySettings(context),
                  ),
                  _buildSettingsTile(
                    context,
                    icon: Icons.block_rounded,
                    title: 'Blocked Users',
                    subtitle: 'Manage blocked accounts',
                    onTap: () => _showBlockedUsers(context),
                  ),
                  _buildSettingsTile(
                    context,
                    icon: Icons.circle,
                    iconColor: _getStatusColor(),
                    title: 'Activity Status',
                    subtitle: _appearOffline
                        ? 'Appear Offline'
                        : _getStatusText(_currentActivityStatus),
                    onTap: () => _showActivityStatusDialog(context),
                  ),

                  const Divider(height: 24),

                  // Account Section
                  _buildSettingsSectionHeader(context, 'Account'),
                  _buildSettingsTile(
                    context,
                    icon: Icons.person_outline_rounded,
                    title: 'Account Information',
                    subtitle: 'View your account details',
                    onTap: () => _showAccountInfo(context),
                  ),
                  _buildSettingsTile(
                    context,
                    icon: Icons.email_outlined,
                    title: 'Email',
                    subtitle: currentUserEmail,
                    onTap: () {
                      // TODO: Navigate to email settings
                    },
                  ),
                  _buildSettingsTile(
                    context,
                    icon: Icons.verified_user_outlined,
                    title: 'Email Verification',
                    subtitle: currentUserEmailVerified
                        ? 'Verified'
                        : 'Not verified - Tap to verify',
                    trailing: currentUserEmailVerified
                        ? Icon(Icons.check_circle, color: Colors.green)
                        : null,
                    onTap: () {
                      if (!currentUserEmailVerified) {
                        _sendVerificationEmail(context);
                      }
                    },
                  ),
                  _buildSettingsTile(
                    context,
                    icon: Icons.password_rounded,
                    title: 'Change Password',
                    subtitle: 'Update your password',
                    onTap: () => _showChangePassword(context),
                  ),

                  const Divider(height: 24),

                  // Notifications Section
                  _buildSettingsSectionHeader(context, 'Notifications'),
                  _buildSettingsTile(
                    context,
                    icon: Icons.notifications_outlined,
                    title: 'Notification Settings',
                    subtitle: 'Manage your notifications',
                    onTap: () => _showNotificationSettings(context),
                  ),
                  _buildSettingsTile(
                    context,
                    icon: Icons.vibration_rounded,
                    title: 'Haptic Feedback',
                    subtitle: 'Vibrate on interactions',
                    trailing: Switch(
                      value: _hapticFeedbackEnabled,
                      onChanged: (value) async {
                        setState(() => _hapticFeedbackEnabled = value);
                        await _updateSetting({'hapticFeedbackEnabled': value});
                      },
                      activeColor: theme.primary,
                    ),
                  ),

                  const Divider(height: 24),

                  // Appearance Section
                  _buildSettingsSectionHeader(context, 'Appearance'),
                  _buildSettingsTile(
                    context,
                    icon: Icons.palette_outlined,
                    title: 'Theme',
                    subtitle: 'Light, Dark, or System',
                    onTap: () => _showThemeSettings(context),
                  ),
                  _buildSettingsTile(
                    context,
                    icon: Icons.language_rounded,
                    title: 'Language',
                    subtitle: 'English (US)',
                    onTap: () => _showLanguageSettings(context),
                  ),
                  _buildSettingsTile(
                    context,
                    icon: Icons.text_fields_rounded,
                    title: 'Text Size',
                    subtitle: 'Adjust font size',
                    onTap: () => _showTextSizeSettings(context),
                  ),

                  const Divider(height: 24),

                  // Data & Storage Section
                  _buildSettingsSectionHeader(context, 'Data & Storage'),
                  _buildSettingsTile(
                    context,
                    icon: Icons.download_rounded,
                    title: 'Download Your Data',
                    subtitle: 'Request a copy of your information',
                    onTap: () => _showDownloadData(context),
                  ),
                  _buildSettingsTile(
                    context,
                    icon: Icons.storage_rounded,
                    title: 'Storage',
                    subtitle: 'Manage app storage',
                    onTap: () => _showStorageSettings(context),
                  ),

                  const Divider(height: 24),

                  // Support Section
                  _buildSettingsSectionHeader(context, 'Support'),
                  _buildSettingsTile(
                    context,
                    icon: Icons.help_outline_rounded,
                    title: 'Help Center',
                    subtitle: 'Get help and support',
                    onTap: () {
                      // TODO: Open help center
                    },
                  ),
                  _buildSettingsTile(
                    context,
                    icon: Icons.info_outline_rounded,
                    title: 'About Pulse',
                    subtitle: 'App version and information',
                    onTap: () => _showAboutDialog(context),
                  ),
                  _buildSettingsTile(
                    context,
                    icon: Icons.bug_report_outlined,
                    title: 'Report a Problem',
                    subtitle: 'Help us improve',
                    onTap: () {
                      // TODO: Open bug report
                    },
                  ),

                  const Divider(height: 24),

                  // Danger Zone
                  _buildSettingsSectionHeader(context, 'Account Actions'),
                  _buildSettingsTile(
                    context,
                    icon: Icons.logout_rounded,
                    title: 'Log Out',
                    subtitle: 'Sign out of your account',
                    iconColor: theme.error,
                    onTap: () async {
                      final confirmed = await _showConfirmDialog(
                        context,
                        title: 'Log Out',
                        message: 'Are you sure you want to log out?',
                      );
                      if (confirmed == true) {
                        try {
                          await authManager.signOut();
                        } catch (_) {}
                        if (!mounted) return;
                        Navigator.of(context).pop();
                        context.go('/loginPage');
                      }
                    },
                  ),
                  _buildSettingsTile(
                    context,
                    icon: Icons.delete_forever_rounded,
                    title: 'Delete Account',
                    subtitle: 'Permanently delete your account',
                    iconColor: theme.error,
                    onTap: () => _showDeleteAccount(context),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),

            // Enhanced Footer
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.primaryBackground,
                border: Border(
                  top: BorderSide(color: theme.alternate, width: 1),
                ),
              ),
              child: Column(
                children: [
                  // Quick Links
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildFooterLink(
                        context,
                        icon: Icons.description_outlined,
                        label: 'Terms',
                        onTap: () {
                          // TODO: Open terms
                        },
                      ),
                      Container(
                        width: 1,
                        height: 30,
                        color: theme.alternate,
                      ),
                      _buildFooterLink(
                        context,
                        icon: Icons.privacy_tip_outlined,
                        label: 'Privacy',
                        onTap: () {
                          // TODO: Open privacy policy
                        },
                      ),
                      Container(
                        width: 1,
                        height: 30,
                        color: theme.alternate,
                      ),
                      _buildFooterLink(
                        context,
                        icon: Icons.contact_support_outlined,
                        label: 'Support',
                        onTap: () {
                          // TODO: Open support
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  // App info with badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [theme.primary, theme.secondary],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Alpha-v0.0.1',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Pulse Social',
                        style: theme.labelMedium.override(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '© 2025 Pulse. All rights reserved.',
                    style: theme.bodySmall.override(
                      fontFamily: 'Inter',
                      fontSize: 10,
                      color: theme.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Social media icons (placeholder)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildSocialIcon(context, Icons.public, () {}),
                      const SizedBox(width: 12),
                      _buildSocialIcon(context, Icons.email_outlined, () {}),
                      const SizedBox(width: 12),
                      _buildSocialIcon(
                          context, Icons.chat_bubble_outline, () {}),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooterLink(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = FlutterFlowTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          children: [
            Icon(icon, color: theme.secondaryText, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.bodySmall.override(
                fontFamily: 'Inter',
                fontSize: 11,
                color: theme.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSocialIcon(
      BuildContext context, IconData icon, VoidCallback onTap) {
    final theme = FlutterFlowTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.alternate.withOpacity(0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: theme.secondaryText, size: 18),
      ),
    );
  }

  Widget _buildSettingsSectionHeader(BuildContext context, String title) {
    final theme = FlutterFlowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: theme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title.toUpperCase(),
            style: theme.labelMedium.override(
              fontFamily: 'Inter',
              color: theme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // Activity status helper methods
  Color _getStatusColor() {
    if (_appearOffline) return Colors.grey;
    switch (_currentActivityStatus) {
      case 'online':
        return Colors.green;
      case 'away':
        return Colors.orange;
      case 'offline':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'online':
        return 'Active now';
      case 'away':
        return 'Away';
      case 'offline':
        return 'Offline';
      default:
        return 'Unknown';
    }
  }

  Future<void> _showActivityStatusDialog(BuildContext context) async {
    final theme = FlutterFlowTheme.of(context);

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: BoxDecoration(
            color: theme.secondaryBackground,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Activity Status',
                      style: theme.headlineSmall.override(
                        fontFamily: 'Outfit',
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: theme.secondaryText),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose how you appear to others',
                  style: theme.bodyMedium.override(
                    fontFamily: 'Inter',
                    color: theme.secondaryText,
                  ),
                ),
                const SizedBox(height: 24),

                // Appear Offline Toggle
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.primaryBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.alternate.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.visibility_off_rounded,
                        color: _appearOffline
                            ? theme.primary
                            : theme.secondaryText,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Appear Offline',
                              style: theme.bodyLarge.override(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Hide your online status from everyone',
                              style: theme.bodySmall.override(
                                fontFamily: 'Inter',
                                color: theme.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _appearOffline,
                        onChanged: (value) async {
                          setModalState(() => _appearOffline = value);
                          setState(() => _appearOffline = value);

                          if (value) {
                            // Set user as offline manually
                            await ApiService.instance
                                .setActivityStatus('offline');
                          } else {
                            // Resume normal status
                            await ApiService.instance
                                .setActivityStatus('online');
                          }
                        },
                        activeColor: theme.primary,
                      ),
                    ],
                  ),
                ),

                if (!_appearOffline) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Status Options
                  Text(
                    'Current Status',
                    style: theme.labelMedium.override(
                      fontFamily: 'Inter',
                      color: theme.secondaryText,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),

                  _buildStatusOption(
                    context,
                    setModalState,
                    status: 'online',
                    icon: Icons.circle,
                    color: Colors.green,
                    title: 'Online',
                    subtitle: 'Active now',
                  ),
                  const SizedBox(height: 8),
                  _buildStatusOption(
                    context,
                    setModalState,
                    status: 'away',
                    icon: Icons.circle,
                    color: Colors.orange,
                    title: 'Away',
                    subtitle: 'Not at device',
                  ),
                  const SizedBox(height: 8),
                  _buildStatusOption(
                    context,
                    setModalState,
                    status: 'offline',
                    icon: Icons.circle,
                    color: Colors.grey,
                    title: 'Offline',
                    subtitle: 'Not available',
                  ),
                ],

                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),

                // Show Activity Status Toggle
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.primaryBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.alternate.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.remove_red_eye_outlined,
                        color: _activityStatusVisible
                            ? theme.primary
                            : theme.secondaryText,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Show Activity Status',
                              style: theme.bodyLarge.override(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Let others see when you\'re active',
                              style: theme.bodySmall.override(
                                fontFamily: 'Inter',
                                color: theme.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _activityStatusVisible,
                        onChanged: (value) async {
                          setModalState(() => _activityStatusVisible = value);
                          setState(() => _activityStatusVisible = value);
                          await _updateSetting(
                              {'activityStatusVisible': value});
                        },
                        activeColor: theme.primary,
                      ),
                    ],
                  ),
                ),

                SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusOption(
    BuildContext context,
    StateSetter setModalState, {
    required String status,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    final theme = FlutterFlowTheme.of(context);
    final isSelected = _currentActivityStatus == status && !_appearOffline;

    return InkWell(
      onTap: () async {
        setModalState(() => _currentActivityStatus = status);
        setState(() => _currentActivityStatus = status);
        await ApiService.instance.setActivityStatus(status);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.primary.withOpacity(0.1)
              : theme.primaryBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isSelected ? theme.primary : theme.alternate.withOpacity(0.5),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.bodyLarge.override(
                      fontFamily: 'Inter',
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.bodySmall.override(
                      fontFamily: 'Inter',
                      color: theme.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: theme.primary,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    Color? iconColor,
    VoidCallback? onTap,
  }) {
    final theme = FlutterFlowTheme.of(context);
    final effectiveIconColor = iconColor ?? theme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.alternate.withOpacity(0.5),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // Icon with gradient background
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        effectiveIconColor.withOpacity(0.15),
                        effectiveIconColor.withOpacity(0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: effectiveIconColor.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: effectiveIconColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                // Title and subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.bodyLarge.override(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: theme.bodySmall.override(
                            fontFamily: 'Inter',
                            color: theme.secondaryText,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Trailing widget
                trailing ??
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: theme.secondaryText.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: theme.secondaryText,
                        size: 18,
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Privacy Settings Dialog
  void _showPrivacySettings(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.alternate,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.lock_outline_rounded, color: theme.primary),
                  const SizedBox(width: 12),
                  Text(
                    'Privacy Settings',
                    style: theme.headlineSmall,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Privacy options
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildPrivacyOption(
                    context,
                    title: 'Profile Visibility',
                    subtitle: 'Control who can see your profile',
                    options: ['Public', 'Friends Only', 'Private'],
                    selectedIndex: 0, // TODO: Connect to state
                  ),
                  const SizedBox(height: 16),
                  _buildPrivacyOption(
                    context,
                    title: 'Location Sharing',
                    subtitle: 'Control who can see your location',
                    options: ['Everyone', 'Friends', 'Nobody'],
                    selectedIndex: 1,
                  ),
                  const SizedBox(height: 16),
                  _buildPrivacyOption(
                    context,
                    title: 'Pulse History',
                    subtitle: 'Who can see your past pulses',
                    options: ['Public', 'Friends Only', 'Only Me'],
                    selectedIndex: 1,
                  ),
                  const SizedBox(height: 16),
                  _buildPrivacyOption(
                    context,
                    title: 'Friend Requests',
                    subtitle: 'Who can send you friend requests',
                    options: ['Everyone', 'Friends of Friends', 'Nobody'],
                    selectedIndex: 0,
                  ),
                  const SizedBox(height: 24),
                  SwitchListTile(
                    title: Text('Show Online Status', style: theme.bodyLarge),
                    subtitle: Text(
                      'Let others see when you\'re online',
                      style: theme.bodySmall,
                    ),
                    value: true, // TODO: Connect to state
                    onChanged: (value) {},
                    activeColor: theme.primary,
                  ),
                  SwitchListTile(
                    title:
                        Text('Allow Message Requests', style: theme.bodyLarge),
                    subtitle: Text(
                      'Receive messages from non-friends',
                      style: theme.bodySmall,
                    ),
                    value: true,
                    onChanged: (value) {},
                    activeColor: theme.primary,
                  ),
                  SwitchListTile(
                    title: Text('Show in Search', style: theme.bodyLarge),
                    subtitle: Text(
                      'Allow others to find you via search',
                      style: theme.bodySmall,
                    ),
                    value: true,
                    onChanged: (value) {},
                    activeColor: theme.primary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyOption(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<String> options,
    required int selectedIndex,
  }) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.primaryBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.alternate),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: theme.bodyLarge.override(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
              )),
          const SizedBox(height: 4),
          Text(subtitle, style: theme.bodySmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: options.asMap().entries.map((entry) {
              final isSelected = entry.key == selectedIndex;
              return FilterChip(
                label: Text(entry.value),
                selected: isSelected,
                onSelected: (selected) {
                  // TODO: Update state
                },
                backgroundColor: theme.secondaryBackground,
                selectedColor: theme.primary.withOpacity(0.2),
                checkmarkColor: theme.primary,
                labelStyle: TextStyle(
                  color: isSelected ? theme.primary : theme.primaryText,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // Blocked Users Dialog
  void _showBlockedUsers(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.block_rounded, color: theme.error),
            const SizedBox(width: 12),
            const Text('Blocked Users'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'You haven\'t blocked anyone yet.',
                style: theme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Blocked users won\'t be able to see your profile, send you messages, or interact with your content.',
                style: theme.bodySmall.override(
                  fontFamily: 'Inter',
                  color: theme.secondaryText,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Account Info Dialog
  void _showAccountInfo(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.alternate,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.person_outline_rounded, color: theme.primary),
                  const SizedBox(width: 12),
                  Text('Account Information', style: theme.headlineSmall),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildInfoRow(context, 'User ID', currentUserUid),
                  _buildInfoRow(context, 'Email', currentUserEmail),
                  _buildInfoRow(
                      context, 'Display Name', _displayName ?? 'Not set'),
                  _buildInfoRow(
                      context,
                      'Phone',
                      currentPhoneNumber.isEmpty
                          ? 'Not set'
                          : currentPhoneNumber),
                  _buildInfoRow(context, 'Email Verified',
                      currentUserEmailVerified ? 'Yes' : 'No'),
                  _buildInfoRow(
                      context,
                      'Member Since',
                      _joinDate != null
                          ? '${_joinDate!.month}/${_joinDate!.day}/${_joinDate!.year}'
                          : 'Unknown'),
                  const SizedBox(height: 16),
                  Text(
                    'This information is used to personalize your experience and is not shared with other users unless you choose to display it on your profile.',
                    style: theme.bodySmall.override(
                      fontFamily: 'Inter',
                      color: theme.secondaryText,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    final theme = FlutterFlowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: theme.bodyMedium.override(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                color: theme.secondaryText,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: theme.bodyMedium,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  // Send Verification Email
  void _sendVerificationEmail(BuildContext context) async {
    final theme = FlutterFlowTheme.of(context);
    try {
      await currentUser?.sendEmailVerification();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              const Text('Verification email sent! Please check your inbox.'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send verification email: $e'),
          backgroundColor: theme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Change Password Dialog
  void _showChangePassword(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.password_rounded, color: theme.primary),
              const SizedBox(width: 12),
              const Text('Change Password'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: currentPasswordController,
                  obscureText: obscureCurrent,
                  decoration: InputDecoration(
                    labelText: 'Current Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(obscureCurrent
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () =>
                          setState(() => obscureCurrent = !obscureCurrent),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: newPasswordController,
                  obscureText: obscureNew,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                          obscureNew ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => obscureNew = !obscureNew),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: confirmPasswordController,
                  obscureText: obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Confirm New Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(obscureConfirm
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () =>
                          setState(() => obscureConfirm = !obscureConfirm),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (newPasswordController.text !=
                    confirmPasswordController.text) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Passwords do not match')),
                  );
                  return;
                }
                // TODO: Implement password change with Firebase re-authentication
                Navigator.pop(context);
              },
              child: const Text('Change Password'),
            ),
          ],
        ),
      ),
    );
  }

  // Notification Settings Dialog
  void _showNotificationSettings(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(
            color: theme.secondaryBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.alternate,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(Icons.notifications_outlined, color: theme.primary),
                    const SizedBox(width: 12),
                    Text('Notification Settings', style: theme.headlineSmall),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SwitchListTile(
                      title: Text('Push Notifications', style: theme.bodyLarge),
                      subtitle: Text('Receive push notifications',
                          style: theme.bodySmall),
                      value: true,
                      onChanged: (value) {},
                      activeColor: theme.primary,
                    ),
                    const Divider(),
                    Text('Pulse Notifications', style: theme.labelLarge),
                    SwitchListTile(
                      title: Text('New Pulses Nearby', style: theme.bodyMedium),
                      value: true,
                      onChanged: (value) {},
                      activeColor: theme.primary,
                    ),
                    SwitchListTile(
                      title: Text('Pulse Invitations', style: theme.bodyMedium),
                      value: true,
                      onChanged: (value) {},
                      activeColor: theme.primary,
                    ),
                    SwitchListTile(
                      title: Text('Pulse Updates', style: theme.bodyMedium),
                      value: true,
                      onChanged: (value) {},
                      activeColor: theme.primary,
                    ),
                    const Divider(),
                    Text('Social Notifications', style: theme.labelLarge),
                    SwitchListTile(
                      title: Text('New Messages', style: theme.bodyMedium),
                      value: true,
                      onChanged: (value) {},
                      activeColor: theme.primary,
                    ),
                    SwitchListTile(
                      title: Text('New Followers', style: theme.bodyMedium),
                      value: true,
                      onChanged: (value) {},
                      activeColor: theme.primary,
                    ),
                    SwitchListTile(
                      title: Text('Friend Requests', style: theme.bodyMedium),
                      value: true,
                      onChanged: (value) {},
                      activeColor: theme.primary,
                    ),
                    SwitchListTile(
                      title: Text('Post Reactions', style: theme.bodyMedium),
                      value: _notifyPostReactions,
                      onChanged: (value) async {
                        setModalState(() => _notifyPostReactions = value);
                        setState(() => _notifyPostReactions = value);
                        await _updateSetting({'notifyPostReactions': value});
                      },
                      activeColor: theme.primary,
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

  // Theme Settings Dialog
  void _showThemeSettings(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    int selectedTheme = 0; // 0: System, 1: Light, 2: Dark

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Container(
          decoration: BoxDecoration(
            color: theme.secondaryBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.alternate,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Title
              Row(
                children: [
                  Icon(Icons.palette_outlined, color: theme.primary),
                  const SizedBox(width: 12),
                  Text('Choose Theme', style: theme.headlineSmall),
                ],
              ),
              const SizedBox(height: 24),
              // Theme options
              _buildThemeOption(
                context,
                icon: Icons.brightness_auto_rounded,
                title: 'System Default',
                subtitle: 'Follow device settings',
                isSelected: selectedTheme == 0,
                onTap: () => setState(() => selectedTheme = 0),
              ),
              const SizedBox(height: 12),
              _buildThemeOption(
                context,
                icon: Icons.light_mode_rounded,
                title: 'Light Mode',
                subtitle: 'Always use light theme',
                isSelected: selectedTheme == 1,
                onTap: () => setState(() => selectedTheme = 1),
              ),
              const SizedBox(height: 12),
              _buildThemeOption(
                context,
                icon: Icons.dark_mode_rounded,
                title: 'Dark Mode',
                subtitle: 'Always use dark theme',
                isSelected: selectedTheme == 2,
                onTap: () => setState(() => selectedTheme = 2),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // TODO: Implement theme change
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Theme updated successfully')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Apply Theme'),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThemeOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = FlutterFlowTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.primary.withOpacity(0.1)
                : theme.primaryBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? theme.primary : theme.alternate,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.primary.withOpacity(0.2)
                      : theme.alternate,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: isSelected ? theme.primary : theme.secondaryText,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.bodyLarge.override(
                        fontFamily: 'Inter',
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected ? theme.primary : theme.primaryText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.bodySmall.override(
                        fontFamily: 'Inter',
                        color: theme.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, color: theme.primary, size: 24),
            ],
          ),
        ),
      ),
    );
  }

  // Language Settings Dialog
  void _showLanguageSettings(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final languages = [
      {'name': 'English (US)', 'code': 'en_US'},
      {'name': 'English (UK)', 'code': 'en_GB'},
      {'name': 'Español', 'code': 'es'},
      {'name': 'Français', 'code': 'fr'},
      {'name': 'Deutsch', 'code': 'de'},
      {'name': '日本語', 'code': 'ja'},
      {'name': '中文', 'code': 'zh'},
      {'name': 'हिन्दी', 'code': 'hi'},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.65,
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.alternate,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.language_rounded, color: theme.primary),
                  const SizedBox(width: 12),
                  Text('Choose Language', style: theme.headlineSmall),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: languages.length,
                itemBuilder: (context, index) {
                  final language = languages[index];
                  final isSelected =
                      index == 0; // TODO: Connect to actual state
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          // TODO: Implement language change
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Language changed to ${language['name']}'),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? theme.primary.withOpacity(0.1)
                                : theme.primaryBackground,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color:
                                  isSelected ? theme.primary : theme.alternate,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  language['name']!,
                                  style: theme.bodyLarge.override(
                                    fontFamily: 'Inter',
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? theme.primary
                                        : theme.primaryText,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(Icons.check_circle,
                                    color: theme.primary, size: 22),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Text Size Settings Dialog
  void _showTextSizeSettings(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    double textScale = 1.0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Container(
          decoration: BoxDecoration(
            color: theme.secondaryBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.alternate,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Title
              Row(
                children: [
                  Icon(Icons.text_fields_rounded, color: theme.primary),
                  const SizedBox(width: 12),
                  Text('Text Size', style: theme.headlineSmall),
                ],
              ),
              const SizedBox(height: 32),
              // Preview text
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.primaryBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.alternate),
                ),
                child: Column(
                  children: [
                    Text(
                      'Preview',
                      style: theme.bodyLarge.override(
                        fontFamily: 'Inter',
                        fontSize: 14 * textScale,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This is how your text will look with the selected size.',
                      style: theme.bodyMedium.override(
                        fontFamily: 'Inter',
                        fontSize: 13 * textScale,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              // Slider
              Row(
                children: [
                  Icon(Icons.text_decrease, color: theme.secondaryText),
                  Expanded(
                    child: Slider(
                      value: textScale,
                      min: 0.8,
                      max: 1.4,
                      divisions: 6,
                      activeColor: theme.primary,
                      label: '${(textScale * 100).round()}%',
                      onChanged: (value) => setState(() => textScale = value),
                    ),
                  ),
                  Icon(Icons.text_increase, color: theme.secondaryText),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${(textScale * 100).round()}% of default size',
                style: theme.bodySmall.override(
                  fontFamily: 'Inter',
                  color: theme.secondaryText,
                ),
              ),
              const SizedBox(height: 24),
              // Apply button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // TODO: Implement text size change
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Text size updated'),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Apply'),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  // Download Data Dialog
  void _showDownloadData(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.download_rounded, color: theme.primary),
            const SizedBox(width: 12),
            const Text('Download Your Data'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Request a copy of your data',
              style: theme.bodyLarge.override(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'We\'ll prepare a downloadable file containing:',
              style: theme.bodyMedium,
            ),
            const SizedBox(height: 8),
            _buildBulletPoint(context, 'Your profile information'),
            _buildBulletPoint(context, 'Your pulses and events'),
            _buildBulletPoint(context, 'Your posts and messages'),
            _buildBulletPoint(context, 'Your connections and followers'),
            const SizedBox(height: 12),
            Text(
              'This process may take up to 48 hours. You\'ll receive an email when your data is ready to download.',
              style: theme.bodySmall.override(
                fontFamily: 'Inter',
                color: theme.secondaryText,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // TODO: Implement data download request
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'Data download requested. You\'ll receive an email within 48 hours.'),
                ),
              );
            },
            child: const Text('Request Download'),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletPoint(BuildContext context, String text) {
    final theme = FlutterFlowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 4),
      child: Row(
        children: [
          Icon(Icons.circle, size: 6, color: theme.primaryText),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.bodySmall)),
        ],
      ),
    );
  }

  // Storage Settings Dialog
  void _showStorageSettings(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.storage_rounded, color: theme.primary),
            const SizedBox(width: 12),
            const Text('Storage'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Cache'),
              subtitle: const Text('~45 MB'),
              trailing: TextButton(
                onPressed: () {
                  // TODO: Implement cache clearing
                },
                child: const Text('Clear'),
              ),
            ),
            ListTile(
              title: const Text('Downloaded Media'),
              subtitle: const Text('~120 MB'),
              trailing: TextButton(
                onPressed: () {
                  // TODO: Implement media clearing
                },
                child: const Text('Clear'),
              ),
            ),
            ListTile(
              title: const Text('Total Storage Used'),
              subtitle: const Text('~165 MB'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // About Dialog
  void _showAboutDialog(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    showAboutDialog(
      context: context,
      applicationName: 'Pulse',
      applicationVersion: '1.0.0',
      applicationIcon: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [theme.primary, theme.secondary],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 32),
      ),
      applicationLegalese: '© 2025 Pulse. All rights reserved.',
      children: [
        const SizedBox(height: 16),
        Text(
          'Connect with people through real-time events and experiences.',
          style: theme.bodyMedium,
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () {
            // TODO: Open terms
          },
          icon: const Icon(Icons.description_outlined),
          label: const Text('Terms of Service'),
        ),
        TextButton.icon(
          onPressed: () {
            // TODO: Open privacy policy
          },
          icon: const Icon(Icons.privacy_tip_outlined),
          label: const Text('Privacy Policy'),
        ),
      ],
    );
  }

  // Delete Account Dialog
  void _showDeleteAccount(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_rounded, color: theme.error),
            const SizedBox(width: 12),
            const Text('Delete Account'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This action cannot be undone!',
              style: theme.bodyLarge.override(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                color: theme.error,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Deleting your account will:',
              style: theme.bodyMedium,
            ),
            const SizedBox(height: 8),
            _buildBulletPoint(context, 'Permanently delete all your data'),
            _buildBulletPoint(context, 'Remove all your pulses and posts'),
            _buildBulletPoint(context, 'Delete all your messages'),
            _buildBulletPoint(context, 'Remove you from all connections'),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Enter your password to confirm',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (passwordController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter your password')),
                );
                return;
              }
              final confirmed = await _showConfirmDialog(
                context,
                title: 'Final Confirmation',
                message: 'Are you absolutely sure? This cannot be undone.',
              );
              if (confirmed == true) {
                // TODO: Implement account deletion
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.error,
            ),
            child: const Text('Delete My Account'),
          ),
        ],
      ),
    );
  }

  // Confirm Dialog Helper
  Future<bool?> _showConfirmDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
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
        // Load activity statuses for followers
        _loadActivityStatusesForFollowers();
      }
    } catch (e) {
      print('Error fetching followers: $e');
      if (mounted) setState(() => _followers = []);
    } finally {
      if (mounted) setState(() => _loadingFollowers = false);
    }
  }

  Future<void> _loadActivityStatusesForFollowers() async {
    if (_followers.isEmpty) return;

    try {
      final userIds = _followers
          .map((f) => f['id'] as String?)
          .whereType<String>()
          .toList();

      if (userIds.isEmpty) return;

      final statuses = await ApiService.instance.getActivityStatuses(userIds);
      if (mounted && statuses != null) {
        setState(() {
          statuses.forEach((userId, statusData) {
            if (statusData != null && statusData is Map) {
              _activityStatuses[userId] =
                  statusData['status'] as String? ?? 'offline';
            }
          });
        });
      }
    } catch (e) {
      print('Error loading activity statuses: $e');
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
        // Load activity statuses for following
        _loadActivityStatusesForFollowing();
      }
    } catch (e) {
      print('Error fetching following: $e');
      if (mounted) setState(() => _following = []);
    } finally {
      if (mounted) setState(() => _loadingFollowing = false);
    }
  }

  Future<void> _loadActivityStatusesForFollowing() async {
    if (_following.isEmpty) return;

    try {
      final userIds = _following
          .map((f) => f['id'] as String?)
          .whereType<String>()
          .toList();

      if (userIds.isEmpty) return;

      final statuses = await ApiService.instance.getActivityStatuses(userIds);
      if (mounted && statuses != null) {
        setState(() {
          statuses.forEach((userId, statusData) {
            if (statusData != null && statusData is Map) {
              _activityStatuses[userId] =
                  statusData['status'] as String? ?? 'offline';
            }
          });
        });
      }
    } catch (e) {
      print('Error loading activity statuses: $e');
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
                      SliverToBoxAdapter(child: _buildHighlights(context)),
                      SliverAppBar(
                        pinned: true,
                        backgroundColor: theme.primaryBackground,
                        elevation: 0,
                        toolbarHeight: 0,
                        bottom: PreferredSize(
                          preferredSize: const Size.fromHeight(72),
                          child: _buildTabs(context),
                        ),
                      ),
                      // Build tab content as slivers instead of widgets
                      ..._buildTabContentSlivers(context),
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

  Widget _buildHighlights(BuildContext context) {
    final userId = currentUser?.uid;
    if (userId == null) return const SizedBox.shrink();

    return HighlightsRow(
      userId: userId,
      isOwnProfile: true,
      onHighlightTap: (highlight) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => HighlightViewerPage(
              highlightId: highlight['id'] as String,
            ),
          ),
        );
      },
      onCreateTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const ManageHighlightPage(),
          ),
        );
      },
    );
  }

  Widget _buildTabs(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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

  List<Widget> _buildTabContentSlivers(BuildContext context) {
    // Return slivers based on the current tab index
    switch (_tabController.index) {
      case 0:
        return _buildMyEventsTabSlivers(context);
      case 1:
        return _buildMyPostsTabSlivers(context);
      case 2:
        return _buildConnectionsTabSlivers(context);
      default:
        return _buildMyEventsTabSlivers(context);
    }
  }

  List<Widget> _buildMyEventsTabSlivers(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    if (_loadingCreated && _loadingJoined) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Center(
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
            ),
          ),
        ),
      ];
    }

    final bool showCreated = _eventsFilterIndex == 0;
    final List<Map<String, dynamic>> visible = showCreated ? _created : _joined;

    List<Widget> slivers = [
      SliverToBoxAdapter(child: _buildEventsFilter(context)),
      const SliverToBoxAdapter(child: SizedBox(height: 12)),
    ];

    if (visible.isEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: _buildEmptyState(
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
          ),
        ),
      );
    } else {
      slivers.add(
        SliverToBoxAdapter(
          child: _buildSectionHeader(
            context,
            icon:
                showCreated ? Icons.auto_awesome_rounded : Icons.group_rounded,
            title: showCreated ? 'Created by you' : 'You joined',
            color: showCreated ? theme.primary : Colors.teal,
          ),
        ),
      );

      slivers.add(
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final pulse = visible[index];
              return PulseCardWidgetMaterial(
                pulse: pulse,
                onTap: () async {
                  await Haptics.vibrate(HapticsType.selection);
                  // Navigate to pulse details
                },
              ).animate().fadeIn(duration: 300.ms).slideX(begin: 0.05, end: 0);
            },
            childCount: visible.length,
          ),
        ),
      );
    }

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 16)));

    return slivers;
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

  List<Widget> _buildMyPostsTabSlivers(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    if (_loadingPosts) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Center(
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
            ),
          ),
        ),
      ];
    }

    if (_posts.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: _buildEmptyState(
            context,
            icon: Icons.post_add_rounded,
            title: 'No posts yet',
            subtitle: 'Share updates and moments from your events.',
            actionText: 'Create Post',
            onAction: () {
              _showCreatePostSheet(context);
            },
          ),
        ),
      ];
    }

    return [
      SliverToBoxAdapter(
        child: Padding(
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
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildPostCard(context, _posts[index]),
          childCount: _posts.length,
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
    ];
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

  List<Widget> _buildConnectionsTabSlivers(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return [
      // Followers section header
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        sliver: SliverToBoxAdapter(
          child: _buildSectionHeader(
            context,
            icon: Icons.people_rounded,
            title: 'Followers ($_followersCount)',
            color: Colors.teal,
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 12)),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(child: _buildFollowersGrid(context)),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),

      // Following section header
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(
          child: _buildSectionHeader(
            context,
            icon: Icons.person_add_rounded,
            title: 'Following ($_followingCount)',
            color: theme.primary,
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 12)),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(child: _buildFollowingGrid(context)),
      ),
    ];
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
        final userId = user['id'] as String?;
        final name = (user['displayName'] as String?)?.trim();
        final avatar = (user['profileImageUrl'] as String?)?.trim();
        final activityStatus =
            userId != null ? _activityStatuses[userId] : null;

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
              Stack(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: theme.primary.withOpacity(0.1),
                    backgroundImage: (avatar != null && avatar.isNotEmpty)
                        ? NetworkImage(avatar)
                        : null,
                    child: (avatar == null || avatar.isEmpty)
                        ? Icon(Icons.person_rounded,
                            color: theme.primary, size: 32)
                        : null,
                  ),
                  if (activityStatus != null)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: _getActivityStatusColor(activityStatus),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.secondaryBackground,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
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
        final userId = user['id'] as String?;
        final name = (user['displayName'] as String?)?.trim();
        final avatar = (user['profileImageUrl'] as String?)?.trim();
        final activityStatus =
            userId != null ? _activityStatuses[userId] : null;

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
              Stack(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: theme.primary.withOpacity(0.1),
                    backgroundImage: (avatar != null && avatar.isNotEmpty)
                        ? NetworkImage(avatar)
                        : null,
                    child: (avatar == null || avatar.isEmpty)
                        ? Icon(Icons.person_rounded,
                            color: theme.primary, size: 32)
                        : null,
                  ),
                  if (activityStatus != null)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: _getActivityStatusColor(activityStatus),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.secondaryBackground,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
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

  Color _getActivityStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'online':
        return Colors.green;
      case 'away':
        return Colors.orange;
      case 'busy':
      case 'dnd':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
