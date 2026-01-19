import 'package:flutter/material.dart';
import '../../services/moderation_service.dart';
import '../../flutter_flow/flutter_flow_theme.dart';

/// User actions menu (block, mute, report)
class UserActionsSheet extends StatefulWidget {
  final String userId;
  final String? userName;
  final String? userImageUrl;
  final VoidCallback? onBlock;
  final VoidCallback? onMute;
  final VoidCallback? onReport;

  const UserActionsSheet({
    super.key,
    required this.userId,
    this.userName,
    this.userImageUrl,
    this.onBlock,
    this.onMute,
    this.onReport,
  });

  @override
  State<UserActionsSheet> createState() => _UserActionsSheetState();

  /// Show the user actions sheet
  static Future<String?> show(
    BuildContext context, {
    required String userId,
    String? userName,
    String? userImageUrl,
    VoidCallback? onBlock,
    VoidCallback? onMute,
    VoidCallback? onReport,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => UserActionsSheet(
        userId: userId,
        userName: userName,
        userImageUrl: userImageUrl,
        onBlock: onBlock,
        onMute: onMute,
        onReport: onReport,
      ),
    );
  }
}

class _UserActionsSheetState extends State<UserActionsSheet> {
  final ModerationService _moderationService = ModerationService.instance;
  bool _isLoading = true;
  BlockStatus? _blockStatus;

  @override
  void initState() {
    super.initState();
    _loadBlockStatus();
  }

