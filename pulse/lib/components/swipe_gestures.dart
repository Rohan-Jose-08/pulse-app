import 'package:flutter/material.dart';
import '../flutter_flow/flutter_flow_theme.dart';
import '../utils/haptic_utils.dart';

/// Swipeable list item with customizable actions
/// Modern UX pattern for delete, archive, and other quick actions
class SwipeableListItem extends StatelessWidget {
  final Widget child;
  final List<SwipeAction>? leftActions;
  final List<SwipeAction>? rightActions;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const SwipeableListItem({
    Key? key,
    required this.child,
    this.leftActions,
    this.rightActions,
    this.onTap,
    this.onLongPress,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: UniqueKey(),
      background:
          _buildActionBackground(context, leftActions, Alignment.centerLeft),
      secondaryBackground:
          _buildActionBackground(context, rightActions, Alignment.centerRight),
      confirmDismiss: (direction) async {
        await HapticUtils.medium();
        final actions = direction == DismissDirection.startToEnd
            ? leftActions
            : rightActions;
        if (actions == null || actions.isEmpty) return false;

        final action = actions.first;
        action.onTap();
        return action.dismissible;
      },
      child: InkWell(
        onTap: onTap,
        onLongPress: () async {
          if (onLongPress != null) {
            await HapticUtils.medium();
            onLongPress!();
          }
        },
        child: child,
      ),
    );
  }

  Widget _buildActionBackground(
    BuildContext context,
    List<SwipeAction>? actions,
    Alignment alignment,
  ) {
    if (actions == null || actions.isEmpty) {
      return const SizedBox();
    }

    final action = actions.first;
    return Container(
      color: action.backgroundColor,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Icon(
        action.icon,
        color: action.foregroundColor ?? Colors.white,
        size: 28,
      ),
    );
  }
}

class SwipeAction {
  final IconData icon;
  final Color backgroundColor;
  final Color? foregroundColor;
  final VoidCallback onTap;
  final bool dismissible;

  const SwipeAction({
    required this.icon,
    required this.backgroundColor,
    this.foregroundColor,
    required this.onTap,
    this.dismissible = true,
  });
}

/// Long-press contextual menu
/// Modern context menu that appears on long-press with smooth animation
class ContextMenu extends StatelessWidget {
  final Widget child;
  final List<ContextMenuItem> items;

  const ContextMenu({
    Key? key,
    required this.child,
    required this.items,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () async {
        await HapticUtils.medium();
        _showContextMenu(context);
      },
      child: child,
    );
  }

  void _showContextMenu(BuildContext context) {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height,
        offset.dx + size.width,
        offset.dy,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 8,
      items: items.map((item) {
        return PopupMenuItem(
          onTap: item.onTap,
          child: Row(
            children: [
              if (item.icon != null) ...[
                Icon(
                  item.icon,
                  size: 20,
                  color: item.color,
                ),
                const SizedBox(width: 12),
              ],
              Text(
                item.label,
                style: TextStyle(
                  color: item.color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class ContextMenuItem {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final Color? color;

  const ContextMenuItem({
    required this.label,
    this.icon,
    required this.onTap,
    this.color,
  });
}

/// Swipe-to-dismiss wrapper with callback
class SwipeToDismiss extends StatelessWidget {
  final Widget child;
  final VoidCallback onDismiss;
  final String? confirmMessage;
  final Color? backgroundColor;
  final IconData? icon;

  const SwipeToDismiss({
    Key? key,
    required this.child,
    required this.onDismiss,
    this.confirmMessage,
    this.backgroundColor,
    this.icon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Dismissible(
      key: UniqueKey(),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        await HapticUtils.medium();

        if (confirmMessage != null) {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text('Confirm'),
              content: Text(confirmMessage!),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(
                    'Confirm',
                    style: TextStyle(color: theme.error),
                  ),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            onDismiss();
          }
          return confirmed ?? false;
        }

        onDismiss();
        return true;
      },
      background: Container(
        color: backgroundColor ?? theme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(
          icon ?? Icons.delete,
          color: Colors.white,
          size: 28,
        ),
      ),
      child: child,
    );
  }
}

/// Pull-down to refresh with custom indicator
class PullToRefreshWrapper extends StatelessWidget {
  final Widget child;
  final Future<void> Function() onRefresh;
  final Color? color;

  const PullToRefreshWrapper({
    Key? key,
    required this.child,
    required this.onRefresh,
    this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return RefreshIndicator(
      onRefresh: () async {
        await HapticUtils.light();
        await onRefresh();
      },
      color: color ?? theme.primary,
      backgroundColor: theme.secondaryBackground,
      strokeWidth: 2.5,
      displacement: 60,
      edgeOffset: 0,
      child: child,
    );
  }
}

/// Double-tap to like/favorite with animation
class DoubleTapToLike extends StatefulWidget {
  final Widget child;
  final VoidCallback onDoubleTap;
  final VoidCallback? onTap;

  const DoubleTapToLike({
    Key? key,
    required this.child,
    required this.onDoubleTap,
    this.onTap,
  }) : super(key: key);

  @override
  State<DoubleTapToLike> createState() => _DoubleTapToLikeState();
}

class _DoubleTapToLikeState extends State<DoubleTapToLike>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDoubleTap() async {
    await HapticUtils.medium();
    widget.onDoubleTap();
    _controller.forward().then((_) => _controller.reverse());
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTap: _handleDoubleTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          widget.child,
          IgnorePointer(
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: FadeTransition(
                opacity: _controller,
                child: const Icon(
                  Icons.favorite,
                  color: Colors.red,
                  size: 80,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Swipe between pages gesture detector
class SwipeablePageView extends StatelessWidget {
  final List<Widget> pages;
  final int initialPage;
  final ValueChanged<int>? onPageChanged;
  final PageController? controller;

  const SwipeablePageView({
    Key? key,
    required this.pages,
    this.initialPage = 0,
    this.onPageChanged,
    this.controller,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: controller ?? PageController(initialPage: initialPage),
      onPageChanged: (index) async {
        await HapticUtils.light();
        onPageChanged?.call(index);
      },
      itemCount: pages.length,
      itemBuilder: (context, index) => pages[index],
    );
  }
}
