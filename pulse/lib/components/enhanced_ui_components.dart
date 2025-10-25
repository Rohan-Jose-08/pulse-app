import 'dart:ui';
import 'package:flutter/material.dart';
import '../flutter_flow/flutter_flow_theme.dart';

/// Modern Card with enhanced shadows and blur effects
class ModernCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final double? elevation;
  final double? borderRadius;
  final VoidCallback? onTap;
  final bool useGlassmorphism;

  const ModernCard({
    Key? key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.elevation,
    this.borderRadius,
    this.onTap,
    this.useGlassmorphism = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    Widget card = Container(
      margin: margin ?? EdgeInsets.all(AppSpacing.s),
      decoration: BoxDecoration(
        color: useGlassmorphism
            ? theme.secondaryBackground.withOpacity(0.7)
            : color ?? theme.secondaryBackground,
        borderRadius: BorderRadius.circular(borderRadius ?? AppRadius.l),
        boxShadow: [
          BoxShadow(
            color: theme.primaryText.withOpacity(0.05),
            blurRadius: elevation ?? AppElevation.medium,
            offset: const Offset(0, 2),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: theme.primaryText.withOpacity(0.03),
            blurRadius: (elevation ?? AppElevation.medium) * 2,
            offset: const Offset(0, 4),
            spreadRadius: 0,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius ?? AppRadius.l),
        child: useGlassmorphism
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Padding(
                  padding: padding ?? EdgeInsets.all(AppSpacing.m),
                  child: child,
                ),
              )
            : Padding(
                padding: padding ?? EdgeInsets.all(AppSpacing.m),
                child: child,
              ),
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius ?? AppRadius.l),
          child: card,
        ),
      );
    }

    return card;
  }
}

