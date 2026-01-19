import 'package:flutter/material.dart';
import '../../services/moderation_service.dart';
import '../../flutter_flow/flutter_flow_theme.dart';

/// Page to manage blocked and muted users
class BlockedMutedUsersPage extends StatefulWidget {
  const BlockedMutedUsersPage({super.key});

  @override
  State<BlockedMutedUsersPage> createState() => _BlockedMutedUsersPageState();
}

class _BlockedMutedUsersPageState extends State<BlockedMutedUsersPage>
    with SingleTickerProviderStateMixin {
  final ModerationService _moderationService = ModerationService.instance;
  late TabController _tabController;

  List<BlockedUser> _blockedUsers = [];
  List<MutedUser> _mutedUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _moderationService.getBlockedUsers(forceRefresh: true),
        _moderationService.getMutedUsers(forceRefresh: true),
      ]);

      if (mounted) {
        setState(() {
          _blockedUsers = results[0] as List<BlockedUser>;
          _mutedUsers = results[1] as List<MutedUser>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
          'Blocked & Muted',
          style: theme.headlineSmall.copyWith(fontWeight: FontWeight.w600),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.primary,
          unselectedLabelColor: theme.secondaryText,
          indicatorColor: theme.primary,
          indicatorWeight: 3,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.block_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text('Blocked (${_blockedUsers.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.volume_off_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text('Muted (${_mutedUsers.length})'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(theme.primary),
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildBlockedList(),
                _buildMutedList(),
              ],
            ),
    );
  }

  Widget _buildBlockedList() {
    final theme = FlutterFlowTheme.of(context);

    if (_blockedUsers.isEmpty) {
      return _buildEmptyState(
        icon: Icons.block_rounded,
        title: 'No blocked users',
        subtitle:
            'Users you block won\'t be able to see your profile or contact you.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: theme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _blockedUsers.length,
        itemBuilder: (context, index) {
          final user = _blockedUsers[index];
          return _buildUserTile(
            user: user,
            isBlocked: true,
            onAction: () => _unblockUser(user),
          );
        },
      ),
    );
  }

  Widget _buildMutedList() {
    final theme = FlutterFlowTheme.of(context);

    if (_mutedUsers.isEmpty) {
      return _buildEmptyState(
        icon: Icons.volume_off_rounded,
        title: 'No muted users',
        subtitle:
            'When you mute someone, their content won\'t appear in your feed.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: theme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _mutedUsers.length,
        itemBuilder: (context, index) {
          final user = _mutedUsers[index];
          return _buildMutedUserTile(user);
        },
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final theme = FlutterFlowTheme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.alternate.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 48,
                color: theme.secondaryText,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: theme.titleLarge.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.bodyMedium.copyWith(color: theme.secondaryText),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserTile({
    required BlockedUser user,
    required bool isBlocked,
    required VoidCallback onAction,
  }) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundImage: user.profileImageUrl != null
              ? NetworkImage(user.profileImageUrl!)
              : null,
          backgroundColor: theme.primary.withOpacity(0.2),
          child: user.profileImageUrl == null
              ? Icon(Icons.person_outline_rounded, color: theme.primary)
              : null,
        ),
        title: Text(
          user.displayName ?? 'User',
          style: theme.bodyLarge.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Blocked ${_formatDate(user.blockedAt)}',
          style: theme.bodySmall.copyWith(color: theme.secondaryText),
        ),
        trailing: OutlinedButton(
          onPressed: onAction,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            side: BorderSide(color: theme.primary),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: Text(
            'Unblock',
            style: theme.bodySmall.copyWith(
              color: theme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMutedUserTile(MutedUser user) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundImage: user.profileImageUrl != null
              ? NetworkImage(user.profileImageUrl!)
              : null,
          backgroundColor: theme.primary.withOpacity(0.2),
          child: user.profileImageUrl == null
              ? Icon(Icons.person_outline_rounded, color: theme.primary)
              : null,
        ),
        title: Text(
          user.displayName ?? 'User',
          style: theme.bodyLarge.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Muted ${_formatDate(user.mutedAt)}',
          style: theme.bodySmall.copyWith(color: theme.secondaryText),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Muted content:',
                  style: theme.bodySmall.copyWith(
                    color: theme.secondaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    if (user.muteMessages) _buildMuteChip('Messages', theme),
                    if (user.mutePulses) _buildMuteChip('Pulses', theme),
                    if (user.mutePosts) _buildMuteChip('Posts', theme),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _unmuteUser(user),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: theme.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Unmute',
                      style: theme.bodyMedium.copyWith(
                        color: theme.primary,
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
    );
  }

  Widget _buildMuteChip(String label, FlutterFlowTheme theme) {
    return Chip(
      label: Text(label),
      labelStyle: theme.bodySmall.copyWith(
        color: theme.secondaryText,
      ),
      backgroundColor: theme.primaryBackground,
      side: BorderSide(color: theme.alternate),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'today';
    } else if (diff.inDays == 1) {
      return 'yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else if (diff.inDays < 30) {
      final weeks = (diff.inDays / 7).floor();
      return '$weeks ${weeks == 1 ? 'week' : 'weeks'} ago';
    } else {
      final months = (diff.inDays / 30).floor();
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    }
  }

  Future<void> _unblockUser(BlockedUser user) async {
    final theme = FlutterFlowTheme.of(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text('Unblock ${user.displayName}?', style: theme.titleLarge),
        content: Text(
          'They will be able to see your profile and contact you again.',
          style: theme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: theme.bodyLarge),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Unblock',
              style: theme.bodyLarge.copyWith(
                color: theme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final success = await _moderationService.unblockUser(user.id);

    if (mounted) {
      if (success) {
        setState(() {
          _blockedUsers.removeWhere((u) => u.id == user.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user.displayName} has been unblocked'),
            backgroundColor: theme.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to unblock user'),
            backgroundColor: theme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }

  Future<void> _unmuteUser(MutedUser user) async {
    final theme = FlutterFlowTheme.of(context);
    final success = await _moderationService.unmuteUser(user.id);

    if (mounted) {
      if (success) {
        setState(() {
          _mutedUsers.removeWhere((u) => u.id == user.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user.displayName} has been unmuted'),
            backgroundColor: theme.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to unmute user'),
            backgroundColor: theme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }
}
