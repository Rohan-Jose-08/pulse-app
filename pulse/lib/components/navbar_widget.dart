import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
// removed unused: flutter_flow_widgets.dart
import 'dart:ui';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
// removed unused: provider.dart
import 'navbar_model.dart';
import '/pages/search/search_widget.dart';
import '/pages/search_explore/search_explore_page.dart';
import '/pages/discovery/pulse_discovery_map_page.dart';
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
    with SingleTickerProviderStateMixin {
  late NavbarModel _model;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  int _selectedIndex = 0;
  bool _hasUnreadMessages = false;
  StreamSubscription<Map<String, dynamic>>? _conversationSub;

  static const String _kLastMessagesVisitKey = '__last_messages_visit__';

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
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutBack,
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
      } else if (currentRoute == PulseDiscoveryMapPage.routePath) {
        _selectedIndex = 1; // Map
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

    setState(() {
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
        context.goNamed(PulseDiscoveryMapPage.routeName);
        break;
      case 2:
        context.goNamed(SearchExplorePage.routeName);
        break;
      case 3:
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

    return Transform.translate(
      offset: const Offset(0, -22),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.transparent,
        ),
        child: Container(
          width: double.infinity,
          height: 80.0,
          decoration: BoxDecoration(
            color: theme.secondaryBackground.withOpacity(0.95),
            boxShadow: [
              BoxShadow(
                blurRadius: 20.0,
                color: Colors.black.withOpacity(0.1),
                offset: const Offset(0.0, -5.0),
                spreadRadius: 0.0,
              )
            ],
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24.0),
              topRight: Radius.circular(24.0),
            ),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24.0),
              topRight: Radius.circular(24.0),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20.0, vertical: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildNavItem(0, Icons.search_rounded, 'Search',
                        SearchWidget.routePath),
                    _buildNavItem(1, Icons.public_rounded, 'Map',
                        PulseDiscoveryMapPage.routePath),
                    _buildNavItem(2, Icons.explore_rounded, 'Explore',
                        SearchExplorePage.routePath),
                    _buildNavItem(3, Icons.add_circle_rounded, 'Create',
                        CreatePulseWidget.routePath),
                    _buildNavItem(
                        4, Icons.chat_bubble_rounded, 'Messages', '/messages'),
                    _buildNavItem(
                        5, Icons.person_rounded, 'Profile', '/profile'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
      int index, IconData icon, String label, String routePath) {
    final theme = FlutterFlowTheme.of(context);
    final isSelected = _selectedIndex == index;
    final showUnread = index == 4 &&
        !isSelected &&
        _hasUnreadMessages; // messages index shifted
    final effectiveIcon = showUnread ? Icons.mark_chat_unread_rounded : icon;

    return GestureDetector(
      onTap: () => _onItemTapped(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              width: isSelected ? 50.0 : 40.0,
              height: isSelected ? 50.0 : 40.0,
              decoration: BoxDecoration(
                gradient: isSelected
                    ? LinearGradient(
                        colors: [
                          Color(0xFF6366F1),
                          Color(0xFF8B5CF6),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isSelected ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(isSelected ? 16.0 : 12.0),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Color(0xFF6366F1).withOpacity(0.3),
                          blurRadius: 12.0,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: ScaleTransition(
                scale: isSelected
                    ? _scaleAnimation
                    : const AlwaysStoppedAnimation(1.0),
                child: Icon(
                  effectiveIcon,
                  color: isSelected ? Colors.white : theme.secondaryText,
                  size: isSelected ? 24.0 : 22.0,
                ),
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: GoogleFonts.inter(
                fontSize: isSelected ? 12.0 : 11.0,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? Color(0xFF6366F1) : theme.secondaryText,
              ),
              child: Text(label),
            ),
            if (isSelected) ...[
              const SizedBox(height: 2),
              Container(
                width: 20.0,
                height: 2.0,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF6366F1),
                      Color(0xFF8B5CF6),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(1.0),
                ),
              ),
            ],
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
