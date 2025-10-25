import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../flutter_flow/flutter_flow_theme.dart';

/// Tooltip for onboarding and feature discovery
class FeatureDiscoveryTooltip extends StatefulWidget {
  final String featureId;
  final String title;
  final String description;
  final Widget child;
  final TooltipPosition position;

  const FeatureDiscoveryTooltip({
    Key? key,
    required this.featureId,
    required this.title,
    required this.description,
    required this.child,
    this.position = TooltipPosition.bottom,
  }) : super(key: key);

  @override
  State<FeatureDiscoveryTooltip> createState() =>
      _FeatureDiscoveryTooltipState();
}

class _FeatureDiscoveryTooltipState extends State<FeatureDiscoveryTooltip> {
  bool _shouldShow = false;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _checkIfShouldShow();
  }

  Future<void> _checkIfShouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenKey = 'feature_seen_${widget.featureId}';
    final hasSeen = prefs.getBool(hasSeenKey) ?? false;

    if (!hasSeen && mounted) {
      setState(() => _shouldShow = true);
      // Show tooltip after a short delay
      Future.delayed(const Duration(milliseconds: 500), _showTooltip);
    }
  }

  void _showTooltip() {
    if (!_shouldShow || !mounted) return;

    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    _overlayEntry = OverlayEntry(
      builder: (context) => _TooltipOverlay(
        targetOffset: offset,
        targetSize: size,
        title: widget.title,
        description: widget.description,
        position: widget.position,
        onDismiss: _dismissTooltip,
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  Future<void> _dismissTooltip() async {
    _overlayEntry?.remove();
    _overlayEntry = null;
    setState(() => _shouldShow = false);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('feature_seen_${widget.featureId}', true);
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class _TooltipOverlay extends StatelessWidget {
  final Offset targetOffset;
  final Size targetSize;
  final String title;
  final String description;
  final TooltipPosition position;
  final VoidCallback onDismiss;

  const _TooltipOverlay({
    required this.targetOffset,
    required this.targetSize,
    required this.title,
    required this.description,
    required this.position,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final screenSize = MediaQuery.of(context).size;

    return Material(
      color: Colors.black54,
      child: GestureDetector(
        onTap: onDismiss,
        child: Stack(
          children: [
            // Highlight the target widget
            Positioned(
              left: targetOffset.dx - 8,
              top: targetOffset.dy - 8,
              child: Container(
                width: targetSize.width + 16,
                height: targetSize.height + 16,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: theme.primary.withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
              ),
            ),
            // Tooltip card
            Positioned(
              left: _calculateLeft(screenSize),
              top: _calculateTop(),
              child: Container(
                width: screenSize.width * 0.8,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.secondaryBackground,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: theme.titleMedium.override(
                              fontWeight: FontWeight.w700,
                              color: theme.primaryText,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: theme.secondaryText),
                          onPressed: onDismiss,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: theme.bodyMedium.override(
                        color: theme.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton(
                        onPressed: onDismiss,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.primary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Got it!',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _calculateLeft(Size screenSize) {
    return screenSize.width * 0.1;
  }

  double _calculateTop() {
    switch (position) {
      case TooltipPosition.top:
        return targetOffset.dy - 200;
      case TooltipPosition.bottom:
        return targetOffset.dy + targetSize.height + 20;
      case TooltipPosition.left:
        return targetOffset.dy;
      case TooltipPosition.right:
        return targetOffset.dy;
    }
  }
}

enum TooltipPosition {
  top,
  bottom,
  left,
  right,
}

/// Simple helper to reset all tooltips (for testing)
class TooltipManager {
  static Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys =
        prefs.getKeys().where((key) => key.startsWith('feature_seen_'));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  static Future<void> markAsSeen(String featureId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('feature_seen_$featureId', true);
  }

  static Future<bool> hasSeen(String featureId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('feature_seen_$featureId') ?? false;
  }
}
