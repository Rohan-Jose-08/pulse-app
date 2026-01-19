import 'package:flutter/material.dart';
import '../../services/moderation_service.dart';
import '../../flutter_flow/flutter_flow_theme.dart';

/// Bottom sheet for event organizers to moderate their pulse content
class PulseModerationSheet extends StatefulWidget {
  final String pulseId;
  final String pulseTitle;
  final bool isOrganizer;

  const PulseModerationSheet({
    super.key,
    required this.pulseId,
    required this.pulseTitle,
    required this.isOrganizer,
  });

  static Future<void> show(
    BuildContext context, {
    required String pulseId,
    required String pulseTitle,
    required bool isOrganizer,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PulseModerationSheet(
        pulseId: pulseId,
        pulseTitle: pulseTitle,
        isOrganizer: isOrganizer,
      ),
    );
  }

  @override
  State<PulseModerationSheet> createState() => _PulseModerationSheetState();
}

class _PulseModerationSheetState extends State<PulseModerationSheet> {
  final ModerationService _moderationService = ModerationService.instance;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.alternate,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.shield_rounded,
                    color: theme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pulse Moderation',
                        style: theme.titleLarge.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        widget.pulseTitle,
                        style: theme.bodyMedium.copyWith(
                          color: theme.secondaryText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Options
          if (widget.isOrganizer) ...[
            _buildOptionTile(
              icon: Icons.comment_rounded,
              title: 'Manage Comments',
              subtitle: 'Review and moderate comments on this pulse',
              onTap: () => _showCommentsModeration(context),
              theme: theme,
            ),
            _buildOptionTile(
              icon: Icons.people_rounded,
              title: 'Manage Attendees',
              subtitle: 'View attendees and manage access',
              onTap: () => _showAttendeesManagement(context),
              theme: theme,
            ),
            _buildOptionTile(
              icon: Icons.block_rounded,
              title: 'Block Users',
              subtitle: 'Prevent specific users from joining',
              onTap: () => _showBlockedUsers(context),
              theme: theme,
            ),
            _buildOptionTile(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Chat Settings',
              subtitle: 'Configure chat moderation for this pulse',
              onTap: () => _showChatSettings(context),
              theme: theme,
            ),
            _buildOptionTile(
              icon: Icons.report_outlined,
              title: 'View Reports',
              subtitle: 'See content reported by attendees',
              onTap: () => _showPulseReports(context),
              theme: theme,
            ),
          ],

          // Report option for everyone
          _buildOptionTile(
            icon: Icons.flag_outlined,
            title: 'Report This Pulse',
            subtitle: 'Report inappropriate content or behavior',
            onTap: () => _reportPulse(context),
            theme: theme,
            isDestructive: true,
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required FlutterFlowTheme theme,
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDestructive
                    ? theme.error.withOpacity(0.1)
                    : theme.alternate,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: isDestructive ? theme.error : theme.primaryText,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDestructive ? theme.error : theme.primaryText,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.bodySmall.copyWith(
                      color: theme.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.secondaryText,
            ),
          ],
        ),
      ),
    );
  }

  void _showCommentsModeration(BuildContext context) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PulseCommentsModeration(pulseId: widget.pulseId),
      ),
    );
  }

  void _showAttendeesManagement(BuildContext context) {
    Navigator.pop(context);
    // Navigate to attendees management
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Attendees management coming soon')),
    );
  }

  void _showBlockedUsers(BuildContext context) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PulseBlockedUsers(pulseId: widget.pulseId),
      ),
    );
  }

  void _showChatSettings(BuildContext context) {
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (context) => PulseChatSettingsDialog(pulseId: widget.pulseId),
    );
  }

  void _showPulseReports(BuildContext context) {
    Navigator.pop(context);
    // Navigate to pulse reports
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pulse reports feature coming soon')),
    );
  }

  void _reportPulse(BuildContext context) {
    Navigator.pop(context);
    // Show report dialog
    _moderationService.reportContent(
      reportedPulseId: widget.pulseId,
      category: ReportCategory.other,
    );
  }
}

/// Page for moderating comments on a pulse
class PulseCommentsModeration extends StatefulWidget {
  final String pulseId;

