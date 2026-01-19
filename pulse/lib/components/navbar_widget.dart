import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
// removed unused: flutter_flow_widgets.dart
import 'dart:ui';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
// removed unused: provider.dart
import 'navbar_model.dart';
import '/pages/search/search_widget.dart';
import '/pages/search_explore/search_explore_page.dart';
import '/pages/discovery/pulse_discovery_map_page.dart'; // legacy map (kept for backward compatibility)
import '/pages/map/dual_layer_map_page.dart';
import '/pages/create_pulse/create_pulse_widget.dart';
import '/pages/profile/profile_widget.dart';
import '/pages/messaging/messages_hub_widget.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '/backend/api_service.dart';
import '/backend/socket_service.dart';
import '/auth/firebase_auth/auth_util.dart';

export 'navbar_model.dart';

class NavbarWidget extends StatefulWidget {
  const NavbarWidget({super.key});

  @override
  State<NavbarWidget> createState() => _NavbarWidgetState();
}

class _NavbarWidgetState extends State<NavbarWidget>
    with TickerProviderStateMixin {
  late NavbarModel _model;
  late AnimationController _animationController;
  late AnimationController _pulseAnimationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _pulseAnimation;

  int _selectedIndex = 0;
  int _previousIndex = 0;
  bool _hasUnreadMessages = false;
  int _unreadCount = 0;
  StreamSubscription<Map<String, dynamic>>? _conversationSub;

  static const String _kLastMessagesVisitKey = '__last_messages_visit__';

  // Modern color scheme
  static const _primaryGradient = [Color(0xFF6366F1), Color(0xFF8B5CF6)];
  static const _createGradient = [Color(0xFFEC4899), Color(0xFFF43F5E)];

  @override
  void setState(VoidCallback callback) {
    super.setState(callback);
    _model.onUpdate();
  }

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => NavbarModel());

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _pulseAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.elasticOut,
      ),
    );

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _pulseAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateSelectedIndexFromRoute();
      _initUnreadTracking();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateSelectedIndexFromRoute();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pulseAnimationController.dispose();
    _conversationSub?.cancel();
    _model.dispose();
    super.dispose();
  }

  void _updateSelectedIndexFromRoute() {
    final currentRoute =
        GoRouter.of(context).routerDelegate.currentConfiguration.uri.toString();

    setState(() {
      if (currentRoute == '/' || currentRoute == SearchWidget.routePath) {
        _selectedIndex = 0; // Search
      } else if (currentRoute == DualLayerMapPage.routePath ||
          currentRoute == PulseDiscoveryMapPage.routePath) {
        _selectedIndex = 1; // Map (new dual layer)
      } else if (currentRoute == SearchExplorePage.routePath) {
        _selectedIndex = 2; // Explore
      } else if (currentRoute == CreatePulseWidget.routePath) {
        _selectedIndex = 3;
      } else if (currentRoute == MessagesHubWidget.routePath ||
          currentRoute.contains('messages')) {
        _selectedIndex = 4;
        _markMessagesVisited();
      } else if (currentRoute.contains('profile')) {
        _selectedIndex = 5;
      }
    });
  }

  void _onItemTapped(int index) {
    if (_selectedIndex == index) return;

    // Haptic feedback
    HapticFeedback.selectionClick();

    setState(() {
      _previousIndex = _selectedIndex;
      _selectedIndex = index;
    });

    _animationController.forward().then((_) {
      _animationController.reverse();
    });

    switch (index) {
      case 0:
        context.goNamed(SearchWidget.routeName);
        break;
      case 1:
        context.goNamed(DualLayerMapPage.routeName);
        break;
      case 2:
        context.goNamed(SearchExplorePage.routeName);
        break;
      case 3:
        HapticFeedback.mediumImpact();
        context.goNamed(CreatePulseWidget.routeName);
        break;
      case 4:
        _markMessagesVisited();
        try {
          context.goNamed(MessagesHubWidget.routeName);
        } catch (_) {
          context.go(MessagesHubWidget.routePath);
        }
        break;
      case 5:
        context.goNamed(ProfileWidget.routeName);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Container(
        width: double.infinity,
        height: 80.0 + bottomInset,
        decoration: BoxDecoration(
          color: (isDark ? const Color(0xFF1A1A2E) : Colors.white)
              .withOpacity(0.92),
          boxShadow: [
            BoxShadow(
              blurRadius: 30.0,
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
              offset: const Offset(0.0, -8.0),
              spreadRadius: 0.0,
            ),
          ],
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(28.0),
            topRight: Radius.circular(28.0),
          ),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(28.0),
            topRight: Radius.circular(28.0),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
            child: Padding(
              padding: EdgeInsets.fromLTRB(8.0, 6.0, 8.0, 6.0 + bottomInset),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildNavItem(0, Icons.home_rounded, 'Home', theme, isDark),
                  _buildNavItem(1, Icons.map_rounded, 'Map', theme, isDark),
                  _buildNavItem(
                      2, Icons.explore_rounded, 'Explore', theme, isDark),
                  _buildCreateButton(theme, isDark),
                  _buildNavItem(
                      4, Icons.chat_bubble_rounded, 'Chat', theme, isDark),
                  _buildNavItem(
                      5, Icons.person_rounded, 'Profile', theme, isDark),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label,
      FlutterFlowTheme theme, bool isDark) {
    final isSelected = _selectedIndex == index;
    final showUnread = index == 4 && !isSelected && _hasUnreadMessages;
    final effectiveIcon = showUnread ? Icons.mark_chat_unread_rounded : icon;

    return GestureDetector(
      onTap: () => _onItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    width: isSelected ? 48.0 : 42.0,
                    height: isSelected ? 36.0 : 32.0,
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? LinearGradient(
                              colors: _primaryGradient,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: isSelected ? null : Colors.transparent,
                      borderRadius: BorderRadius.circular(12.0),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: _primaryGradient[0].withOpacity(0.4),
                                blurRadius: 12.0,
                                offset: const Offset(0, 4),
                                spreadRadius: -2,
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: AnimatedScale(
                        scale: isSelected ? 1.1 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          effectiveIcon,
                          color: isSelected
                              ? Colors.white
                              : (isDark ? Colors.grey[400] : Colors.grey[600]),
                          size: isSelected ? 22.0 : 20.0,
                        ),
                      ),
                    ),
                  ),
                  // Unread badge
                  if (showUnread)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _pulseAnimation.value,
                            child: child,
                          );
                        },
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFEF4444), Color(0xFFF97316)],
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF1A1A2E)
                                  : Colors.white,
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFEF4444).withOpacity(0.5),
                                blurRadius: 8,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              _unreadCount > 9
                                  ? '9+'
                                  : (_unreadCount > 0 ? '$_unreadCount' : ''),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: GoogleFonts.inter(
                  fontSize: isSelected ? 11.0 : 10.0,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? _primaryGradient[0]
                      : (isDark ? Colors.grey[400] : Colors.grey[600]),
                  letterSpacing: isSelected ? 0.3 : 0,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreateButton(FlutterFlowTheme theme, bool isDark) {
    final isSelected = _selectedIndex == 3;

    return GestureDetector(
      onTap: () => _onItemTapped(3),
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              width: isSelected ? 52.0 : 48.0,
              height: isSelected ? 40.0 : 36.0,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isSelected ? _primaryGradient : _createGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14.0),
                boxShadow: [
                  BoxShadow(
                    color:
                        (isSelected ? _primaryGradient[0] : _createGradient[0])
                            .withOpacity(0.5),
                    blurRadius: isSelected ? 16.0 : 12.0,
                    offset: const Offset(0, 4),
                    spreadRadius: isSelected ? 0 : -2,
                  ),
                ],
              ),
              child: Center(
                child: AnimatedRotation(
                  turns: isSelected ? 0.125 : 0,
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    Icons.add_rounded,
                    color: Colors.white,
                    size: isSelected ? 26.0 : 24.0,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: GoogleFonts.inter(
                fontSize: isSelected ? 11.0 : 10.0,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? _primaryGradient[0]
                    : (isDark ? _createGradient[0] : _createGradient[1]),
                letterSpacing: isSelected ? 0.3 : 0,
              ),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _initUnreadTracking() async {
    try {
      // Ensure socket is connected to receive real-time updates
      // Safe to call multiple times: internal guards prevent duplicate connects
      // and it will authenticate using current Firebase ID token.
      SocketService.instance.connect();

      final prefs = await SharedPreferences.getInstance();
      final lastVisitIso = prefs.getString(_kLastMessagesVisitKey);
      DateTime? lastVisit =
          lastVisitIso != null ? DateTime.tryParse(lastVisitIso) : null;

      // Establish a baseline on first run to avoid false-positive unread indicator
      if (lastVisit == null) {
        final now = DateTime.now();
        await prefs.setString(_kLastMessagesVisitKey, now.toIso8601String());
        lastVisit = now;
      }

      // Initial unread check based on conversations updated after last visit
      try {
        final convos = await ApiService.instance.listConversations();
        if (convos != null && convos.isNotEmpty) {
          final hasNewer = convos.any((c) {
            final updatedAt =
                DateTime.tryParse(c['updatedAt']?.toString() ?? '');
            if (updatedAt == null) return false;
            // Optional: if backend sends lastSenderId, ignore my own messages
            final lastSenderId = c['lastSenderId']?.toString();
            final isMine =
                lastSenderId != null && lastSenderId == currentUserUid;
            return updatedAt.isAfter(lastVisit!) && !isMine;
          });
          if (mounted) setState(() => _hasUnreadMessages = hasNewer);
        }
      } catch (_) {
        // ignore network errors on initial check
      }

      // Real-time: any conversation update while not on Messages marks unread
      _conversationSub = SocketService.instance.conversationUpdates.listen((d) {
        if (!mounted) return;
        final lastSenderId = d['lastSenderId']?.toString();
        final isMine = lastSenderId != null && lastSenderId == currentUserUid;
        if (_selectedIndex != 3 && !isMine) {
          setState(() => _hasUnreadMessages = true);
        }
      });
    } catch (_) {
      // no-op
    }
  }

  Future<void> _markMessagesVisited() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _kLastMessagesVisitKey, DateTime.now().toIso8601String());
      if (mounted) setState(() => _hasUnreadMessages = false);
    } catch (_) {
      // ignore
    }
  }
}
