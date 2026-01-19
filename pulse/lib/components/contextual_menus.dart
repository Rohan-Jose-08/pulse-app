import 'package:flutter/material.dart';
import '../flutter_flow/flutter_flow_theme.dart';
import '../utils/haptic_utils.dart';

/// Modern floating action menu (speed dial pattern)
class FloatingActionMenu extends StatefulWidget {
  final IconData mainIcon;
  final List<FloatingMenuItem> items;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const FloatingActionMenu({
    Key? key,
    this.mainIcon = Icons.add,
    required this.items,
    this.backgroundColor,
    this.foregroundColor,
  }) : super(key: key);

  @override
  State<FloatingActionMenu> createState() => _FloatingActionMenuState();
}

class _FloatingActionMenuState extends State<FloatingActionMenu>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() async {
    setState(() => _isOpen = !_isOpen);
    await HapticUtils.medium();
    if (_isOpen) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Menu items
        ...List.generate(widget.items.length, (index) {
          final item = widget.items[widget.items.length - 1 - index];
          return _buildMenuItem(item, index, theme);
        }),

        // Main FAB
        const SizedBox(height: 16),
        FloatingActionButton(
          onPressed: _toggle,
          backgroundColor: widget.backgroundColor ?? theme.primary,
          foregroundColor: widget.foregroundColor ?? Colors.white,
          elevation: 4,
          child: AnimatedRotation(
            turns: _isOpen ? 0.125 : 0,
            duration: const Duration(milliseconds: 250),
            child: Icon(widget.mainIcon),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuItem(
      FloatingMenuItem item, int index, FlutterFlowTheme theme) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final slideValue = Curves.easeOut.transform(_controller.value);
        final opacity = _controller.value;

        return Transform.translate(
          offset: Offset(0, (1 - slideValue) * 50),
          child: Opacity(
            opacity: opacity,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Label
                  if (item.label != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: theme.secondaryBackground,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        item.label!,
                        style: theme.bodyMedium.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),
                  // Mini FAB
                  Material(
                    elevation: 4,
                    shape: const CircleBorder(),
                    color: item.backgroundColor ?? theme.secondary,
                    child: InkWell(
                      onTap: () async {
                        await HapticUtils.light();
                        _toggle();
                        item.onTap();
                      },
                      customBorder: const CircleBorder(),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Icon(
                          item.icon,
                          size: 24,
                          color: item.foregroundColor ?? Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class FloatingMenuItem {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const FloatingMenuItem({
    required this.icon,
    this.label,
    required this.onTap,
    this.backgroundColor,
    this.foregroundColor,
  });
}

/// Modern dropdown menu button
class ModernDropdownMenu extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final List<DropdownMenuItem> items;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const ModernDropdownMenu({
    Key? key,
    this.label,
    this.icon,
    required this.items,
    this.backgroundColor,
    this.foregroundColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return PopupMenuButton<int>(
      onSelected: (index) async {
        await HapticUtils.light();
        items[index].onTap();
      },
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 8,
      offset: const Offset(0, 48),
      itemBuilder: (context) {
        return List.generate(items.length, (index) {
          final item = items[index];
          return PopupMenuItem<int>(
            value: index,
            child: Row(
              children: [
                if (item.icon != null) ...[
                  Icon(
                    item.icon,
                    size: 20,
                    color: item.color ?? theme.primaryText,
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      color: item.color ?? theme.primaryText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (item.trailing != null) item.trailing!,
              ],
            ),
          );
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: backgroundColor ?? theme.secondaryBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.alternate),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: foregroundColor ?? theme.primaryText),
              const SizedBox(width: 8),
            ],
            if (label != null)
              Text(
                label!,
                style: theme.bodyMedium.copyWith(
                  color: foregroundColor ?? theme.primaryText,
                  fontWeight: FontWeight.w500,
                ),
              ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_drop_down,
              size: 20,
              color: foregroundColor ?? theme.secondaryText,
            ),
          ],
        ),
      ),
    );
  }
}

class DropdownMenuItem {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final Color? color;
  final Widget? trailing;

  const DropdownMenuItem({
    required this.label,
    this.icon,
    required this.onTap,
    this.color,
    this.trailing,
  });
}

/// Tab bar with modern styling
class ModernTabBar extends StatelessWidget {
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final bool isScrollable;

  const ModernTabBar({
    Key? key,
    required this.tabs,
    required this.selectedIndex,
    required this.onTap,
    this.isScrollable = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.alternate.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(4),
      child: isScrollable
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildTabRow(theme),
            )
          : _buildTabRow(theme),
    );
  }

  Widget _buildTabRow(FlutterFlowTheme theme) {
    return Row(
      mainAxisSize: isScrollable ? MainAxisSize.min : MainAxisSize.max,
      children: List.generate(tabs.length, (index) {
        final isSelected = index == selectedIndex;
        return Expanded(
          flex: isScrollable ? 0 : 1,
          child: GestureDetector(
            onTap: () async {
              await HapticUtils.light();
              onTap(index);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? theme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  tabs[index],
                  style: theme.bodyMedium.copyWith(
                    color: isSelected ? Colors.white : theme.primaryText,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Modern segmented control (iOS style)
class ModernSegmentedControl extends StatelessWidget {
  final List<String> segments;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const ModernSegmentedControl({
    Key? key,
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: theme.alternate.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        children: List.generate(segments.length, (index) {
          final isSelected = index == selectedIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () async {
                await HapticUtils.light();
                onChanged(index);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.secondaryBackground
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    segments[index],
                    style: theme.bodySmall.copyWith(
                      color:
                          isSelected ? theme.primaryText : theme.secondaryText,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
