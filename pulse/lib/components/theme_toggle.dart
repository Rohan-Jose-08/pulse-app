import 'package:flutter/material.dart';
import '../flutter_flow/flutter_flow_theme.dart';
import '../main.dart';
import '../utils/haptic_utils.dart';

/// Modern theme toggle widget with smooth animations
class ThemeToggle extends StatelessWidget {
  final ThemeMode currentMode;
  final bool showLabel;
  final bool isCompact;

  const ThemeToggle({
    super.key,
    required this.currentMode,
    this.showLabel = true,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final isDark = currentMode == ThemeMode.dark;

    if (isCompact) {
      return IconButton(
        icon: AnimatedSwitcher(
          duration: AppAnimation.normal,
          transitionBuilder: (child, animation) {
            return RotationTransition(
              turns: animation,
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          child: Icon(
            isDark ? Icons.dark_mode : Icons.light_mode,
            key: ValueKey(isDark),
            color: theme.primaryText,
          ),
        ),
        onPressed: () => _toggleTheme(context),
      );
    }

    return InkWell(
      onTap: () => _toggleTheme(context),
      borderRadius: BorderRadius.circular(AppRadius.xxl),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: showLabel ? AppSpacing.m : AppSpacing.s,
          vertical: AppSpacing.s,
        ),
        decoration: BoxDecoration(
          color: theme.alternate,
          borderRadius: BorderRadius.circular(AppRadius.xxl),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Sun/Moon icon with rotation animation
            AnimatedSwitcher(
              duration: AppAnimation.normal,
              transitionBuilder: (child, animation) {
                return RotationTransition(
                  turns: Tween(begin: 0.5, end: 1.0).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              child: Icon(
                isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                key: ValueKey(isDark),
                color: theme.primaryText,
                size: 20,
              ),
            ),
            if (showLabel) ...[
              const SizedBox(width: AppSpacing.s),
              Text(
                isDark ? 'Dark' : 'Light',
                style: theme.bodyMedium.override(
                  color: theme.primaryText,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _toggleTheme(BuildContext context) {
    HapticUtils.light();
    final newMode =
        currentMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    MyApp.of(context).setThemeMode(newMode);
  }
}

/// Modern segmented theme selector (Light / System / Dark)
class ThemeSelector extends StatelessWidget {
  final ThemeMode currentMode;

  const ThemeSelector({
    super.key,
    required this.currentMode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.alternate,
        borderRadius: BorderRadius.circular(AppRadius.l),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildOption(
            context,
            theme,
            'Light',
            Icons.light_mode_rounded,
            ThemeMode.light,
          ),
          const SizedBox(width: 4),
          _buildOption(
            context,
            theme,
            'System',
            Icons.settings_suggest_rounded,
            ThemeMode.system,
          ),
          const SizedBox(width: 4),
          _buildOption(
            context,
            theme,
            'Dark',
            Icons.dark_mode_rounded,
            ThemeMode.dark,
          ),
        ],
      ),
    );
  }

  Widget _buildOption(
    BuildContext context,
    FlutterFlowTheme theme,
    String label,
    IconData icon,
    ThemeMode mode,
  ) {
    final isSelected = currentMode == mode;

    return Expanded(
      child: InkWell(
        onTap: () {
          HapticUtils.light();
          MyApp.of(context).setThemeMode(mode);
        },
        borderRadius: BorderRadius.circular(AppRadius.m),
        child: AnimatedContainer(
          duration: AppAnimation.normal,
          curve: AppAnimation.emphasized,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.m,
            vertical: AppSpacing.s,
          ),
          decoration: BoxDecoration(
            color: isSelected ? theme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.m),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : theme.secondaryText,
                size: 20,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: theme.bodySmall.override(
                  color: isSelected ? Colors.white : theme.secondaryText,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Floating theme toggle button for quick access
class FloatingThemeToggle extends StatelessWidget {
  final ThemeMode currentMode;

  const FloatingThemeToggle({
    super.key,
    required this.currentMode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final isDark = currentMode == ThemeMode.dark;

    return FloatingActionButton.small(
      onPressed: () {
        HapticUtils.medium();
        final newMode =
            currentMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
        MyApp.of(context).setThemeMode(newMode);
      },
      backgroundColor: theme.primary,
      elevation: AppElevation.high,
      child: AnimatedSwitcher(
        duration: AppAnimation.normal,
        transitionBuilder: (child, animation) {
          return RotationTransition(
            turns: Tween(begin: 0.5, end: 1.0).animate(animation),
            child: ScaleTransition(scale: animation, child: child),
          );
        },
        child: Icon(
          isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          key: ValueKey(isDark),
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Theme toggle list tile for settings pages
class ThemeToggleListTile extends StatelessWidget {
  final ThemeMode currentMode;

  const ThemeToggleListTile({
    super.key,
    required this.currentMode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final isDark = currentMode == ThemeMode.dark;

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(AppSpacing.s),
        decoration: BoxDecoration(
          color: theme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(AppRadius.m),
        ),
        child: Icon(
          isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
          color: theme.primary,
          size: 20,
        ),
      ),
      title: Text(
        'Theme',
        style: theme.bodyLarge.override(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        isDark ? 'Dark mode' : 'Light mode',
        style: theme.bodySmall.override(
          color: theme.secondaryText,
        ),
      ),
      trailing: Switch.adaptive(
        value: isDark,
        onChanged: (value) {
          HapticUtils.light();
          MyApp.of(context).setThemeMode(
            value ? ThemeMode.dark : ThemeMode.light,
          );
        },
        activeColor: theme.primary,
      ),
      onTap: () {
        HapticUtils.light();
        final newMode =
            currentMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
        MyApp.of(context).setThemeMode(newMode);
      },
    );
  }
}
