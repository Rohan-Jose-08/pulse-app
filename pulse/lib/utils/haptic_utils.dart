import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:haptic_feedback/haptic_feedback.dart';

/// Centralized haptic feedback utilities for consistent UX
class HapticUtils {
  /// Light impact for selections and navigation
  static Future<void> light() async {
    await HapticFeedback.lightImpact();
  }

  /// Medium impact for button presses
  static Future<void> medium() async {
    await HapticFeedback.mediumImpact();
  }

  /// Heavy impact for significant actions
  static Future<void> heavy() async {
    await HapticFeedback.heavyImpact();
  }

  /// Selection for picker changes
  static Future<void> selection() async {
    await HapticFeedback.selectionClick();
  }

  /// Success vibration pattern
  static Future<void> success() async {
    await Haptics.vibrate(HapticsType.success);
  }

  /// Warning vibration pattern
  static Future<void> warning() async {
    await Haptics.vibrate(HapticsType.warning);
  }

  /// Error vibration pattern
  static Future<void> error() async {
    await Haptics.vibrate(HapticsType.error);
  }

  /// Custom duration vibration
  static Future<void> vibrate({int durationMs = 50}) async {
    await Haptics.vibrate(HapticsType.selection);
  }
}

/// Enhanced button widget with haptic feedback
class HapticButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final HapticsType feedbackType;
  final Color? backgroundColor;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final double? elevation;

  const HapticButton({
    Key? key,
    required this.child,
    this.onPressed,
    this.feedbackType = HapticsType.selection,
    this.backgroundColor,
    this.padding,
    this.borderRadius,
    this.elevation,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor ?? Colors.transparent,
      elevation: elevation ?? 0,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: onPressed == null
            ? null
            : () async {
                await Haptics.vibrate(feedbackType);
                onPressed!();
              },
        borderRadius: borderRadius,
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: child,
        ),
      ),
    );
  }
}

/// Haptic-enabled IconButton
class HapticIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;
  final double size;
  final HapticsType feedbackType;

  const HapticIconButton({
    Key? key,
    required this.icon,
    this.onPressed,
    this.color,
    this.size = 24,
    this.feedbackType = HapticsType.selection,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: color, size: size),
      onPressed: onPressed == null
          ? null
          : () async {
              await Haptics.vibrate(feedbackType);
              onPressed!();
            },
    );
  }
}

/// Haptic-enabled Card with scale animation
class HapticCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final BorderRadius? borderRadius;
  final double? elevation;
  final HapticsType feedbackType;

  const HapticCard({
    Key? key,
    required this.child,
    this.onTap,
    this.margin,
    this.padding,
    this.color,
    this.borderRadius,
    this.elevation,
    this.feedbackType = HapticsType.light,
  }) : super(key: key);

  @override
  State<HapticCard> createState() => _HapticCardState();
}

class _HapticCardState extends State<HapticCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      onTap: widget.onTap == null
          ? null
          : () async {
              await Haptics.vibrate(widget.feedbackType);
              widget.onTap!();
            },
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Card(
          margin: widget.margin,
          color: widget.color,
          elevation: widget.elevation ?? 2,
          shape: RoundedRectangleBorder(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
          ),
          child: Padding(
            padding: widget.padding ?? const EdgeInsets.all(16),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