  const PulseCommentsModeration({super.key, required this.pulseId});

  @override
  State<PulseCommentsModeration> createState() =>
      _PulseCommentsModerationState();
}

class _PulseCommentsModerationState extends State<PulseCommentsModeration> {
  List<Map<String, dynamic>> _comments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  Future<void> _loadComments() async {
    // Load comments from API
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.secondaryBackground,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: theme.primaryText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Moderate Comments',
          style: theme.headlineSmall.copyWith(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: theme.primaryText),
            onPressed: _loadComments,
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(theme.primary),
              ),
            )
          : _comments.isEmpty
              ? _buildEmptyState(theme)
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _comments.length,
                  itemBuilder: (context, index) {
                    return _buildCommentTile(_comments[index], theme);
                  },
                ),
    );
  }

  Widget _buildEmptyState(FlutterFlowTheme theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.comment_outlined,
            size: 64,
            color: theme.secondaryText,
          ),
          const SizedBox(height: 16),
          Text(
            'No comments yet',
            style: theme.titleLarge.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Comments on this pulse will appear here',
            style: theme.bodyMedium.copyWith(color: theme.secondaryText),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentTile(
      Map<String, dynamic> comment, FlutterFlowTheme theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User info
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: theme.primary.withOpacity(0.2),
                child: Icon(
                  Icons.person_outline_rounded,
                  color: theme.primary,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comment['userName'] ?? 'User',
                      style: theme.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '2h ago',
                      style: theme.bodySmall.copyWith(
                        color: theme.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: theme.secondaryText),
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'hide', child: Text('Hide')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  const PopupMenuItem(value: 'warn', child: Text('Warn User')),
                  const PopupMenuItem(
                      value: 'block', child: Text('Block User')),
                ],
                onSelected: (action) => _handleCommentAction(comment, action),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Comment content
          Text(
            comment['content'] ?? '',
            style: theme.bodyMedium,
          ),
        ],
      ),
    );
  }

  void _handleCommentAction(Map<String, dynamic> comment, String action) {
    switch (action) {
      case 'hide':
        // Hide comment
        break;
      case 'delete':
        // Delete comment
        break;
      case 'warn':
        // Warn user
        break;
      case 'block':
        // Block user from pulse
        break;
    }
  }
}

/// Page for managing blocked users on a pulse
class PulseBlockedUsers extends StatefulWidget {
  final String pulseId;

  const PulseBlockedUsers({super.key, required this.pulseId});

  @override
  State<PulseBlockedUsers> createState() => _PulseBlockedUsersState();
}

