import 'dart:async';
import 'package:flutter/foundation.dart';
import '../backend/api_service.dart';

/// ML-powered recommendation service for personalized content
class MLRecommendationService {
  static final MLRecommendationService instance = MLRecommendationService._();
  MLRecommendationService._();

  final ApiService _api = ApiService.instance;

  // Cache for recommendations
  List<Map<String, dynamic>>? _cachedRecommendations;
  DateTime? _cacheTime;
  static const Duration _cacheDuration = Duration(minutes: 15);

  /// Get personalized pulse recommendations with location awareness
  Future<List<Map<String, dynamic>>> getPersonalizedRecommendations({
    double? latitude,
    double? longitude,
    bool forceRefresh = false,
  }) async {
    // Check cache
    if (!forceRefresh &&
        _cachedRecommendations != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheDuration) {
      return _cachedRecommendations!;
    }

    try {
      final recommendations = await _api.getPersonalizedPulses(
        latitude: latitude,
        longitude: longitude,
      );

      // Cache results
      _cachedRecommendations = recommendations;
      _cacheTime = DateTime.now();

      return recommendations;
    } catch (e) {
      debugPrint('Error getting personalized recommendations: $e');
      return _cachedRecommendations ?? [];
    }
  }

  /// Clear recommendation cache
  void clearCache() {
    _cachedRecommendations = null;
    _cacheTime = null;
  }

  /// Track interaction with a pulse
  Future<void> trackInteraction({
    required String pulseId,
    required MLInteractionType type,
    int? durationSeconds,
    String? source,
  }) async {
    try {
      await _api.trackPulseInteraction(
        pulseId: pulseId,
        interactionType: type.value,
        durationSeconds: durationSeconds,
        source: source ?? 'app',
      );

      // Clear cache after significant interactions to get fresh recommendations
      if (type == MLInteractionType.join ||
          type == MLInteractionType.share ||
          type == MLInteractionType.message) {
        clearCache();
      }
    } catch (e) {
      debugPrint('Error tracking interaction: $e');
    }
  }

  /// Get user's ML features (preferences, history stats)
  Future<Map<String, dynamic>?> getUserFeatures() async {
    try {
      return await _api.getUserMLFeatures();
    } catch (e) {
      debugPrint('Error getting user ML features: $e');
      return null;
    }
  }

  /// Get recommendation statistics
  Future<Map<String, dynamic>?> getRecommendationStats() async {
    try {
      return await _api.getRecommendationStats();
    } catch (e) {
      debugPrint('Error getting recommendation stats: $e');
      return null;
    }
  }

  /// Find users similar to current user
  Future<List<Map<String, dynamic>>> getSimilarUsers() async {
    try {
      return await _api.getSimilarUsers();
    } catch (e) {
      debugPrint('Error getting similar users: $e');
      return [];
    }
  }

  /// Get explanation for why a pulse was recommended
  Future<String?> getRecommendationExplanation(String pulseId) async {
    try {
      return await _api.getRecommendationExplanation(pulseId);
    } catch (e) {
      debugPrint('Error getting recommendation explanation: $e');
      return null;
    }
  }

  /// Get user's interaction history
  Future<List<Map<String, dynamic>>> getInteractionHistory({
    int limit = 50,
  }) async {
    try {
      return await _api.getInteractionHistory(limit: limit);
    } catch (e) {
      debugPrint('Error getting interaction history: $e');
      return [];
    }
  }

  /// Recompute user features (trigger ML feature extraction)
  Future<bool> recomputeUserFeatures() async {
    try {
      await _api.recomputeUserFeatures();
      clearCache(); // Clear cache to get fresh recommendations
      return true;
    } catch (e) {
      debugPrint('Error recomputing user features: $e');
      return false;
    }
  }

  /// Get ML model statistics
  Future<Map<String, dynamic>?> getModelStats() async {
    try {
      return await _api.getMLModelStats();
    } catch (e) {
      debugPrint('Error getting model stats: $e');
      return null;
    }
  }

  /// Clear recommendation cache on backend
  Future<void> clearBackendCache() async {
    try {
      await _api.clearRecommendationCache();
      clearCache(); // Also clear local cache
    } catch (e) {
      debugPrint('Error clearing backend cache: $e');
    }
  }
}

/// Types of interactions for ML tracking
enum MLInteractionType {
  view('view'),
  join('join'),
  message('message'),
  share('share'),
  invite('invite'),
  recommendationView('recommendation_view'),
  recommendationClick('recommendation_click'),
  search('search');

  const MLInteractionType(this.value);
  final String value;
}

/// Helper extension for easy tracking
extension MLTrackingExtension on String {
  /// Track viewing this pulse
  Future<void> trackView({int? durationSeconds}) async {
    await MLRecommendationService.instance.trackInteraction(
      pulseId: this,
      type: MLInteractionType.view,
      durationSeconds: durationSeconds,
    );
  }

  /// Track joining this pulse
  Future<void> trackJoin() async {
    await MLRecommendationService.instance.trackInteraction(
      pulseId: this,
      type: MLInteractionType.join,
    );
  }

  /// Track messaging in this pulse
  Future<void> trackMessage() async {
    await MLRecommendationService.instance.trackInteraction(
      pulseId: this,
      type: MLInteractionType.message,
    );
  }

  /// Track sharing this pulse
  Future<void> trackShare() async {
    await MLRecommendationService.instance.trackInteraction(
      pulseId: this,
      type: MLInteractionType.share,
    );
  }

  /// Track clicking a recommendation
  Future<void> trackRecommendationClick() async {
    await MLRecommendationService.instance.trackInteraction(
      pulseId: this,
      type: MLInteractionType.recommendationClick,
    );
  }
}
