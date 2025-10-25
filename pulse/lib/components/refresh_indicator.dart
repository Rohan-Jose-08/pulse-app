import 'package:flutter/material.dart';
import '../flutter_flow/flutter_flow_theme.dart';

/// Custom pull-to-refresh indicator with brand styling
class CustomRefreshIndicator extends StatelessWidget {
  final Widget child;
  final Future<void> Function() onRefresh;
  final Color? color;
  final Color? backgroundColor;

  const CustomRefreshIndicator({
    Key? key,
    required this.child,
    required this.onRefresh,
    this.color,
    this.backgroundColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: color ?? theme.primary,
      backgroundColor: backgroundColor ?? theme.secondaryBackground,
      strokeWidth: 3,
      displacement: 60,
      child: child,
    );
  }
}

/// Custom refresh indicator with animation
class AnimatedRefreshIndicator extends StatefulWidget {
  final Widget child;
  final Future<void> Function() onRefresh;

  const AnimatedRefreshIndicator({
    Key? key,
    required this.child,
    required this.onRefresh,
  }) : super(key: key);

  @override
  State<AnimatedRefreshIndicator> createState() =>
      _AnimatedRefreshIndicatorState();
}

class _AnimatedRefreshIndicatorState extends State<AnimatedRefreshIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    _controller.repeat();
    try {
      await widget.onRefresh();
    } finally {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: theme.primary,
      backgroundColor: theme.secondaryBackground,
      strokeWidth: 3,
      displacement: 60,
      child: widget.child,
    );
  }
}

/// Scroll to refresh wrapper for custom scrollables
class CustomScrollToRefresh extends StatelessWidget {
  final Widget child;
  final Future<void> Function() onRefresh;
  final ScrollController? scrollController;

  const CustomScrollToRefresh({
    Key? key,
    required this.child,
    required this.onRefresh,
    this.scrollController,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomRefreshIndicator(
      onRefresh: onRefresh,
      child: child,
    );
  }
}