class _PulseBlockedUsersState extends State<PulseBlockedUsers> {
  List<Map<String, dynamic>> _blockedUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    // Load blocked users from API
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.secondaryBackground,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: theme.primaryText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Blocked Users',
          style: theme.headlineSmall.copyWith(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.person_add_rounded, color: theme.primary),
            onPressed: () => _showAddBlockedUser(context),
            tooltip: 'Block User',
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(theme.primary),
              ),
            )
          : _blockedUsers.isEmpty
              ? _buildEmptyState(theme)
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _blockedUsers.length,
                  itemBuilder: (context, index) {
                    return _buildBlockedUserTile(_blockedUsers[index], theme);
                  },
                ),
    );
  }

  Widget _buildEmptyState(FlutterFlowTheme theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.block_rounded,
            size: 64,
            color: theme.secondaryText,
          ),
          const SizedBox(height: 16),
          Text(
            'No blocked users',
            style: theme.titleLarge.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Users you block from this pulse will appear here',
            style: theme.bodyMedium.copyWith(color: theme.secondaryText),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBlockedUserTile(
    Map<String, dynamic> user,
    FlutterFlowTheme theme,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: theme.error.withOpacity(0.2),
          child: Icon(Icons.person_off_rounded, color: theme.error),
        ),
        title: Text(
          user['displayName'] ?? 'User',
          style: theme.bodyLarge.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Blocked ${user['blockedAt'] ?? 'recently'}',
          style: theme.bodySmall.copyWith(color: theme.secondaryText),
        ),
        trailing: TextButton(
          onPressed: () => _unblockUser(user),
          child: Text(
            'Unblock',
            style: theme.bodyMedium.copyWith(
              color: theme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  void _showAddBlockedUser(BuildContext context) {
    // Show dialog to search and block a user
    final theme = FlutterFlowTheme.of(context);
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Block User', style: theme.titleLarge),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'Search by name or username',
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
              // Search and show results
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

  void _unblockUser(Map<String, dynamic> user) {
    // Unblock user from pulse
  }
}

/// Dialog for pulse chat settings
class PulseChatSettingsDialog extends StatefulWidget {
  final String pulseId;

  const PulseChatSettingsDialog({super.key, required this.pulseId});

  @override
  State<PulseChatSettingsDialog> createState() =>
      _PulseChatSettingsDialogState();
}

class _PulseChatSettingsDialogState extends State<PulseChatSettingsDialog> {
  bool _chatEnabled = true;
  bool _slowMode = false;
  int _slowModeDelay = 5;
  bool _autoModeration = true;
  bool _linksAllowed = true;
  bool _mediaAllowed = true;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Chat Settings',
                  style: theme.titleLarge.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Chat Enabled
            SwitchListTile(
              title: Text('Enable Chat', style: theme.bodyLarge),
              subtitle: Text(
                'Allow attendees to chat',
                style: theme.bodySmall.copyWith(color: theme.secondaryText),
              ),
              value: _chatEnabled,
              onChanged: (v) => setState(() => _chatEnabled = v),
              activeColor: theme.primary,
              contentPadding: EdgeInsets.zero,
            ),

            // Slow Mode
            SwitchListTile(
              title: Text('Slow Mode', style: theme.bodyLarge),
              subtitle: Text(
                'Limit message frequency',
                style: theme.bodySmall.copyWith(color: theme.secondaryText),
              ),
              value: _slowMode,
              onChanged:
                  _chatEnabled ? (v) => setState(() => _slowMode = v) : null,
              activeColor: theme.primary,
              contentPadding: EdgeInsets.zero,
            ),

            if (_slowMode)
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 8),
                child: Row(
                  children: [
                    Text('Delay: ', style: theme.bodyMedium),
                    DropdownButton<int>(
                      value: _slowModeDelay,
                      items: [5, 10, 15, 30, 60].map((seconds) {
                        return DropdownMenuItem(
                          value: seconds,
                          child: Text('$seconds seconds'),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _slowModeDelay = v!),
                    ),
                  ],
                ),
              ),

            // Auto Moderation
            SwitchListTile(
              title: Text('Auto Moderation', style: theme.bodyLarge),
              subtitle: Text(
                'Automatically filter inappropriate content',
                style: theme.bodySmall.copyWith(color: theme.secondaryText),
              ),
              value: _autoModeration,
              onChanged: _chatEnabled
                  ? (v) => setState(() => _autoModeration = v)
                  : null,
              activeColor: theme.primary,
              contentPadding: EdgeInsets.zero,
            ),

            // Links Allowed
            SwitchListTile(
              title: Text('Allow Links', style: theme.bodyLarge),
              subtitle: Text(
                'Let users share links in chat',
                style: theme.bodySmall.copyWith(color: theme.secondaryText),
              ),
              value: _linksAllowed,
              onChanged: _chatEnabled
                  ? (v) => setState(() => _linksAllowed = v)
                  : null,
              activeColor: theme.primary,
              contentPadding: EdgeInsets.zero,
            ),

            // Media Allowed
            SwitchListTile(
              title: Text('Allow Media', style: theme.bodyLarge),
              subtitle: Text(
                'Let users share images and files',
                style: theme.bodySmall.copyWith(color: theme.secondaryText),
              ),
              value: _mediaAllowed,
              onChanged: _chatEnabled
                  ? (v) => setState(() => _mediaAllowed = v)
                  : null,
              activeColor: theme.primary,
              contentPadding: EdgeInsets.zero,
            ),

            const SizedBox(height: 24),

            // Save Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Save Settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveSettings() {
    // Save settings to API
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Chat settings saved')),
    );
  }
}
