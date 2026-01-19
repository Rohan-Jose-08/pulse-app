import 'package:flutter/material.dart';
import '../flutter_flow/flutter_flow_theme.dart';
import '../services/ml_recommendation_service.dart';

/// Dashboard widget showing ML insights and personalization stats
class MLInsightsDashboard extends StatefulWidget {
  const MLInsightsDashboard({super.key});

  @override
  State<MLInsightsDashboard> createState() => _MLInsightsDashboardState();
}

class _MLInsightsDashboardState extends State<MLInsightsDashboard> {
  final _mlService = MLRecommendationService.instance;

  Map<String, dynamic>? _userFeatures;
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>>? _similarUsers;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    final results = await Future.wait([
      _mlService.getUserFeatures(),
      _mlService.getRecommendationStats(),
      _mlService.getSimilarUsers(),
    ]);

    setState(() {
      _userFeatures = results[0] as Map<String, dynamic>?;
      _stats = results[1] as Map<String, dynamic>?;
      _similarUsers = results[2] as List<Map<String, dynamic>>?;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: theme.primary),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(theme),
            const SizedBox(height: 24),
            if (_userFeatures != null) ...[
              _buildUserPreferences(theme),
              const SizedBox(height: 16),
            ],
            if (_stats != null) ...[
              _buildEngagementStats(theme),
              const SizedBox(height: 16),
            ],
            if (_similarUsers != null && _similarUsers!.isNotEmpty) ...[
              _buildSimilarUsers(theme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(FlutterFlowTheme theme) {
    return Row(
      children: [
        Icon(Icons.psychology, color: theme.primary, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your ML Insights',
                style: theme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'How we personalize your experience',
                style: theme.bodySmall?.copyWith(
                  color: theme.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUserPreferences(FlutterFlowTheme theme) {
    final features = _userFeatures!;
    final categories = features['favoriteCategories'] as List? ?? [];
    final activityLevel = features['activityLevel'] as String? ?? 'moderate';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.favorite, color: theme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Your Preferences',
                  style: theme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow(
              theme,
              'Activity Level',
              activityLevel.toUpperCase(),
              Icons.trending_up,
            ),
            const SizedBox(height: 12),
            if (categories.isNotEmpty) ...[
              Text(
                'Favorite Categories',
                style: theme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: categories
                    .take(5)
                    .map((cat) => Chip(
                          label: Text(
                            cat.toString(),
                            style: theme.bodySmall,
                          ),
                          backgroundColor: theme.primary.withOpacity(0.1),
                          side: BorderSide.none,
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEngagementStats(FlutterFlowTheme theme) {
    final stats = _stats!;
    final totalRecs = stats['totalRecommendations'] as int? ?? 0;
    final clicked = stats['clicked'] as int? ?? 0;
    final ctr = stats['clickThroughRate'] as double? ?? 0.0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bar_chart, color: theme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Engagement Stats',
                  style: theme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    theme,
                    'Recommendations',
                    totalRecs.toString(),
                    Icons.auto_awesome,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    theme,
                    'Clicked',
                    clicked.toString(),
                    Icons.touch_app,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    theme,
                    'Click Rate',
                    '${(ctr * 100).toStringAsFixed(1)}%',
                    Icons.trending_up,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    FlutterFlowTheme theme,
    String label,
    String value,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.primaryBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: theme.primary, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.bodySmall?.copyWith(
              color: theme.secondaryText,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSimilarUsers(FlutterFlowTheme theme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.people, color: theme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Similar Users',
                  style: theme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Users with similar interests help improve your recommendations',
              style: theme.bodySmall?.copyWith(
                color: theme.secondaryText,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${_similarUsers!.length} similar users found',
              style: theme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    FlutterFlowTheme theme,
    String label,
    String value,
    IconData icon,
  ) {
    return Row(
      children: [
        Icon(icon, color: theme.secondaryText, size: 18),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: theme.bodyMedium?.copyWith(
            color: theme.secondaryText,
          ),
        ),
        Text(
          value,
          style: theme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
