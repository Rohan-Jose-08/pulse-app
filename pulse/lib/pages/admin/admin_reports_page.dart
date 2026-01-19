import 'package:flutter/material.dart';
import '../../services/admin_moderation_service.dart';
import '../../flutter_flow/flutter_flow_theme.dart';

/// Admin page for managing reports
class AdminReportsPage extends StatefulWidget {
  const AdminReportsPage({super.key});

  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage> {
  final AdminModerationService _adminService = AdminModerationService.instance;

  List<AdminReport> _reports = [];
  bool _isLoading = true;
  String _statusFilter = 'PENDING';
  String _categoryFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() => _isLoading = true);

    final reports = await _adminService.getPendingReports();

    if (mounted) {
      setState(() {
        _reports = reports;
        _isLoading = false;
      });
    }
  }

  List<AdminReport> get _filteredReports {
    return _reports.where((report) {
      if (_categoryFilter != 'ALL' && report.category != _categoryFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Content Reports',
                style:
                    theme.headlineMedium.copyWith(fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  // Status Filter
                  _buildFilterDropdown(
                    value: _statusFilter,
                    items: ['PENDING', 'UNDER_REVIEW', 'RESOLVED', 'DISMISSED'],
                    onChanged: (value) {
                      setState(() => _statusFilter = value!);
                      _loadReports();
                    },
                    theme: theme,
                  ),
                  const SizedBox(width: 12),
                  // Category Filter
                  _buildFilterDropdown(
                    value: _categoryFilter,
                    items: [
                      'ALL',
                      'SPAM',
                      'HARASSMENT',
                      'VIOLENCE',
                      'HATE_SPEECH',
                      'SEXUAL_CONTENT',
                      'MISINFORMATION',
                      'ILLEGAL_ACTIVITY',
                      'OTHER',
                    ],
                    onChanged: (value) {
                      setState(() => _categoryFilter = value!);
                    },
                    theme: theme,
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: _loadReports,
                    icon: Icon(Icons.refresh_rounded, color: theme.primaryText),
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ],
          ),
        ),

        // Reports List
        Expanded(
          child: _isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(theme.primary),
                  ),
                )
              : _filteredReports.isEmpty
                  ? _buildEmptyState(theme)
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: _filteredReports.length,
                      itemBuilder: (context, index) {
                        return _buildReportCard(_filteredReports[index], theme);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildFilterDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required FlutterFlowTheme theme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.alternate),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          items: items.map((item) {
            return DropdownMenuItem(
              value: item,
              child: Text(
                _formatFilterLabel(item),
                style: theme.bodyMedium,
              ),
            );
          }).toList(),
          onChanged: onChanged,
          dropdownColor: theme.secondaryBackground,
        ),
      ),
    );
  }

  String _formatFilterLabel(String value) {
    if (value == 'ALL') return 'All Categories';
    return value
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}'
            : '')
        .join(' ');
  }

  Widget _buildEmptyState(FlutterFlowTheme theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 64,
            color: theme.success,
          ),
          const SizedBox(height: 16),
          Text(
            'No pending reports',
            style: theme.titleLarge.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'All reports have been reviewed',
            style: theme.bodyMedium.copyWith(color: theme.secondaryText),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(AdminReport report, FlutterFlowTheme theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
        border: report.isHighPriority
            ? Border.all(color: theme.error, width: 2)
            : null,
      ),
      child: InkWell(
        onTap: () => _showReportDetails(report),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  // Priority indicator
                  Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                      color: report.priorityColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Content Type Icon
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.alternate,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getContentTypeIcon(report.contentType),
                      size: 20,
                      color: theme.primaryText,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Report Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _formatContentType(report.contentType),
                              style: theme.bodyLarge.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildCategoryChip(report.category, theme),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Reported ${_formatTimeAgo(report.createdAt)} by ${report.reporterName ?? 'Anonymous'}',
                          style: theme.bodySmall.copyWith(
                            color: theme.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // AI Scores
                  if (report.aiToxicityScore != null)
                    _buildAiScoreBadge(report, theme),
                ],
              ),

              // Description
              if (report.description != null && report.description!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12, left: 56),
                  child: Text(
                    report.description!,
                    style:
                        theme.bodyMedium.copyWith(color: theme.secondaryText),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

              // Action Buttons
              Padding(
                padding: const EdgeInsets.only(top: 12, left: 56),
                child: Row(
                  children: [
                    _buildActionChip(
                      label: 'Review',
                      icon: Icons.visibility_rounded,
                      onTap: () => _showReportDetails(report),
                      theme: theme,
                    ),
                    const SizedBox(width: 8),
                    _buildActionChip(
                      label: 'Dismiss',
                      icon: Icons.close_rounded,
                      onTap: () => _dismissReport(report),
                      theme: theme,
                      isDestructive: false,
                    ),
                    const SizedBox(width: 8),
                    _buildActionChip(
                      label: 'Take Action',
                      icon: Icons.gavel_rounded,
                      onTap: () => _showActionDialog(report),
                      theme: theme,
                      isPrimary: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String category, FlutterFlowTheme theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _getCategoryColor(category).withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _formatFilterLabel(category),
        style: theme.bodySmall.copyWith(
          color: _getCategoryColor(category),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildAiScoreBadge(AdminReport report, FlutterFlowTheme theme) {
    final toxicity = report.aiToxicityScore ?? 0;
    final color = toxicity > 0.8
        ? theme.error
        : toxicity > 0.5
            ? Colors.orange
            : theme.success;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.smart_toy_rounded, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '${(toxicity * 100).toInt()}%',
            style: theme.bodySmall.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionChip({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required FlutterFlowTheme theme,
    bool isPrimary = false,
    bool isDestructive = false,
  }) {
    final color = isPrimary
        ? theme.primary
        : isDestructive
            ? theme.error
            : theme.secondaryText;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isPrimary ? theme.primary : Colors.transparent,
          border: Border.all(color: color.withOpacity(isPrimary ? 0 : 0.5)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isPrimary ? Colors.white : color,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.bodySmall.copyWith(
                color: isPrimary ? Colors.white : color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getContentTypeIcon(String contentType) {
    switch (contentType.toUpperCase()) {
      case 'PULSE':
        return Icons.explore_rounded;
      case 'POST':
        return Icons.article_rounded;
      case 'COMMENT':
        return Icons.comment_rounded;
      case 'MESSAGE':
        return Icons.message_rounded;
      case 'USER':
        return Icons.person_rounded;
      default:
        return Icons.description_rounded;
    }
  }

  String _formatContentType(String contentType) {
    return contentType.split('_').map((word) {
      return word.isNotEmpty
          ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}'
          : '';
    }).join(' ');
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

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }

  void _showReportDetails(AdminReport report) {
    final theme = FlutterFlowTheme.of(context);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          width: 600,
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'Report Details',
                      style: theme.headlineSmall.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Report Info
                _buildDetailSection(
                    'Report Information',
                    [
                      _buildDetailRow('ID', report.id, theme),
                      _buildDetailRow('Category',
                          _formatFilterLabel(report.category), theme),
                      if (report.subcategory != null)
                        _buildDetailRow(
                            'Subcategory', report.subcategory!, theme),
                      _buildDetailRow('Status', report.status, theme),
                      _buildDetailRow(
                          'Reported At', report.createdAt.toString(), theme),
                    ],
                    theme),

                const SizedBox(height: 16),

                // Reporter Info
                _buildDetailSection(
                    'Reporter',
                    [
                      _buildDetailRow(
                          'Name', report.reporterName ?? 'Anonymous', theme),
                      _buildDetailRow('User ID', report.reporterId, theme),
                    ],
                    theme),

                const SizedBox(height: 16),

                // AI Analysis
                if (report.aiToxicityScore != null)
                  _buildDetailSection(
                      'AI Analysis',
                      [
                        _buildDetailRow(
                          'Toxicity Score',
                          '${(report.aiToxicityScore! * 100).toInt()}%',
                          theme,
                        ),
                        if (report.aiSpamScore != null)
                          _buildDetailRow(
                            'Spam Score',
                            '${(report.aiSpamScore! * 100).toInt()}%',
                            theme,
                          ),
                        _buildDetailRow(
                          'Recommended Action',
                          report.aiRecommendedAction == true
                              ? 'Take Action'
                              : 'Review',
                          theme,
                        ),
                      ],
                      theme),

                const SizedBox(height: 16),

                // Description
                if (report.description != null)
                  _buildDetailSection(
                      'Description',
                      [
                        Text(
                          report.description!,
                          style: theme.bodyMedium,
                        ),
                      ],
                      theme),

                const SizedBox(height: 24),

                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _dismissReport(report);
                      },
                      child: const Text('Dismiss'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _showActionDialog(report);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Take Action'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailSection(
    String title,
    List<Widget> children,
    FlutterFlowTheme theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.titleSmall.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.secondaryText,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.primaryBackground,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, FlutterFlowTheme theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.bodySmall.copyWith(color: theme.secondaryText),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _dismissReport(AdminReport report) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Dismiss Report?'),
        content: const Text(
          'This will mark the report as dismissed without taking any action.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final success = await _adminService.resolveReport(
      reportId: report.id,
      resolution: 'DISMISSED',
      action: 'NO_ACTION',
      notes: 'Report dismissed by admin',
    );

    if (success && mounted) {
      setState(() {
        _reports.removeWhere((r) => r.id == report.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report dismissed')),
      );
    }
  }

  void _showActionDialog(AdminReport report) {
    final theme = FlutterFlowTheme.of(context);
    String selectedAction = 'WARN';
    final notesController = TextEditingController();
    int? duration;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text('Take Action', style: theme.titleLarge),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select action to take:',
                  style: theme.bodyMedium.copyWith(color: theme.secondaryText),
                ),
                const SizedBox(height: 12),

                // Action Options
                _buildRadioOption(
                  value: 'WARN',
                  groupValue: selectedAction,
                  label: 'Issue Warning',
                  description: 'Send a warning to the user',
                  onChanged: (v) => setDialogState(() => selectedAction = v!),
                  theme: theme,
                ),
                _buildRadioOption(
                  value: 'HIDE_CONTENT',
                  groupValue: selectedAction,
                  label: 'Hide Content',
                  description: 'Remove content from public view',
                  onChanged: (v) => setDialogState(() => selectedAction = v!),
                  theme: theme,
                ),
                _buildRadioOption(
                  value: 'REMOVE_CONTENT',
                  groupValue: selectedAction,
                  label: 'Remove Content',
                  description: 'Permanently delete the content',
                  onChanged: (v) => setDialogState(() => selectedAction = v!),
                  theme: theme,
                ),
                _buildRadioOption(
                  value: 'MUTE',
                  groupValue: selectedAction,
                  label: 'Mute User',
                  description: 'Temporarily restrict user from posting',
                  onChanged: (v) => setDialogState(() => selectedAction = v!),
                  theme: theme,
                ),
                _buildRadioOption(
                  value: 'SUSPEND',
                  groupValue: selectedAction,
                  label: 'Suspend User',
                  description: 'Temporarily ban user from the platform',
                  onChanged: (v) => setDialogState(() => selectedAction = v!),
                  theme: theme,
                ),
                _buildRadioOption(
                  value: 'BAN',
                  groupValue: selectedAction,
                  label: 'Ban User',
                  description: 'Permanently ban user from the platform',
                  onChanged: (v) => setDialogState(() => selectedAction = v!),
                  theme: theme,
                ),

                const SizedBox(height: 16),

                // Duration (for mute/suspend)
                if (selectedAction == 'MUTE' || selectedAction == 'SUSPEND')
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Duration:',
                        style: theme.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          _buildDurationChip(
                              1, duration, setDialogState, theme),
                          _buildDurationChip(
                              3, duration, setDialogState, theme),
                          _buildDurationChip(
                              7, duration, setDialogState, theme),
                          _buildDurationChip(
                              14, duration, setDialogState, theme),
                          _buildDurationChip(
                              30, duration, setDialogState, theme),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),

                // Notes
                TextField(
                  controller: notesController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Notes (optional)',
                    hintText: 'Add notes about this action...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: theme.bodyLarge),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _executeAction(
                  report,
                  selectedAction,
                  notesController.text,
                  duration,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Execute'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadioOption({
    required String value,
    required String groupValue,
    required String label,
    required String description,
    required ValueChanged<String?> onChanged,
    required FlutterFlowTheme theme,
  }) {
    return RadioListTile<String>(
      value: value,
      groupValue: groupValue,
      onChanged: onChanged,
      title: Text(label, style: theme.bodyLarge),
      subtitle: Text(
        description,
        style: theme.bodySmall.copyWith(color: theme.secondaryText),
      ),
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }

  Widget _buildDurationChip(
    int days,
    int? selected,
    StateSetter setDialogState,
    FlutterFlowTheme theme,
  ) {
    final isSelected = selected == days;
    return ChoiceChip(
      label: Text('$days ${days == 1 ? 'day' : 'days'}'),
      selected: isSelected,
      onSelected: (sel) => setDialogState(() => selected = sel ? days : null),
      selectedColor: theme.primary,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : theme.primaryText,
      ),
    );
  }

  Future<void> _executeAction(
    AdminReport report,
    String action,
    String notes,
    int? duration,
  ) async {
    bool success = false;

    switch (action) {
      case 'WARN':
        success = await _adminService.warnUser(
          userId: report.reportedUserData?['id'] ?? '',
          reason: report.category,
          message: notes.isNotEmpty ? notes : null,
        );
        break;
      case 'HIDE_CONTENT':
        success = await _adminService.hideContent(
          contentType: report.contentType,
          contentId: report.contentId,
          reason: report.category,
        );
        break;
      case 'REMOVE_CONTENT':
        success = await _adminService.removeContent(
          contentType: report.contentType,
          contentId: report.contentId,
          reason: report.category,
        );
        break;
      case 'MUTE':
        success = await _adminService.muteUser(
          userId: report.reportedUserData?['id'] ?? '',
          reason: report.category,
          durationHours: (duration ?? 1) * 24,
        );
        break;
      case 'SUSPEND':
        success = await _adminService.suspendUser(
          userId: report.reportedUserData?['id'] ?? '',
          reason: report.category,
          durationDays: duration ?? 7,
        );
        break;
      case 'BAN':
        success = await _adminService.banUser(
          userId: report.reportedUserData?['id'] ?? '',
          reason: report.category,
        );
        break;
    }

    if (success) {
      // Also resolve the report
      await _adminService.resolveReport(
        reportId: report.id,
        resolution: 'ACTION_TAKEN',
        action: action,
        notes: notes,
      );

      if (mounted) {
        setState(() {
          _reports.removeWhere((r) => r.id == report.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Action executed successfully')),
        );
      }
    }
  }
}
