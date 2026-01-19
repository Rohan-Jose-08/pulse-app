import 'package:flutter/material.dart';
import '../flutter_flow/flutter_flow_theme.dart';
import '../flutter_flow/flutter_flow_icon_button.dart';
import '../components/modern_bottom_sheets.dart';
import '../components/swipe_gestures.dart';
import '../components/modern_search.dart';
import '../components/contextual_menus.dart';
import '../components/enhanced_loading_states.dart';
import '../components/theme_toggle.dart';
import '../utils/modern_transitions.dart';
import '../utils/haptic_utils.dart';
import '../utils/animations.dart';
import '../main.dart';

/// Showcase page demonstrating all modern UX improvements
class ModernUXShowcase extends StatefulWidget {
  const ModernUXShowcase({Key? key}) : super(key: key);

  @override
  State<ModernUXShowcase> createState() => _ModernUXShowcaseState();
}

class _ModernUXShowcaseState extends State<ModernUXShowcase> {
  int _selectedTab = 0;
  bool _isLoading = false;
  double _progress = 0.0;
  final Set<String> _selectedFilters = {};

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.secondaryBackground,
        elevation: 0,
        leading: FlutterFlowIconButton(
          borderColor: Colors.transparent,
          borderRadius: 30,
          buttonSize: 46,
          icon: Icon(
            Icons.arrow_back_rounded,
            color: theme.primaryText,
            size: 24,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Modern UX Showcase',
          style: theme.headlineSmall,
        ),
        actions: [
          ThemeToggle(
            currentMode: MyApp.of(context).themeMode,
            isCompact: true,
          ),
          const SizedBox(width: 8),
          ModernDropdownMenu(
            icon: Icons.more_vert,
            items: [
              DropdownMenuItem(
                label: 'Settings',
                icon: Icons.settings,
                onTap: () {},
              ),
              DropdownMenuItem(
                label: 'Help',
                icon: Icons.help_outline,
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Modern Tab Bar
            SlideInFromBottom(
              child: _buildSection(
                theme,
                'Tab Navigation',
                ModernTabBar(
                  tabs: const ['All', 'Active', 'Completed'],
                  selectedIndex: _selectedTab,
                  onTap: (index) => setState(() => _selectedTab = index),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Modern Search
            SlideInFromBottom(
              delay: const Duration(milliseconds: 100),
              child: _buildSection(
                theme,
                'Search Bar',
                ModernSearchBar(
                  hintText: 'Search anything...',
                  onChanged: (query) {},
                  trailing: [
                    IconButton(
                      icon: const Icon(Icons.mic, size: 20),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Search Filters
            SlideInFromBottom(
              delay: const Duration(milliseconds: 200),
              child: _buildSection(
                theme,
                'Filter Chips',
                SearchFilters(
                  filters: const [
                    FilterChip(id: 'nearby', label: 'Nearby'),
                    FilterChip(id: 'today', label: 'Today'),
                    FilterChip(id: 'popular', label: 'Popular'),
                    FilterChip(id: 'video', label: 'Video'),
                  ],
                  selectedFilters: _selectedFilters,
                  onChanged: (filters) {
                    setState(() => _selectedFilters
                      ..clear()
                      ..addAll(filters));
                  },
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Swipeable List Items
            SlideInFromBottom(
              delay: const Duration(milliseconds: 300),
              child: _buildSection(
                theme,
                'Swipeable Items',
                Column(
                  children: List.generate(3, (index) {
                    return SwipeableListItem(
                      leftActions: [
                        SwipeAction(
                          icon: Icons.archive,
                          backgroundColor: Colors.blue,
                          onTap: () => _showSnackbar(context, 'Archived'),
                        ),
                      ],
                      rightActions: [
                        SwipeAction(
                          icon: Icons.delete,
                          backgroundColor: theme.error,
                          onTap: () => _showSnackbar(context, 'Deleted'),
                        ),
                      ],
                      onTap: () {},
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.secondaryBackground,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            EnhancedSkeleton.circle(size: 40),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Swipe me left or right',
                                    style: theme.bodyLarge.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Try swiping to see actions',
                                    style: theme.bodySmall.copyWith(
                                      color: theme.secondaryText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Loading States
            SlideInFromBottom(
              delay: const Duration(milliseconds: 400),
              child: _buildSection(
                theme,
                'Loading States',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() => _isLoading = !_isLoading);
                            },
                            child: Text(_isLoading ? 'Stop' : 'Show Loading'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_isLoading) ...[
                      const Center(child: PulsingDots()),
                      const SizedBox(height: 16),
                      const Center(
                        child: ModernLoadingIndicator(
                          message: 'Loading content...',
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    ModernProgressBar(
                      progress: _progress,
                      label: 'Upload Progress',
                      showPercentage: true,
                    ),
                    const SizedBox(height: 8),
                    Slider(
                      value: _progress,
                      onChanged: (value) => setState(() => _progress = value),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Skeleton Loaders
            SlideInFromBottom(
              delay: const Duration(milliseconds: 500),
              child: _buildSection(
                theme,
                'Skeleton Loaders',
                const CardSkeleton(
                  showAvatar: true,
                  showImage: true,
                  lineCount: 2,
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Action Buttons
            SlideInFromBottom(
              delay: const Duration(milliseconds: 600),
              child: _buildSection(
                theme,
                'Dialogs & Bottom Sheets',
                Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _showModernBottomSheet(context),
                            icon: const Icon(Icons.menu),
                            label: const Text('Bottom Sheet'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _showActionSheet(context),
                            icon: const Icon(Icons.more_horiz),
                            label: const Text('Actions'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _showConfirmDialog(context),
                            icon: const Icon(Icons.warning_outlined),
                            label: const Text('Confirm'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _navigateWithTransition(context),
                            icon: const Icon(Icons.arrow_forward),
                            label: const Text('Transition'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Segmented Control
            SlideInFromBottom(
              delay: const Duration(milliseconds: 700),
              child: _buildSection(
                theme,
                'Segmented Control',
                ModernSegmentedControl(
                  segments: const ['Map', 'List', 'Grid'],
                  selectedIndex: 0,
                  onChanged: (index) {},
                ),
              ),
            ),

            const SizedBox(height: 100),
          ],
        ),
      ),
      floatingActionButton: FloatingActionMenu(
        mainIcon: Icons.add,
        items: [
          FloatingMenuItem(
            icon: Icons.photo_camera,
            label: 'Camera',
            onTap: () => _showSnackbar(context, 'Camera'),
          ),
          FloatingMenuItem(
            icon: Icons.photo_library,
            label: 'Gallery',
            onTap: () => _showSnackbar(context, 'Gallery'),
          ),
          FloatingMenuItem(
            icon: Icons.create,
            label: 'Text',
            onTap: () => _showSnackbar(context, 'Text'),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(FlutterFlowTheme theme, String title, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            title,
            style: theme.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        child,
      ],
    );
  }

  void _showModernBottomSheet(BuildContext context) {
    ModernBottomSheet.show(
      context: context,
      title: 'Modern Bottom Sheet',
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text(
              'This is a modern, draggable bottom sheet with smooth animations. '
              'Try dragging it up and down!',
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  void _showActionSheet(BuildContext context) {
    ActionBottomSheet.show(
      context: context,
      title: 'Quick Actions',
      subtitle: 'Choose an action',
      actions: [
        ActionSheetItem(
          title: 'Share',
          icon: Icons.share,
          onTap: () => _showSnackbar(context, 'Shared'),
        ),
        ActionSheetItem(
          title: 'Edit',
          icon: Icons.edit,
          onTap: () => _showSnackbar(context, 'Editing'),
        ),
        ActionSheetItem(
          title: 'Delete',
          icon: Icons.delete,
          isDestructive: true,
          onTap: () => _showSnackbar(context, 'Deleted'),
        ),
      ],
    );
  }

  void _showConfirmDialog(BuildContext context) async {
    final confirmed = await ModernConfirmDialog.show(
      context: context,
      title: 'Are you sure?',
      message: 'This action requires confirmation',
      confirmText: 'Yes, Continue',
      cancelText: 'Cancel',
      isDestructive: true,
    );

    if (confirmed && context.mounted) {
      _showSnackbar(context, 'Confirmed!');
    }
  }

  void _navigateWithTransition(BuildContext context) {
    Navigator.push(
      context,
      ModernTransitions.fadeScale(_TransitionDemoPage()),
    );
  }

  void _showSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _TransitionDemoPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.secondaryBackground,
        title: const Text('Smooth Transition'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 80, color: Colors.green),
            const SizedBox(height: 24),
            Text(
              'Beautiful Transition!',
              style: theme.headlineMedium,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }
}
