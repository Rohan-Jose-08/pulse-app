import 'package:flutter/material.dart';
import '../flutter_flow/flutter_flow_theme.dart';

/// Enhanced skeleton loader with multiple patterns and smooth animations
class EnhancedSkeleton extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final bool shimmer;
  final Color? baseColor;
  final Color? highlightColor;

  const EnhancedSkeleton({
    Key? key,
    this.width,
    this.height,
    this.borderRadius,
    this.shimmer = true,
    this.baseColor,
    this.highlightColor,
  }) : super(key: key);

  /// Circle skeleton (avatar)
  const EnhancedSkeleton.circle({
    Key? key,
    required double size,
    bool shimmer = true,
    Color? baseColor,
    Color? highlightColor,
  }) : this(
          key: key,
          width: size,
          height: size,
          borderRadius: BorderRadius.circular(size / 2),
          shimmer: shimmer,
          baseColor: baseColor,
          highlightColor: highlightColor,
        );

  /// Rectangle skeleton
  const EnhancedSkeleton.rectangle({
    Key? key,
    double? width,
    double? height,
    double? borderRadius,
    bool shimmer = true,
    Color? baseColor,
    Color? highlightColor,
  }) : this(
          key: key,
          width: width,
          height: height,
          borderRadius: borderRadius != null
              ? BorderRadius.circular(borderRadius)
              : BorderRadius.circular(8),
          shimmer: shimmer,
          baseColor: baseColor,
          highlightColor: highlightColor,
        );

  @override
  State<EnhancedSkeleton> createState() => _EnhancedSkeletonState();
}

class _EnhancedSkeletonState extends State<EnhancedSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    if (widget.shimmer) {
      _controller = AnimationController(
        duration: const Duration(milliseconds: 1500),
        vsync: this,
      )..repeat();
    } else {
      _controller = AnimationController(vsync: this);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final baseColor =
        widget.baseColor ?? (isDark ? Colors.grey[800]! : Colors.grey[300]!);
    final highlightColor = widget.highlightColor ??
        (isDark ? Colors.grey[700]! : Colors.grey[100]!);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: widget.shimmer
                ? LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      baseColor,
                      highlightColor,
                      baseColor,
                    ],
                    stops: [
                      _controller.value - 0.3,
                      _controller.value,
                      _controller.value + 0.3,
                    ].map((e) => e.clamp(0.0, 1.0)).toList(),
                  )
                : null,
            color: widget.shimmer ? null : baseColor,
          ),
        );
      },
    );
  }
}

/// Card skeleton for list items
class CardSkeleton extends StatelessWidget {
  final bool showAvatar;
  final bool showImage;
  final int lineCount;

  const CardSkeleton({
    Key? key,
    this.showAvatar = true,
    this.showImage = false,
    this.lineCount = 2,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with avatar
          Row(
            children: [
              if (showAvatar) ...[
                const EnhancedSkeleton.circle(size: 40),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EnhancedSkeleton.rectangle(
                      width: double.infinity,
                      height: 16,
                    ),
                    const SizedBox(height: 8),
                    EnhancedSkeleton.rectangle(
                      width: 120,
                      height: 12,
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Image
          if (showImage) ...[
            const SizedBox(height: 12),
            EnhancedSkeleton.rectangle(
              width: double.infinity,
              height: 200,
              borderRadius: 8,
            ),
          ],

          // Content lines
          const SizedBox(height: 12),
          ...List.generate(lineCount, (index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: EnhancedSkeleton.rectangle(
                width: index == lineCount - 1 ? 180 : double.infinity,
                height: 12,
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// List skeleton loader
class ListSkeleton extends StatelessWidget {
  final int itemCount;
  final Widget Function(int index)? itemBuilder;

  const ListSkeleton({
    Key? key,
    this.itemCount = 5,
    this.itemBuilder,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        return itemBuilder?.call(index) ?? const CardSkeleton();
      },
    );
  }
}

/// Modern loading indicator with text
class ModernLoadingIndicator extends StatelessWidget {
  final String? message;
  final Color? color;
  final double size;

  const ModernLoadingIndicator({
    Key? key,
    this.message,
    this.color,
    this.size = 40,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(
                color ?? theme.primary,
              ),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: theme.bodyMedium.copyWith(
                color: theme.secondaryText,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// Pulsing loading dots
class PulsingDots extends StatefulWidget {
  final int dotCount;
  final double dotSize;
  final Color? color;
  final Duration duration;

  const PulsingDots({
    Key? key,
    this.dotCount = 3,
    this.dotSize = 8,
    this.color,
    this.duration = const Duration(milliseconds: 1200),
  }) : super(key: key);

  @override
  State<PulsingDots> createState() => _PulsingDotsState();
}

class _PulsingDotsState extends State<PulsingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final color = widget.color ?? theme.primary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(widget.dotCount, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final delay = index / widget.dotCount;
            final progress = (_controller.value - delay).clamp(0.0, 1.0);
            final opacity = (progress * 2 - 1).abs();

            return Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.dotSize / 4),
              child: Container(
                width: widget.dotSize,
                height: widget.dotSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.3 + opacity * 0.7),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

/// Progress bar with percentage
class ModernProgressBar extends StatelessWidget {
  final double progress;
  final String? label;
  final Color? color;
  final Color? backgroundColor;
  final double height;
  final bool showPercentage;

  const ModernProgressBar({
    Key? key,
    required this.progress,
    this.label,
    this.color,
    this.backgroundColor,
    this.height = 8,
    this.showPercentage = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final percentage = (progress * 100).toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null || showPercentage)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (label != null)
                  Text(
                    label!,
                    style: theme.bodySmall,
                  ),
                if (showPercentage)
                  Text(
                    '$percentage%',
                    style: theme.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.primary,
                    ),
                  ),
              ],
            ),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: height,
            backgroundColor:
                backgroundColor ?? theme.alternate.withOpacity(0.3),
            valueColor: AlwaysStoppedAnimation<Color>(
              color ?? theme.primary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Spinning refresh indicator
class SpinningRefreshIndicator extends StatefulWidget {
  final double size;
  final Color? color;

  const SpinningRefreshIndicator({
    Key? key,
    this.size = 24,
    this.color,
  }) : super(key: key);

  @override
  State<SpinningRefreshIndicator> createState() =>
      _SpinningRefreshIndicatorState();
}

class _SpinningRefreshIndicatorState extends State<SpinningRefreshIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return RotationTransition(
      turns: _controller,
      child: Icon(
        Icons.refresh,
        size: widget.size,
        color: widget.color ?? theme.primary,
      ),
    );
  }
}
