import 'package:flutter/material.dart';
import '../../services/admin_moderation_service.dart';
import '../../flutter_flow/flutter_flow_theme.dart';

/// Admin page for viewing audit log
class AdminAuditLogPage extends StatefulWidget {
  const AdminAuditLogPage({super.key});

  @override
  State<AdminAuditLogPage> createState() => _AdminAuditLogPageState();
}

class _AdminAuditLogPageState extends State<AdminAuditLogPage> {
  final AdminModerationService _adminService = AdminModerationService.instance;

  List<AuditLogEntry> _entries = [];
  bool _isLoading = true;
  int _currentPage = 1;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadAuditLog();
  }

  Future<void> _loadAuditLog({bool refresh = false}) async {
    if (refresh) {
      _currentPage = 1;
      _hasMore = true;
    }

    if (!_hasMore && !refresh) return;

    setState(() => _isLoading = true);

    final entries = await _adminService.getAuditLog(page: _currentPage);

    if (mounted) {
      setState(() {
        if (refresh) {
          _entries = entries;
        } else {
          _entries.addAll(entries);
        }
        _hasMore = entries.length >= 50;
        _isLoading = false;
      });
    }
  }

  void _loadMore() {
    if (!_isLoading && _hasMore) {
      _currentPage++;
      _loadAuditLog();
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Audit Log',
                    style: theme.headlineMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Track all moderation actions taken by administrators',
                    style:
                        theme.bodyMedium.copyWith(color: theme.secondaryText),
                  ),
                ],
              ),
              IconButton(
                onPressed: () => _loadAuditLog(refresh: true),
                icon: Icon(Icons.refresh_rounded, color: theme.primaryText),
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),

        // Audit Log List
        Expanded(
          child: _isLoading && _entries.isEmpty
              ? Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(theme.primary),
                  ),
                )
              : _entries.isEmpty
                  ? _buildEmptyState(theme)
                  : NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is ScrollEndNotification &&
                            notification.metrics.extentAfter < 100) {
                          _loadMore();
                        }
                        return false;
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        itemCount: _entries.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _entries.length) {
                            return Padding(
                              padding: const EdgeInsets.all(16),
                              child: Center(
                                child: CircularProgressIndicator(
                                  valueColor:
                                      AlwaysStoppedAnimation(theme.primary),
                                ),
                              ),
                            );
                          }
                          return _buildLogEntry(_entries[index], theme);
                        },
                      ),
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
            Icons.history_rounded,
            size: 64,
            color: theme.secondaryText,
          ),
          const SizedBox(height: 16),
          Text(
            'No audit entries',
            style: theme.titleLarge.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Moderation actions will appear here',
            style: theme.bodyMedium.copyWith(color: theme.secondaryText),
          ),
        ],
      ),
    );
  }

  Widget _buildLogEntry(AuditLogEntry entry, FlutterFlowTheme theme) {
    final actionInfo = _getActionInfo(entry.action);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _showEntryDetails(entry),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Action Icon
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: actionInfo.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  actionInfo.icon,
                  size: 20,
                  color: actionInfo.color,
                ),
              ),
              const SizedBox(width: 12),
              // Entry Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            actionInfo.label,
                            style: theme.bodyLarge.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          _formatDateTime(entry.createdAt),
                          style: theme.bodySmall.copyWith(
                            color: theme.secondaryText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _buildActionDescription(entry),
                      style: theme.bodyMedium.copyWith(
                        color: theme.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Admin Info
                    Row(
                      children: [
                        Icon(
                          Icons.admin_panel_settings_rounded,
                          size: 14,
                          color: theme.secondaryText,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          entry.adminName ?? 'Admin',
                          style: theme.bodySmall.copyWith(
                            color: theme.secondaryText,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
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

  ({IconData icon, Color color, String label}) _getActionInfo(String action) {
    switch (action.toUpperCase()) {
      case 'WARN_USER':
        return (
          icon: Icons.warning_rounded,
          color: Colors.amber,
          label: 'User Warning'
        );
      case 'MUTE_USER':
        return (
          icon: Icons.volume_off_rounded,
          color: Colors.orange,
          label: 'User Muted'
        );
      case 'SUSPEND_USER':
        return (
          icon: Icons.person_off_rounded,
          color: Colors.red,
          label: 'User Suspended'
        );
      case 'BAN_USER':
        return (
          icon: Icons.block_rounded,
          color: Colors.red.shade800,
          label: 'User Banned'
        );
      case 'HIDE_CONTENT':
        return (
          icon: Icons.visibility_off_rounded,
          color: Colors.blue,
          label: 'Content Hidden'
        );
      case 'REMOVE_CONTENT':
        return (
          icon: Icons.delete_rounded,
          color: Colors.red,
          label: 'Content Removed'
        );
      case 'RESTORE_CONTENT':
        return (
          icon: Icons.restore_rounded,
          color: Colors.green,
          label: 'Content Restored'
        );
      case 'RESOLVE_REPORT':
        return (
          icon: Icons.check_circle_rounded,
          color: Colors.green,
          label: 'Report Resolved'
        );
      case 'DISMISS_REPORT':
        return (
          icon: Icons.cancel_rounded,
          color: Colors.grey,
          label: 'Report Dismissed'
        );
      case 'ACCEPT_APPEAL':
        return (
          icon: Icons.thumb_up_rounded,
          color: Colors.green,
          label: 'Appeal Accepted'
        );
      case 'REJECT_APPEAL':
        return (
          icon: Icons.thumb_down_rounded,
          color: Colors.red,
          label: 'Appeal Rejected'
        );
      case 'UNBAN_USER':
        return (
          icon: Icons.person_add_rounded,
          color: Colors.green,
          label: 'User Unbanned'
        );
      default:
        return (
          icon: Icons.history_rounded,
          color: Colors.grey,
          label: _formatActionLabel(action)
        );
    }
  }

  String _formatActionLabel(String action) {
    return action
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}'
            : '')
        .join(' ');
  }

  String _buildActionDescription(AuditLogEntry entry) {
    final parts = <String>[];

    if (entry.targetUserName != null) {
      parts.add('Target: ${entry.targetUserName}');
    }

    if (entry.contentType != null && entry.contentId != null) {
      parts.add('${entry.contentType}: ${entry.contentId.substring(0, 8)}...');
    }

    if (parts.isEmpty) {
      return 'No additional details';
    }

    return parts.join(' • ');
  }

  String _formatDateTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  void _showEntryDetails(AuditLogEntry entry) {
    final theme = FlutterFlowTheme.of(context);
    final actionInfo = _getActionInfo(entry.action);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: actionInfo.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      actionInfo.icon,
                      size: 24,
                      color: actionInfo.color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      actionInfo.label,
                      style: theme.titleLarge.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Details
              _buildDetailRow('Entry ID', entry.id, theme),
              _buildDetailRow('Action', entry.action, theme),
              _buildDetailRow(
                'Performed By',
                entry.adminName ?? entry.adminId,
                theme,
              ),
              _buildDetailRow(
                'Date & Time',
                entry.createdAt.toString(),
                theme,
              ),
              if (entry.targetUserId != null)
                _buildDetailRow(
                  'Target User',
                  entry.targetUserName ?? entry.targetUserId!,
                  theme,
                ),
              if (entry.contentType != null)
                _buildDetailRow('Content Type', entry.contentType!, theme),
              if (entry.contentId != null)
                _buildDetailRow('Content ID', entry.contentId!, theme),

              // Additional Details
              if (entry.details != null && entry.details!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Additional Details',
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
                  child: Text(
                    entry.details.toString(),
                    style: theme.bodySmall.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
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
}
