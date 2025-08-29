import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'dart:ui';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'navbar_model.dart';
// removed unused: '/pages/search/search_widget.dart'
import '/pages/search_explore/search_explore_page.dart';
import '/pages/create_pulse/create_pulse_widget.dart';
import '/pages/messaging/messages_hub_widget.dart';
import '/pages/profile/profile_widget.dart';

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

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  @override
  void dispose() {
    _model.maybeDispose();
    _animationController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

    _animationController.forward().then((_) {
      _animationController.reverse();
    });

    // Navigate to appropriate route
    switch (index) {
      case 0:
        context.pushNamed(SearchExplorePage.routeName);
        break;
      case 1:
        context.pushNamed(SearchExplorePage.routeName);
        break;
      case 2:
        context.pushNamed(CreatePulseWidget.routeName);
        break;
      case 3:
        context.pushNamed(MessagesHubWidget.routeName);
        break;
      case 4:
        context.pushNamed(ProfileWidget.routeName);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Transform.translate(
      offset: const Offset(0, -19),
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
                    _buildNavItem(0, Icons.search_rounded, 'Search'),
                    _buildNavItem(1, Icons.explore_rounded, 'Explore'),
                    _buildNavItem(2, Icons.add_circle_rounded, 'Create'),
                    _buildNavItem(3, Icons.chat_bubble_rounded, 'Messages'),
                    _buildNavItem(4, Icons.person_rounded, 'Profile'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final theme = FlutterFlowTheme.of(context);
    final isSelected = _selectedIndex == index;

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
                  icon,
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
}
