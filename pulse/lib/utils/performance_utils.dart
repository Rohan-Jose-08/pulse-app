import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';

/// Performance optimization utilities for Flutter apps
class PerformanceUtils {
  // Private constructor to prevent instantiation
  PerformanceUtils._();

  // Debounce timers cache
  static final Map<String, Timer> _debounceTimers = {};

  // Throttle flags cache
  static final Map<String, bool> _throttleFlags = {};

  /// Check if rebuild is necessary by comparing values
  static bool shouldRebuild<T>(T oldValue, T newValue) {
    return oldValue != newValue;
  }

  /// Named debounce function calls with automatic cleanup
  static void debounceNamed(
    String key,
    VoidCallback callback, {
    Duration delay = const Duration(milliseconds: 300),
  }) {
    _debounceTimers[key]?.cancel();
    _debounceTimers[key] = Timer(delay, () {
      callback();
      _debounceTimers.remove(key);
    });
  }

  /// Cancel a named debounce timer
  static void cancelDebounce(String key) {
    _debounceTimers[key]?.cancel();
    _debounceTimers.remove(key);
  }

  /// Named throttle function calls
  static void throttleNamed(
    String key,
    VoidCallback callback, {
    Duration duration = const Duration(milliseconds: 300),
  }) {
    if (_throttleFlags[key] == true) return;

    callback();
    _throttleFlags[key] = true;
    Timer(duration, () => _throttleFlags.remove(key));
  }

  /// Debounce function calls
  static Function debounce(
    Function func, {
    Duration delay = const Duration(milliseconds: 300),
  }) {
    Timer? timer;
    return ([args]) {
      timer?.cancel();
      timer = Timer(delay, () {
        Function.apply(func as Function, args ?? []);
      });
    };
  }

  /// Throttle function calls
  static Function throttle(
    Function func, {
    Duration duration = const Duration(milliseconds: 300),
  }) {
    bool isThrottled = false;
    return ([args]) {
      if (!isThrottled) {
        Function.apply(func as Function, args ?? []);
        isThrottled = true;
        Timer(duration, () {
          isThrottled = false;
        });
      }
    };
  }
}

/// Mixin to optimize list view performance
mixin ListViewOptimization<T extends StatefulWidget> on State<T> {
  /// Calculate item extent for better performance
  double? get itemExtent => null;

  /// Use RepaintBoundary for complex list items
  Widget buildOptimizedListItem(Widget child, int index) {
    return RepaintBoundary(
      key: ValueKey(index),
      child: child,
    );
  }

  /// Build with addAutomaticKeepAlives enabled by default
  bool get addAutomaticKeepAlives => true;

  /// Add repaint boundaries automatically
  bool get addRepaintBoundaries => true;

  /// Add semantic indexes
  bool get addSemanticIndexes => true;
}

/// Widget to prevent unnecessary rebuilds
class RebuildOptimizer extends StatelessWidget {
  final Widget child;
  final Object? cacheKey;

  const RebuildOptimizer({
    Key? key,
    required this.child,
    this.cacheKey,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: child,
    );
  }
}

/// Lazy loading wrapper for heavy widgets
class LazyWidget extends StatefulWidget {
  final Widget Function() builder;
  final Widget placeholder;

  const LazyWidget({
    Key? key,
    required this.builder,
    this.placeholder = const SizedBox.shrink(),
  }) : super(key: key);

  @override
  State<LazyWidget> createState() => _LazyWidgetState();
}

class _LazyWidgetState extends State<LazyWidget> {
  Widget? _child;

  @override
  void initState() {
    super.initState();
    // Build widget after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _child = widget.builder();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _child ?? widget.placeholder;
  }
}

/// Optimized image loader with automatic caching
class OptimizedImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const OptimizedImage({
    Key? key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: width?.toInt(),
      cacheHeight: height?.toInt(),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return placeholder ??
            Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
              ),
            );
      },
      errorBuilder: (context, error, stackTrace) {
        return errorWidget ??
            const Icon(Icons.error, color: Colors.grey, size: 32);
      },
    );
  }
}

