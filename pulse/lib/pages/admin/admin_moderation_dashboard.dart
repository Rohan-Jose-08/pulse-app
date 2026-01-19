import 'package:flutter/material.dart';
import '../../services/admin_moderation_service.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import 'admin_reports_page.dart';
import 'admin_appeals_page.dart';
import 'admin_audit_log_page.dart';

/// Admin moderation dashboard home page
class AdminModerationDashboard extends StatefulWidget {
  const AdminModerationDashboard({super.key});

  @override
  State<AdminModerationDashboard> createState() =>
      _AdminModerationDashboardState();
}

class _AdminModerationDashboardState extends State<AdminModerationDashboard> {
  final AdminModerationService _adminService = AdminModerationService.instance;

  ModerationStats? _stats;
  ModerationAnalytics? _analytics;
  bool _isLoading = true;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);

    final results = await Future.wait([
      _adminService.getStats(),
      _adminService.getAnalytics(days: 30),
    ]);

    if (mounted) {
      setState(() {
        _stats = results[0] as ModerationStats?;
        _analytics = results[1] as ModerationAnalytics?;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Scaffold(
      backgroundColor: theme.primaryBackground,
      body: Row(
        children: [
          // Side Navigation
          _buildSideNavigation(theme),
          // Main Content
          Expanded(
            child: _buildMainContent(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildSideNavigation(FlutterFlowTheme theme) {
    return Container(
      width: 250,
      color: theme.secondaryBackground,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.shield_rounded,
                    color: theme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Moderation',
                  style: theme.titleLarge.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Navigation Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildNavItem(
                  icon: Icons.dashboard_rounded,
                  label: 'Dashboard',
                  index: 0,
                  theme: theme,
                ),
                _buildNavItem(
                  icon: Icons.report_rounded,
                  label: 'Reports',
                  index: 1,
                  theme: theme,
                  badge: _stats?.pendingReports,
                ),
                _buildNavItem(
                  icon: Icons.gavel_rounded,
                  label: 'Appeals',
                  index: 2,
                  theme: theme,
                  badge: _stats?.pendingAppeals,
                ),
                _buildNavItem(
                  icon: Icons.people_rounded,
                  label: 'Users',
                  index: 3,
                  theme: theme,
                ),
                _buildNavItem(
                  icon: Icons.history_rounded,
                  label: 'Audit Log',
                  index: 4,
                  theme: theme,
                ),
                _buildNavItem(
                  icon: Icons.settings_rounded,
                  label: 'Settings',
                  index: 5,
                  theme: theme,
                ),
              ],
            ),
          ),
          // Back Button
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.arrow_back_rounded, color: theme.secondaryText),
              label: Text(
                'Back to App',
                style: theme.bodyMedium.copyWith(color: theme.secondaryText),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
    required FlutterFlowTheme theme,
    int? badge,
  }) {
    final isSelected = _selectedIndex == index;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? theme.primary.withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          icon,
          color: isSelected ? theme.primary : theme.secondaryText,
          size: 20,
        ),
        title: Text(
          label,
          style: theme.bodyMedium.copyWith(
            color: isSelected ? theme.primary : theme.primaryText,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        trailing: badge != null && badge > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.error,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge > 99 ? '99+' : badge.toString(),
                  style: theme.bodySmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : null,
        onTap: () {
          setState(() => _selectedIndex = index);
        },
      ),
    );
  }

  Widget _buildMainContent(FlutterFlowTheme theme) {
    switch (_selectedIndex) {
      case 0:
        return _buildDashboardContent(theme);
      case 1:
        return const AdminReportsPage();
      case 2:
        return const AdminAppealsPage();
      case 4:
        return const AdminAuditLogPage();
      default:
        return _buildDashboardContent(theme);
    }
  }

  Widget _buildDashboardContent(FlutterFlowTheme theme) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(theme.primary),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      color: theme.primary,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Moderation Dashboard',
                  style: theme.headlineMedium
                      .copyWith(fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  onPressed: _loadDashboardData,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Refresh'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Stats Cards
            _buildStatsCards(theme),
            const SizedBox(height: 24),

            // Charts Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildReportsChart(theme)),
                const SizedBox(width: 16),
                Expanded(child: _buildCategoryBreakdown(theme)),
              ],
            ),
            const SizedBox(height: 24),

            // Quick Actions
            _buildQuickActions(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCards(FlutterFlowTheme theme) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _buildStatCard(
          title: 'Pending Reports',
          value: _stats?.pendingReports.toString() ?? '0',
          icon: Icons.report_rounded,
          color: Colors.orange,
          theme: theme,
        ),
        _buildStatCard(
          title: 'Resolved Today',
          value: _stats?.resolvedToday.toString() ?? '0',
          icon: Icons.check_circle_rounded,
          color: Colors.green,
          theme: theme,
        ),
        _buildStatCard(
          title: 'Active Warnings',
          value: _stats?.activeWarnings.toString() ?? '0',
          icon: Icons.warning_rounded,
          color: Colors.amber,
          theme: theme,
        ),
        _buildStatCard(
          title: 'Suspended Users',
          value: _stats?.suspendedUsers.toString() ?? '0',
          icon: Icons.person_off_rounded,
          color: Colors.red,
          theme: theme,
        ),
        _buildStatCard(
          title: 'Banned Users',
          value: _stats?.bannedUsers.toString() ?? '0',
          icon: Icons.block_rounded,
          color: Colors.red.shade800,
          theme: theme,
        ),
        _buildStatCard(
          title: 'Pending Appeals',
          value: _stats?.pendingAppeals.toString() ?? '0',
          icon: Icons.gavel_rounded,
          color: Colors.purple,
          theme: theme,
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required FlutterFlowTheme theme,
  }) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: theme.headlineMedium.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.primaryText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: theme.bodySmall.copyWith(color: theme.secondaryText),
          ),
        ],
      ),
    );
  }

  Widget _buildReportsChart(FlutterFlowTheme theme) {
    final reportsByDay = _analytics?.reportsByDay ?? [];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reports Over Time (30 days)',
            style: theme.titleMedium.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: reportsByDay.isEmpty
                ? Center(
                    child: Text(
                      'No data available',
                      style:
                          theme.bodyMedium.copyWith(color: theme.secondaryText),
                    ),
                  )
                : CustomPaint(
                    size: const Size(double.infinity, 200),
                    painter: _SimpleChartPainter(
                      data:
                          reportsByDay.map((d) => d.count.toDouble()).toList(),
                      color: theme.primary,
                      backgroundColor: theme.alternate,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBreakdown(FlutterFlowTheme theme) {
    final categories = _analytics?.reportsByCategory ?? {};

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reports by Category',
            style: theme.titleMedium.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          if (categories.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Text(
                  'No data available',
                  style: theme.bodyMedium.copyWith(color: theme.secondaryText),
                ),
              ),
            )
          else
            ...categories.entries.map((entry) {
              final total = categories.values.fold<int>(0, (sum, v) => sum + v);
              final percentage = total > 0 ? (entry.value / total * 100) : 0.0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatCategory(entry.key),
                          style: theme.bodyMedium,
                        ),
                        Text(
                          '${entry.value} (${percentage.toStringAsFixed(1)}%)',
                          style: theme.bodySmall
                              .copyWith(color: theme.secondaryText),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: percentage / 100,
                      backgroundColor: theme.alternate,
                      valueColor: AlwaysStoppedAnimation(
                        _getCategoryColor(entry.key),
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              );
            }).toList(),
        ],
      ),
    );
  }

  Widget _buildQuickActions(FlutterFlowTheme theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Actions',
            style: theme.titleMedium.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildActionButton(
                icon: Icons.report_rounded,
                label: 'Review Reports',
                onTap: () => setState(() => _selectedIndex = 1),
                theme: theme,
              ),
              _buildActionButton(
                icon: Icons.gavel_rounded,
                label: 'Handle Appeals',
                onTap: () => setState(() => _selectedIndex = 2),
                theme: theme,
              ),
              _buildActionButton(
                icon: Icons.search_rounded,
                label: 'Search User',
                onTap: () => _showUserSearch(context),
                theme: theme,
              ),
              _buildActionButton(
                icon: Icons.analytics_rounded,
                label: 'View Analytics',
                onTap: () {},
                theme: theme,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required FlutterFlowTheme theme,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: theme.alternate),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: theme.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.bodyMedium.copyWith(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCategory(String category) {
    return category
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}'
            : '')
        .join(' ');
  }

  Color _getCategoryColor(String category) {
    switch (category.toUpperCase()) {
      case 'SPAM':
        return Colors.orange;
      case 'HARASSMENT':
        return Colors.red;
      case 'VIOLENCE':
        return Colors.red.shade800;
      case 'HATE_SPEECH':
        return Colors.purple;
      case 'SEXUAL_CONTENT':
        return Colors.pink;
      case 'MISINFORMATION':
        return Colors.amber;
      case 'ILLEGAL_ACTIVITY':
        return Colors.red.shade900;
      default:
        return Colors.blue;
    }
  }

  void _showUserSearch(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text('Search User', style: theme.titleLarge),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'Enter user ID or email',
            prefixIcon: const Icon(Icons.search_rounded),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: theme.bodyLarge),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Navigate to user moderation page
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }
}

/// Simple chart painter for reports over time
class _SimpleChartPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final Color backgroundColor;

  _SimpleChartPainter({
    required this.data,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final maxValue = data.reduce((a, b) => a > b ? a : b);
    if (maxValue == 0) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = color.withOpacity(0.1)
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();

    final stepX = size.width / (data.length - 1);

    for (var i = 0; i < data.length; i++) {
      final x = i * stepX;
      final y = size.height - (data[i] / maxValue * size.height);

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