  Future<void> _loadBlockStatus() async {
    final status = await _moderationService.isUserBlocked(widget.userId);
    if (mounted) {
      setState(() {
        _blockStatus = status;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
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
            // User info
            if (widget.userName != null || widget.userImageUrl != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    if (widget.userImageUrl != null)
                      CircleAvatar(
                        radius: 24,
                        backgroundImage: NetworkImage(widget.userImageUrl!),
                        onBackgroundImageError: (_, __) {},
                      )
                    else
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: theme.primary.withOpacity(0.2),
                        child: Icon(
                          Icons.person_outline_rounded,
                          color: theme.primary,
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.userName ?? 'User',
                        style: theme.titleMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),
            // Actions
            if (_isLoading)
              Padding(
                padding: const EdgeInsets.all(32),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(theme.primary),
                ),
              )
            else ...[
              // Mute option
              _buildActionTile(
                icon: Icons.volume_off_rounded,
                title: 'Mute',
                subtitle: 'Hide their posts and messages from your feed',
                onTap: () => _showMuteOptions(),
              ),
              // Block/Unblock option
              _buildActionTile(
                icon: _blockStatus?.blockedByMe == true
                    ? Icons.lock_open_rounded
                    : Icons.block_rounded,
                title: _blockStatus?.blockedByMe == true ? 'Unblock' : 'Block',
                subtitle: _blockStatus?.blockedByMe == true
                    ? 'Allow this user to interact with you again'
                    : 'Prevent this user from contacting you or seeing your content',
                isDestructive: _blockStatus?.blockedByMe != true,
                onTap: () => _handleBlockAction(),
              ),
              // Report option
              _buildActionTile(
                icon: Icons.flag_rounded,
                title: 'Report',
                subtitle: 'Report this user for violating our guidelines',
                isDestructive: true,
                onTap: () {
                  Navigator.pop(context, 'report');
                  widget.onReport?.call();
                },
              ),
            ],
            const SizedBox(height: 8),
            // Cancel button
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    backgroundColor: theme.primaryBackground,
                  ),
                  child: Text(
                    'Cancel',
                    style: theme.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final theme = FlutterFlowTheme.of(context);

    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDestructive
              ? theme.error.withOpacity(0.1)
              : theme.primaryBackground,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: isDestructive ? theme.error : theme.primaryText,
          size: 24,
        ),
      ),
      title: Text(
        title,
        style: theme.bodyLarge.copyWith(
          fontWeight: FontWeight.w600,
          color: isDestructive ? theme.error : theme.primaryText,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.bodySmall.copyWith(
          color: theme.secondaryText,
        ),
      ),
    );
  }

  Future<void> _showMuteOptions() async {
    final result = await showModalBottomSheet<Map<String, bool>>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => MuteOptionsSheet(userName: widget.userName),
    );

    if (result != null && mounted) {
      final success = await _moderationService.muteUser(
        widget.userId,
        muteMessages: result['messages'] ?? true,
        mutePulses: result['pulses'] ?? true,
        mutePosts: result['posts'] ?? true,
      );

      if (mounted) {
        Navigator.pop(context, 'mute');
        widget.onMute?.call();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? '${widget.userName ?? 'User'} has been muted'
                  : 'Failed to mute user',
            ),
            backgroundColor: success
                ? FlutterFlowTheme.of(context).success
                : FlutterFlowTheme.of(context).error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleBlockAction() async {
    final isBlocked = _blockStatus?.blockedByMe == true;
    final theme = FlutterFlowTheme.of(context);

    if (!isBlocked) {
      // Confirm block
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Block ${widget.userName ?? 'this user'}?',
            style: theme.titleLarge,
          ),
          content: Text(
            'They won\'t be able to find your profile, Pulses, or send you messages. They won\'t be notified that you blocked them.',
            style: theme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: theme.bodyLarge.copyWith(
                  color: theme.secondaryText,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                'Block',
                style: theme.bodyLarge.copyWith(
                  color: theme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );

      if (confirm != true || !mounted) return;
    }

    setState(() => _isLoading = true);

    final success = isBlocked
        ? await _moderationService.unblockUser(widget.userId)
        : await _moderationService.blockUser(widget.userId);

    if (mounted) {
      Navigator.pop(context, isBlocked ? 'unblock' : 'block');
      widget.onBlock?.call();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? (isBlocked
                    ? '${widget.userName ?? 'User'} has been unblocked'
                    : '${widget.userName ?? 'User'} has been blocked')
                : 'Action failed. Please try again.',
          ),
          backgroundColor: success ? theme.success : theme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    }
  }
}

/// Mute options sheet
class MuteOptionsSheet extends StatefulWidget {
  final String? userName;

  const MuteOptionsSheet({super.key, this.userName});

  @override
  State<MuteOptionsSheet> createState() => _MuteOptionsSheetState();
}

class _MuteOptionsSheetState extends State<MuteOptionsSheet> {
  bool _muteMessages = true;
  bool _mutePulses = true;
  bool _mutePosts = true;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
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
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mute ${widget.userName ?? 'this user'}',
                    style: theme.titleLarge.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose what content to hide. They won\'t know you muted them.',
                    style: theme.bodyMedium.copyWith(
                      color: theme.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            SwitchListTile(
              value: _muteMessages,
              onChanged: (v) => setState(() => _muteMessages = v),
              title: Text('Messages', style: theme.bodyLarge),
              subtitle: Text(
                'Hide their messages in conversations',
                style: theme.bodySmall.copyWith(color: theme.secondaryText),
              ),
              activeColor: theme.primary,
            ),
            SwitchListTile(
              value: _mutePulses,
              onChanged: (v) => setState(() => _mutePulses = v),
              title: Text('Pulses', style: theme.bodyLarge),
              subtitle: Text(
                'Hide their Pulses from your feed and map',
                style: theme.bodySmall.copyWith(color: theme.secondaryText),
              ),
              activeColor: theme.primary,
            ),
            SwitchListTile(
              value: _mutePosts,
              onChanged: (v) => setState(() => _mutePosts = v),
              title: Text('Posts', style: theme.bodyLarge),
              subtitle: Text(
                'Hide their posts from your feed',
                style: theme.bodySmall.copyWith(color: theme.secondaryText),
              ),
              activeColor: theme.primary,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: theme.alternate),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: theme.bodyLarge.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context, {
                          'messages': _muteMessages,
                          'pulses': _mutePulses,
                          'posts': _mutePosts,
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Mute',
                        style: theme.bodyLarge.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
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
}