/// Enhanced Button with gradient and animations
class GradientButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final List<Color>? gradientColors;
  final double? width;
  final double? height;
  final double? borderRadius;
  final IconData? icon;
  final bool isLoading;
  final bool isOutlined;

  const GradientButton({
    Key? key,
    required this.text,
    this.onPressed,
    this.gradientColors,
    this.width,
    this.height,
    this.borderRadius,
    this.icon,
    this.isLoading = false,
    this.isOutlined = false,
  }) : super(key: key);

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppAnimation.fast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: AppAnimation.standard),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final gradientColors =
        widget.gradientColors ?? [theme.primary, theme.secondary];

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        width: widget.width,
        height: widget.height ?? 52,
        decoration: BoxDecoration(
          gradient: widget.isOutlined
              ? null
              : LinearGradient(
                  colors: gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          border: widget.isOutlined
              ? Border.all(color: theme.primary, width: 2)
              : null,
          borderRadius: BorderRadius.circular(
            widget.borderRadius ?? AppRadius.m,
          ),
          boxShadow: widget.isOutlined
              ? null
              : [
                  BoxShadow(
                    color: gradientColors.first.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.isLoading ? null : widget.onPressed,
            onTapDown: (_) => _controller.forward(),
            onTapUp: (_) => _controller.reverse(),
            onTapCancel: () => _controller.reverse(),
            borderRadius: BorderRadius.circular(
              widget.borderRadius ?? AppRadius.m,
            ),
            child: Center(
              child: widget.isLoading
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          widget.isOutlined ? theme.primary : Colors.white,
                        ),
                        strokeWidth: 2,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(
                            widget.icon,
                            color: widget.isOutlined
                                ? theme.primary
                                : Colors.white,
                            size: 20,
                          ),
                          SizedBox(width: AppSpacing.s),
                        ],
                        Text(
                          widget.text,
                          style: theme.titleMedium.override(
                            color: widget.isOutlined
                                ? theme.primary
                                : Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Animated Shimmer Loading Placeholder
class ShimmerLoading extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;
  final BoxShape shape;

  const ShimmerLoading({
    Key? key,
    required this.width,
    required this.height,
    this.borderRadius = 8.0,
    this.shape = BoxShape.rectangle,
  }) : super(key: key);

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            shape: widget.shape,
            borderRadius: widget.shape == BoxShape.rectangle
                ? BorderRadius.circular(widget.borderRadius)
                : null,
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                theme.alternate,
                theme.alternate.withOpacity(0.5),
                theme.alternate,
              ],
              stops: [
                _animation.value - 0.3,
                _animation.value,
                _animation.value + 0.3,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Pulse Avatar with online status indicator
class PulseAvatar extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final bool showOnlineStatus;
  final bool isOnline;
  final VoidCallback? onTap;

  const PulseAvatar({
    Key? key,
    this.imageUrl,
    this.size = 48.0,
    this.showOnlineStatus = false,
    this.isOnline = false,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [theme.primary, theme.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.primary.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(2.0),
              child: ClipOval(
                child: imageUrl != null && imageUrl!.isNotEmpty
                    ? Image.network(
                        imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return _buildPlaceholder(theme);
                        },
                      )
                    : _buildPlaceholder(theme),
              ),
            ),
          ),
          if (showOnlineStatus)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: size * 0.25,
                height: size * 0.25,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOnline ? theme.success : theme.secondaryText,
                  border: Border.all(
                    color: theme.secondaryBackground,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(FlutterFlowTheme theme) {
    return Container(
      color: theme.secondaryBackground,
      child: Icon(
        Icons.person,
        size: size * 0.6,
        color: theme.secondaryText,
      ),
    );
  }
}

/// Floating Action Button with micro-interactions
class AnimatedFAB extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String? label;
  final bool isExtended;

  const AnimatedFAB({
    Key? key,
    required this.icon,
    required this.onPressed,
    this.label,
    this.isExtended = false,
  }) : super(key: key);

  @override
  State<AnimatedFAB> createState() => _AnimatedFABState();
}

class _AnimatedFABState extends State<AnimatedFAB>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppAnimation.normal,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: AppAnimation.emphasized),
    );
    _rotationAnimation = Tween<double>(begin: 0.0, end: 0.1).animate(
      CurvedAnimation(parent: _controller, curve: AppAnimation.bounce),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return ScaleTransition(
      scale: _scaleAnimation,
      child: RotationTransition(
        turns: _rotationAnimation,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [theme.primary, theme.secondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppRadius.circular),
            boxShadow: [
              BoxShadow(
                color: theme.primary.withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                _controller.forward().then((_) {
                  _controller.reverse();
                  widget.onPressed();
                });
              },
              borderRadius: BorderRadius.circular(AppRadius.circular),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: widget.isExtended ? AppSpacing.l : AppSpacing.m,
                  vertical: AppSpacing.m,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, color: Colors.white, size: 24),
                    if (widget.isExtended && widget.label != null) ...[
                      SizedBox(width: AppSpacing.s),
                      Text(
                        widget.label!,
                        style: theme.titleMedium.override(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Animated Status Badge
class StatusBadge extends StatelessWidget {
  final String text;
  final Color? color;
  final IconData? icon;
  final bool isPulsing;

  const StatusBadge({
    Key? key,
    required this.text,
    this.color,
    this.icon,
    this.isPulsing = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final badgeColor = color ?? theme.success;

    Widget badge = Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.s,
      ),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(AppRadius.circular),
        border: Border.all(
          color: badgeColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: badgeColor, size: 16),
            SizedBox(width: AppSpacing.xs),
          ],
          Text(
            text,
            style: theme.labelSmall.override(
              color: badgeColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    if (isPulsing) {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 1500),
        builder: (context, value, child) {
          return Opacity(
            opacity: 0.5 + (0.5 * (1 - value)),
            child: Transform.scale(
              scale: 1.0 + (0.05 * value),
              child: child,
            ),
          );
        },
        onEnd: () {
          // Animation will repeat automatically with setState
        },
        child: badge,
      );
    }

    return badge;
  }
}

// Missing import for ImageFilter