/// Viewport-aware builder - only builds when visible
class ViewportBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, bool isInViewport) builder;
  final double viewportFraction;

  const ViewportBuilder({
    Key? key,
    required this.builder,
    this.viewportFraction = 0.1,
  }) : super(key: key);

  @override
  State<ViewportBuilder> createState() => _ViewportBuilderState();
}

class _ViewportBuilderState extends State<ViewportBuilder> {
  bool _isInViewport = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Check if widget is in viewport
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
          if (renderBox != null && mounted) {
            final offset = renderBox.localToGlobal(Offset.zero);
            final screenHeight = MediaQuery.of(context).size.height;
            final isVisible = offset.dy < screenHeight &&
                offset.dy + renderBox.size.height > 0;

            if (isVisible != _isInViewport) {
              setState(() {
                _isInViewport = isVisible;
              });
            }
          }
        });

        return widget.builder(context, _isInViewport);
      },
    );
  }
}

/// Memory-efficient list separator
class EfficientSeparator extends StatelessWidget {
  final double height;
  final Color? color;

  const EfficientSeparator({
    Key? key,
    this.height = 1,
    this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: color != null ? Container(color: color) : const SizedBox.shrink(),
    );
  }
}

/// Optimized cached network image widget
class CachedAvatar extends StatelessWidget {
  final String? imageUrl;
  final double radius;
  final IconData fallbackIcon;
  final Color? backgroundColor;
  final Color? iconColor;

  const CachedAvatar({
    Key? key,
    this.imageUrl,
    this.radius = 24,
    this.fallbackIcon = Icons.person,
    this.backgroundColor,
    this.iconColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor ?? Colors.grey[300],
        child: Icon(fallbackIcon,
            color: iconColor ?? Colors.grey[600], size: radius),
      );
    }

    final cacheSize = (radius * 2 * 2).toInt(); // 2x for retina displays

    return CachedNetworkImage(
      imageUrl: imageUrl!,
      imageBuilder: (context, imageProvider) => CircleAvatar(
        radius: radius,
        backgroundImage: imageProvider,
        backgroundColor: backgroundColor,
      ),
      placeholder: (context, url) => CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor ?? Colors.grey[300],
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      errorWidget: (context, url, error) => CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor ?? Colors.grey[300],
        child: Icon(fallbackIcon,
            color: iconColor ?? Colors.grey[600], size: radius),
      ),
      memCacheWidth: cacheSize,
      memCacheHeight: cacheSize,
    );
  }
}

/// Efficient scroll-aware list item that only builds content when near viewport
class ScrollAwareListItem extends StatefulWidget {
  final Widget Function(BuildContext context) builder;
  final Widget placeholder;
  final double estimatedHeight;

  const ScrollAwareListItem({
    Key? key,
    required this.builder,
    this.placeholder = const SizedBox(height: 72),
    this.estimatedHeight = 72,
  }) : super(key: key);

  @override
  State<ScrollAwareListItem> createState() => _ScrollAwareListItemState();
}

class _ScrollAwareListItemState extends State<ScrollAwareListItem> {
  bool _hasBuilt = false;
  Widget? _cachedChild;

  @override
  Widget build(BuildContext context) {
    if (_hasBuilt) {
      return _cachedChild ?? widget.placeholder;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Build once and cache
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_hasBuilt && mounted) {
            setState(() {
              _hasBuilt = true;
              _cachedChild = widget.builder(context);
            });
          }
        });

        return SizedBox(
          height: widget.estimatedHeight,
          child: widget.placeholder,
        );
      },
    );
  }
}

/// Mixin to add performance optimizations to StatefulWidgets
mixin PerformanceOptimizedState<T extends StatefulWidget> on State<T> {
  /// Debounced setState to prevent rapid rebuilds
  void setStateDebounced(VoidCallback fn,
      {Duration delay = const Duration(milliseconds: 100)}) {
    PerformanceUtils.debounceNamed(
      '${widget.runtimeType}_setState',
      () {
        if (mounted) setState(fn);
      },
      delay: delay,
    );
  }

  /// Throttled setState to limit rebuild frequency
  void setStateThrottled(VoidCallback fn,
      {Duration duration = const Duration(milliseconds: 100)}) {
    PerformanceUtils.throttleNamed(
      '${widget.runtimeType}_setState',
      () {
        if (mounted) setState(fn);
      },
      duration: duration,
    );
  }
}
