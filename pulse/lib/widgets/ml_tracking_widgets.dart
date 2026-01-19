import 'package:flutter/material.dart';
import '../services/ml_recommendation_service.dart';

/// Mixin to add ML tracking capabilities to widgets
mixin MLTrackingMixin<T extends StatefulWidget> on State<T> {
  DateTime? _viewStartTime;

  @override
  void initState() {
    super.initState();
    _viewStartTime = DateTime.now();
  }

  @override
  void dispose() {
    // Track view duration when widget is disposed
    if (_viewStartTime != null) {
      final duration = DateTime.now().difference(_viewStartTime!);
      trackViewDuration(duration.inSeconds);
    }
    super.dispose();
  }

  /// Override this to specify which pulse ID to track
  String? get pulseIdToTrack => null;

  /// Track view duration (called automatically on dispose)
  void trackViewDuration(int seconds) {
    final pulseId = pulseIdToTrack;
    if (pulseId != null && seconds > 0) {
      pulseId.trackView(durationSeconds: seconds);
    }
  }

  /// Manually track a specific interaction
  Future<void> trackInteraction(
    String pulseId,
    MLInteractionType type,
  ) async {
    await MLRecommendationService.instance.trackInteraction(
      pulseId: pulseId,
      type: type,
    );
  }
}

/// Widget wrapper that automatically tracks pulse views
class MLTrackedPulseView extends StatefulWidget {
  const MLTrackedPulseView({
    super.key,
    required this.pulseId,
    required this.child,
    this.minViewDuration = const Duration(seconds: 2),
  });

  final String pulseId;
  final Widget child;
  final Duration minViewDuration;

  @override
  State<MLTrackedPulseView> createState() => _MLTrackedPulseViewState();
}

class _MLTrackedPulseViewState extends State<MLTrackedPulseView> {
  DateTime? _viewStartTime;
  bool _tracked = false;

  @override
  void initState() {
    super.initState();
    _viewStartTime = DateTime.now();
  }

  @override
  void dispose() {
    _trackView();
    super.dispose();
  }

  @override
  void deactivate() {
    _trackView();
    super.deactivate();
  }

  void _trackView() {
    if (_tracked || _viewStartTime == null) return;

    final duration = DateTime.now().difference(_viewStartTime!);
    if (duration >= widget.minViewDuration) {
      widget.pulseId.trackView(durationSeconds: duration.inSeconds);
      _tracked = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Button wrapper that tracks clicks on pulses
class MLTrackedButton extends StatelessWidget {
  const MLTrackedButton({
    super.key,
    required this.pulseId,
    required this.onPressed,
    required this.child,
    this.interactionType = MLInteractionType.view,
  });

  final String pulseId;
  final VoidCallback onPressed;
  final Widget child;
  final MLInteractionType interactionType;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await MLRecommendationService.instance.trackInteraction(
          pulseId: pulseId,
          type: interactionType,
        );
        onPressed();
      },
      child: child,
    );
  }
}

/// Join button with ML tracking
class MLTrackedJoinButton extends StatelessWidget {
  const MLTrackedJoinButton({
    super.key,
    required this.pulseId,
    required this.onJoin,
    this.child,
  });

  final String pulseId;
  final VoidCallback onJoin;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () async {
        await pulseId.trackJoin();
        onJoin();
      },
      child: child ?? const Text('Join'),
    );
  }
}

/// Share button with ML tracking
class MLTrackedShareButton extends StatelessWidget {
  const MLTrackedShareButton({
    super.key,
    required this.pulseId,
    required this.onShare,
    this.child,
  });

  final String pulseId;
  final VoidCallback onShare;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () async {
        await pulseId.trackShare();
        onShare();
      },
      icon: child ?? const Icon(Icons.share),
    );
  }
}

/// Helper to track search interactions
class MLSearchTracker {
  static Future<void> trackSearch(String query, {String? resultPulseId}) async {
    if (resultPulseId != null) {
      await MLRecommendationService.instance.trackInteraction(
        pulseId: resultPulseId,
        type: MLInteractionType.search,
        source: 'search:$query',
      );
    }
  }
}

/// Helper to track message interactions
class MLMessageTracker {
  static final Set<String> _trackedConversations = {};

  static Future<void> trackMessage(String pulseId) async {
    // Only track once per session per pulse to avoid spam
    if (_trackedConversations.contains(pulseId)) return;

    await pulseId.trackMessage();
    _trackedConversations.add(pulseId);
  }

  static void reset() {
    _trackedConversations.clear();
  }
}
