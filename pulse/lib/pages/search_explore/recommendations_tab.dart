import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:geolocator/geolocator.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import '../../backend/api_service.dart';
import '../../services/ml_recommendation_service.dart';
import '../pulse_detail/pulse_detail_page.dart';
import 'search_explore_providers.dart';
import '../../widgets/ml_insights_dashboard.dart';

/// Provider for ML-powered personalized recommendations
final personalizedRecommendationsProvider =
    FutureProvider.autoDispose<List<ExplorePulse>>((ref) async {
  try {
    final mlService = MLRecommendationService.instance;

    // Try to get user's location for better recommendations
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 5),
      );
    } catch (e) {
      print('Could not get location for recommendations: $e');
    }

    final recommendations = await mlService.getPersonalizedRecommendations(
      latitude: position?.latitude,
      longitude: position?.longitude,
    );

    if (recommendations.isEmpty) {
      return [];
    }

    // Convert to ExplorePulse objects
    return recommendations
        .map((pulseData) => ExplorePulse.fromMap(pulseData))
        .toList();
  } catch (e) {
    print('Error fetching personalized recommendations: $e');
    return [];
  }
});

class RecommendationsTab extends ConsumerStatefulWidget {
  const RecommendationsTab({super.key});

  @override
  ConsumerState<RecommendationsTab> createState() => _RecommendationsTabState();
}

class _RecommendationsTabState extends ConsumerState<RecommendationsTab> {
  bool _showInsights = false;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final recommendations = ref.watch(personalizedRecommendationsProvider);

    if (_showInsights) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: theme.primaryBackground,
          title: Text('ML Insights', style: theme.headlineSmall),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: theme.primaryText),
            onPressed: () => setState(() => _showInsights = false),
          ),
        ),
        body: const MLInsightsDashboard(),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(personalizedRecommendationsProvider);
        // Also clear ML cache to get fresh data
        MLRecommendationService.instance.clearCache();
      },
      color: theme.primary,
      backgroundColor: theme.secondaryBackground,
      child: recommendations.when(
        data: (pulses) {
          if (pulses.isEmpty) {
            return _EmptyRecommendations(theme: theme);
          }

          return CustomScrollView(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.auto_awesome,
                              color: theme.primary, size: 24),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'For You',
                                  style: theme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Personalized pulse recommendations based on your interests',
                                  style: theme.bodySmall?.copyWith(
                                    color: theme.secondaryText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.insights, color: theme.primary),
                            onPressed: () {
                              setState(() => _showInsights = true);
                            },
                            tooltip: 'View ML Insights',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                sliver: SliverMasonryGrid.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childCount: pulses.length,
                  itemBuilder: (context, index) {
                    final pulse = pulses[index];
                    return _RecommendationCard(
                      pulse: pulse,
                      onTap: () async {
                        // Track recommendation click using ML service
                        await pulse.id.trackRecommendationClick();

                        // Navigate to pulse detail
                        if (context.mounted) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  PulseDetailPage(pulseId: pulse.id),
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          );
        },
        loading: () => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: theme.primary),
              const SizedBox(height: 16),
              Text('Finding pulses for you...',
                  style:
                      theme.bodyMedium?.copyWith(color: theme.secondaryText)),
            ],
          ),
        ),
        error: (error, stack) => _ErrorRecommendations(
          theme: theme,
          error: error.toString(),
          onRetry: () => ref.invalidate(personalizedRecommendationsProvider),
        ),
      ),
    );
  }
}

class _RecommendationCard extends StatefulWidget {
  const _RecommendationCard({
    required this.pulse,
    required this.onTap,
  });

  final ExplorePulse pulse;
  final VoidCallback onTap;

  @override
  State<_RecommendationCard> createState() => _RecommendationCardState();
}

class _RecommendationCardState extends State<_RecommendationCard> {
  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              offset: const Offset(0, 2),
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pulse Image
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    widget.pulse.imageUrl.isNotEmpty
                        ? Image.network(
                            widget.pulse.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: theme.alternate,
                              child: Icon(Icons.image_not_supported,
                                  color: theme.secondaryText),
                            ),
                          )
                        : Container(
                            color: theme.alternate,
                            child: Icon(Icons.event,
                                size: 48, color: theme.secondaryText),
                          ),
                    // AI Badge
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.primary.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome,
                                size: 12, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              'For You',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Pulse Info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.pulse.title,
                    style: theme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.person_outline,
                          size: 14, color: theme.secondaryText),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          widget.pulse.hostUsername,
                          style: theme.bodySmall
                              ?.copyWith(color: theme.secondaryText),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (widget.pulse.location.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined,
                            size: 14, color: theme.secondaryText),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            widget.pulse.location,
                            style: theme.bodySmall
                                ?.copyWith(color: theme.secondaryText),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (widget.pulse.time != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.access_time,
                            size: 14, color: theme.secondaryText),
                        const SizedBox(width: 4),
                        Text(
                          _formatTime(widget.pulse.time!),
                          style: theme.bodySmall
                              ?.copyWith(color: theme.secondaryText),
                        ),
                      ],
                    ),
                  ],
                  if (widget.pulse.distanceKm != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.near_me, size: 14, color: theme.primary),
                        const SizedBox(width: 4),
                        Text(
                          '${widget.pulse.distanceKm!.toStringAsFixed(1)} km away',
                          style: theme.bodySmall?.copyWith(
                              color: theme.primary,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = time.difference(now);

    if (difference.inDays > 7) {
      return '${time.month}/${time.day}';
    } else if (difference.inDays > 1) {
      return 'in ${difference.inDays} days';
    } else if (difference.inDays == 1) {
      return 'Tomorrow';
    } else if (difference.inHours > 0) {
      return 'in ${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return 'in ${difference.inMinutes}m';
    } else {
      return 'Now';
    }
  }
}

class _EmptyRecommendations extends StatelessWidget {
  const _EmptyRecommendations({required this.theme});

  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.explore_outlined,
                size: 80, color: theme.secondaryText.withOpacity(0.4)),
            const SizedBox(height: 24),
            Text(
              'No recommendations yet',
              style: theme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Join some pulses and interact with the community to get personalized recommendations!',
              style: theme.bodyMedium?.copyWith(color: theme.secondaryText),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                // Navigate to explore tab (handled by parent)
              },
              icon: const Icon(Icons.explore),
              label: const Text('Explore Pulses'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorRecommendations extends StatelessWidget {
  const _ErrorRecommendations({
    required this.theme,
    required this.error,
    required this.onRetry,
  });

  final FlutterFlowTheme theme;
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline,
                size: 64, color: theme.error.withOpacity(0.6)),
            const SizedBox(height: 16),
            Text(
              'Unable to load recommendations',
              style: theme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Please check your connection and try again',
              style: theme.bodySmall?.copyWith(color: theme.secondaryText),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
