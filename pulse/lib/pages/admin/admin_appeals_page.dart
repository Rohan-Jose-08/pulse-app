import 'package:flutter/material.dart';
import '../../services/admin_moderation_service.dart';
import '../../flutter_flow/flutter_flow_theme.dart';

/// Admin page for handling appeals
class AdminAppealsPage extends StatefulWidget {
  const AdminAppealsPage({super.key});

  @override
  State<AdminAppealsPage> createState() => _AdminAppealsPageState();
}

class _AdminAppealsPageState extends State<AdminAppealsPage> {
  final AdminModerationService _adminService = AdminModerationService.instance;

  List<ModerationAppeal> _appeals = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAppeals();
  }

  Future<void> _loadAppeals() async {
    setState(() => _isLoading = true);

    final appeals = await _adminService.getPendingAppeals();

    if (mounted) {
      setState(() {
        _appeals = appeals;
        _isLoading = false;
      });
    }
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
                'User Appeals',
                style:
                    theme.headlineMedium.copyWith(fontWeight: FontWeight.bold),
              ),
              IconButton(
                onPressed: _loadAppeals,
                icon: Icon(Icons.refresh_rounded, color: theme.primaryText),
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),

        // Appeals List
        Expanded(
          child: _isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(theme.primary),
                  ),
                )
              : _appeals.isEmpty
                  ? _buildEmptyState(theme)
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: _appeals.length,
                      itemBuilder: (context, index) {
                        return _buildAppealCard(_appeals[index], theme);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(FlutterFlowTheme theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.gavel_rounded,
            size: 64,
            color: theme.secondaryText,
          ),
          const SizedBox(height: 16),
          Text(
            'No pending appeals',
            style: theme.titleLarge.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'All user appeals have been reviewed',
            style: theme.bodyMedium.copyWith(color: theme.secondaryText),
          ),
        ],
      ),
    );
  }

  Widget _buildAppealCard(ModerationAppeal appeal, FlutterFlowTheme theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.gavel_rounded,
                    size: 20,
                    color: Colors.purple,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Appeal from ${appeal.userName ?? 'User'}',
                        style: theme.bodyLarge.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _buildActionTypeBadge(appeal.actionType, theme),
                          const SizedBox(width: 8),
                          Text(
                            '• ${_formatTimeAgo(appeal.createdAt)}',
                            style: theme.bodySmall.copyWith(
                              color: theme.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Appeal Reason
            Padding(
              padding: const EdgeInsets.only(top: 16, left: 44),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Appeal Reason:',
                    style: theme.bodySmall.copyWith(
                      color: theme.secondaryText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.primaryBackground,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      appeal.appealReason,
                      style: theme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),

            // Actions
            Padding(
              padding: const EdgeInsets.only(top: 16, left: 44),
              child: Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _showAppealDecisionDialog(appeal, true),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Accept'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.success,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _showAppealDecisionDialog(appeal, false),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.error,
                      side: BorderSide(color: theme.error),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _viewUserHistory(appeal.userId),
                    icon: Icon(
                      Icons.history_rounded,
                      size: 18,
                      color: theme.secondaryText,
                    ),
                    label: Text(
                      'View History',
                      style: theme.bodySmall.copyWith(
                        color: theme.secondaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTypeBadge(String actionType, FlutterFlowTheme theme) {
    Color color;
    String label;

    switch (actionType.toUpperCase()) {
      case 'WARNING':
        color = Colors.amber;
        label = 'Warning';
        break;
      case 'MUTE':
        color = Colors.orange;
        label = 'Mute';
        break;
      case 'SUSPENSION':
        color = Colors.red;
        label = 'Suspension';
        break;
      case 'BAN':
        color = Colors.red.shade900;
        label = 'Ban';
        break;
      default:
        color = Colors.grey;
        label = actionType;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.bodySmall.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
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

  void _showAppealDecisionDialog(ModerationAppeal appeal, bool accept) {
    final theme = FlutterFlowTheme.of(context);
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          accept ? 'Accept Appeal' : 'Reject Appeal',
          style: theme.titleLarge,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              accept
                  ? 'This will reverse the moderation action and restore the user\'s standing.'
                  : 'This will deny the appeal and keep the moderation action in place.',
              style: theme.bodyMedium.copyWith(color: theme.secondaryText),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Reason',
                hintText: 'Provide a reason for your decision...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: theme.bodyLarge),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _resolveAppeal(
                appeal,
                accept ? 'ACCEPTED' : 'REJECTED',
                reasonController.text,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: accept ? theme.success : theme.error,
              foregroundColor: Colors.white,
            ),
            child: Text(accept ? 'Accept' : 'Reject'),
          ),
        ],
      ),
    );
  }

  Future<void> _resolveAppeal(
    ModerationAppeal appeal,
    String decision,
    String reason,
  ) async {
    final success = await _adminService.resolveAppeal(
      appealId: appeal.id,
      decision: decision,
      reason: reason.isNotEmpty ? reason : 'No reason provided',
    );

    if (success && mounted) {
      setState(() {
        _appeals.removeWhere((a) => a.id == appeal.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            decision == 'ACCEPTED' ? 'Appeal accepted' : 'Appeal rejected',
          ),
        ),
      );
    }
  }

  void _viewUserHistory(String userId) {
    // Navigate to user history page or show dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('User history feature coming soon')),
    );
  }
}
