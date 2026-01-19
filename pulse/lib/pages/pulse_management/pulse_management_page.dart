import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '/backend/api_service.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/utils/performance_utils.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Pulse Management Page - Admin panel for pulse creators and admins
/// Allows managing members, roles, settings, and pulse lifecycle
class PulseManagementPage extends StatefulWidget {
  const PulseManagementPage({
    super.key,
    required this.pulseId,
    this.pulseName,
  });

  final String pulseId;
  final String? pulseName;

  static String routeName = 'PulseManagement';
  static String routePath = '/pulse/:id/manage';

  @override
  State<PulseManagementPage> createState() => _PulseManagementPageState();
}

class _PulseManagementPageState extends State<PulseManagementPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isLoading = true;
  String? _error;

  // Current user info
  Map<String, dynamic>? _currentUser;

  // Members data
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _bannedMembers = [];

  // Pulse settings
  bool _allowGuestInvites = true;
  bool _requireApproval = false;

  // Precomputed role colors for performance
  static const Map<String, Color> _roleColors = {
    'OWNER': Colors.amber,
    'ADMIN': Colors.blue,
    'MODERATOR': Colors.green,
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load members
      final membersResult =
          await ApiService.instance.getPulseMembers(widget.pulseId);

      if (membersResult != null) {
        _currentUser = membersResult['currentUser'] as Map<String, dynamic>?;
        _members =
            List<Map<String, dynamic>>.from(membersResult['members'] ?? []);
      }

      // Load banned members if admin
      if (_currentUser?['permissions']?['canRemove'] == true) {
        final bannedResult =
            await ApiService.instance.getBannedMembers(widget.pulseId);
        if (bannedResult != null) {
          _bannedMembers = List<Map<String, dynamic>>.from(
              bannedResult['bannedMembers'] ?? []);
        }
      }

      // Load pulse for settings
      final pulseData = await ApiService.instance.getPulseById(widget.pulseId);
      if (pulseData != null) {
        _allowGuestInvites = pulseData['allowGuestInvites'] ?? true;
        _requireApproval = pulseData['requireApproval'] ?? false;
      }
    } catch (e) {
      _error = 'Failed to load pulse management data';
      print('Error loading pulse management: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        elevation: 0,
        leading: FlutterFlowIconButton(
          borderColor: Colors.transparent,
          borderRadius: 30,
          buttonSize: 44,
          icon: Icon(
            Icons.arrow_back_rounded,
            color: theme.primaryText,
            size: 24,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.pulseName ?? 'Manage Pulse',
          style: theme.headlineSmall.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.primary,
          unselectedLabelColor: theme.secondaryText,
          indicatorColor: theme.primary,
          tabs: const [
            Tab(text: 'Members', icon: Icon(Icons.people)),
            Tab(text: 'Roles', icon: Icon(Icons.admin_panel_settings)),
            Tab(text: 'Settings', icon: Icon(Icons.settings)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState(theme)
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildMembersTab(theme),
                    _buildRolesTab(theme),
                    _buildSettingsTab(theme),
                  ],
                ),
    );
  }

  Widget _buildErrorState(FlutterFlowTheme theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: theme.error),
          const SizedBox(height: 16),
          Text(
            _error ?? 'Something went wrong',
            style: theme.bodyLarge.copyWith(color: theme.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FFButtonWidget(
            onPressed: _loadData,
            text: 'Retry',
            options: FFButtonOptions(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              color: theme.primary,
              textStyle: theme.titleSmall.copyWith(color: Colors.white),
              borderRadius: BorderRadius.circular(22),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // MEMBERS TAB
  // ============================================================================

  Widget _buildMembersTab(FlutterFlowTheme theme) {
    final currentUserPermissions = _currentUser?['permissions'] ?? {};
    final canRemove = currentUserPermissions['canRemove'] == true;

    // Precompute total item count for better list performance
    final showBanned = canRemove && _bannedMembers.isNotEmpty;
    final totalItems =
        1 + _members.length + (showBanned ? 2 + _bannedMembers.length : 0);

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: totalItems,
        cacheExtent: 300, // Pre-render items for smoother scrolling
        itemBuilder: (context, index) {
          // Member count header
          if (index == 0) {
            return _buildMemberCountHeader(theme);
          }

          // Members list
          final memberIndex = index - 1;
          if (memberIndex < _members.length) {
            return RepaintBoundary(
              child: _buildMemberCard(theme, _members[memberIndex], canRemove),
            );
          }

          // Banned section header
          final bannedOffset = _members.length + 1;
          if (showBanned && index == bannedOffset) {
            return Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(
                'Banned Members',
                style: theme.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.error,
                ),
              ),
            );
          }

          // Spacing after banned header
          if (showBanned && index == bannedOffset + 1) {
            return const SizedBox(height: 8);
          }

          // Banned members
          final bannedIndex = index - bannedOffset - 2;
          if (showBanned &&
              bannedIndex >= 0 &&
              bannedIndex < _bannedMembers.length) {
            return RepaintBoundary(
              child: _buildBannedMemberCard(theme, _bannedMembers[bannedIndex]),
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildMemberCountHeader(FlutterFlowTheme theme) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.secondaryBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.people, color: theme.primary),
              const SizedBox(width: 12),
              Text(
                '${_members.length} Members',
                style: theme.titleMedium.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (_currentUser != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getRoleColorFast(_currentUser!['role'])
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _currentUser!['role'] ?? 'MEMBER',
                    style: theme.bodySmall.copyWith(
                      color: _getRoleColorFast(_currentUser!['role']),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // Fast role color lookup using precomputed map
  Color _getRoleColorFast(String? role) {
    return _roleColors[role] ?? Colors.grey;
  }

  Widget _buildMemberCard(
      FlutterFlowTheme theme, Map<String, dynamic> member, bool canManage) {
    final user = member['user'] as Map<String, dynamic>?;
    final role = member['role'] as String? ?? 'MEMBER';
    final isCurrentUser = member['userId'] == _currentUser?['userId'];
    final isMuted = member['isMuted'] == true;
    final roleColor = _getRoleColorFast(role);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
        border:
            isCurrentUser ? Border.all(color: theme.primary, width: 2) : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _MemberAvatar(
          imageUrl: user?['profileImageUrl'],
          isMuted: isMuted,
          theme: theme,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                user?['displayName'] ?? 'Unknown User',
                style: theme.bodyLarge.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: roleColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                role,
                style: theme.bodySmall.copyWith(
                  color: roleColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          user?['email'] ?? '',
          style: theme.bodySmall.copyWith(color: theme.secondaryText),
        ),
        trailing: canManage && !isCurrentUser && role != 'OWNER'
            ? PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: theme.secondaryText),
                onSelected: (action) => _handleMemberAction(action, member),
                itemBuilder: (context) => [
                  if (_currentUser?['permissions']?['canChangeRoles'] == true)
                    const PopupMenuItem(
                      value: 'change_role',
                      child: ListTile(
                        leading: Icon(Icons.admin_panel_settings),
                        title: Text('Change Role'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  PopupMenuItem(
                    value: isMuted ? 'unmute' : 'mute',
                    child: ListTile(
                      leading:
                          Icon(isMuted ? Icons.volume_up : Icons.volume_off),
                      title: Text(isMuted ? 'Unmute' : 'Mute'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'remove',
                    child: ListTile(
                      leading: Icon(Icons.person_remove, color: Colors.orange),
                      title: Text('Remove',
                          style: TextStyle(color: Colors.orange)),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'ban',
                    child: ListTile(
                      leading: Icon(Icons.block, color: Colors.red),
                      title: Text('Ban', style: TextStyle(color: Colors.red)),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Widget _buildBannedMemberCard(
      FlutterFlowTheme theme, Map<String, dynamic> member) {
    final user = member['user'] as Map<String, dynamic>?;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.error.withOpacity(0.3)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: theme.error.withOpacity(0.2),
          backgroundImage: user?['profileImageUrl'] != null
              ? NetworkImage(user!['profileImageUrl'])
              : null,
          child: user?['profileImageUrl'] == null
              ? Icon(Icons.person, color: theme.error)
              : null,
        ),
        title: Text(
          user?['displayName'] ?? 'Unknown User',
          style: theme.bodyMedium.copyWith(
            decoration: TextDecoration.lineThrough,
            color: theme.secondaryText,
          ),
        ),
        subtitle: member['bannedReason'] != null
            ? Text(
                'Reason: ${member['bannedReason']}',
                style: theme.bodySmall.copyWith(color: theme.error),
              )
            : null,
        trailing: TextButton(
          onPressed: () => _unbanMember(member['userId']),
          child: Text('Unban', style: TextStyle(color: theme.primary)),
        ),
      ),
    );
  }

  // ============================================================================
  // ROLES TAB
  // ============================================================================

  Widget _buildRolesTab(FlutterFlowTheme theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildRoleInfoCard(
          theme,
          'OWNER',
          'Full control over the pulse',
          [
            'Edit pulse details',
            'Manage all members',
            'Change roles',
            'Delete pulse',
            'Transfer ownership',
          ],
          Icons.star,
          Colors.amber,
        ),
        const SizedBox(height: 12),
        _buildRoleInfoCard(
          theme,
          'ADMIN',
          'Co-organizer with management powers',
          [
            'Edit pulse details',
            'Add/remove members',
            'Promote to Moderator',
            'Manage settings',
          ],
          Icons.verified_user,
          Colors.blue,
        ),
        const SizedBox(height: 12),
        _buildRoleInfoCard(
          theme,
          'MODERATOR',
          'Can manage chat and content',
          [
            'Mute/unmute members',
            'Delete messages',
            'Pin messages',
            'Manage highlights',
          ],
          Icons.shield,
          Colors.green,
        ),
        const SizedBox(height: 12),
        _buildRoleInfoCard(
          theme,
          'MEMBER',
          'Regular participant',
          [
            'Join group chat',
            'Create highlights',
            'Invite others (if allowed)',
          ],
          Icons.person,
          theme.secondaryText,
        ),
        const SizedBox(height: 24),

        // Role assignment section
        if (_currentUser?['permissions']?['canChangeRoles'] == true) ...[
          Text(
            'Assign Roles',
            style: theme.titleMedium.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap a member below to change their role',
            style: theme.bodySmall.copyWith(color: theme.secondaryText),
          ),
          const SizedBox(height: 16),
          ..._members
              .where((m) =>
                  m['role'] != 'OWNER' &&
                  m['userId'] != _currentUser?['userId'])
              .map((member) => _buildRoleAssignmentCard(theme, member)),
        ],
      ],
    );
  }

  Widget _buildRoleInfoCard(
    FlutterFlowTheme theme,
    String role,
    String description,
    List<String> permissions,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
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
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      role,
                      style: theme.titleSmall.copyWith(
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    Text(
                      description,
                      style:
                          theme.bodySmall.copyWith(color: theme.secondaryText),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...permissions.map((p) => Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: Row(
                  children: [
                    Icon(Icons.check, size: 16, color: color),
                    const SizedBox(width: 8),
                    Text(p, style: theme.bodySmall),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildRoleAssignmentCard(
      FlutterFlowTheme theme, Map<String, dynamic> member) {
    final user = member['user'] as Map<String, dynamic>?;
    final role = member['role'] as String? ?? 'MEMBER';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage: user?['profileImageUrl'] != null
              ? NetworkImage(user!['profileImageUrl'])
              : null,
          child: user?['profileImageUrl'] == null ? Icon(Icons.person) : null,
        ),
        title: Text(user?['displayName'] ?? 'Unknown'),
        subtitle: Text('Current role: $role'),
        trailing: DropdownButton<String>(
          value: role,
          underline: const SizedBox(),
          items: const [
            DropdownMenuItem(value: 'ADMIN', child: Text('Admin')),
            DropdownMenuItem(value: 'MODERATOR', child: Text('Moderator')),
            DropdownMenuItem(value: 'MEMBER', child: Text('Member')),
          ],
          onChanged: (newRole) {
            if (newRole != null && newRole != role) {
              _changeRole(member['userId'], newRole);
            }
          },
        ),
      ),
    );
  }

  // ============================================================================
  // SETTINGS TAB
  // ============================================================================

  Widget _buildSettingsTab(FlutterFlowTheme theme) {
    final canEdit = _currentUser?['permissions']?['canEdit'] == true;
    final isOwner = _currentUser?['role'] == 'OWNER';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Permissions section
        _buildSettingsSection(
          theme,
          'Permissions',
          Icons.security,
          [
            _buildSwitchTile(
              theme,
              'Allow guest invites',
              'Members can invite others to join',
              _allowGuestInvites,
              canEdit
                  ? (value) => _updateSetting('allowGuestInvites', value)
                  : null,
            ),
            _buildSwitchTile(
              theme,
              'Require approval',
              'New members need admin approval to join',
              _requireApproval,
              canEdit
                  ? (value) => _updateSetting('requireApproval', value)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Danger zone (owner only)
        if (isOwner) ...[
          _buildSettingsSection(
            theme,
            'Danger Zone',
            Icons.warning,
            [
              _buildActionTile(
                theme,
                'Transfer Ownership',
                'Make another admin the owner',
                Icons.swap_horiz,
                Colors.orange,
                _showTransferOwnershipDialog,
              ),
              _buildActionTile(
                theme,
                'Archive Pulse',
                'Hide pulse from listings',
                Icons.archive,
                Colors.orange,
                _archivePulse,
              ),
              _buildActionTile(
                theme,
                'Delete Pulse',
                'Permanently delete this pulse',
                Icons.delete_forever,
                theme.error,
                _showDeleteConfirmation,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSettingsSection(
    FlutterFlowTheme theme,
    String title,
    IconData icon,
    List<Widget> children,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: theme.primary),
                const SizedBox(width: 12),
                Text(
                  title,
                  style:
                      theme.titleMedium.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSwitchTile(
    FlutterFlowTheme theme,
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool>? onChanged,
  ) {
    return SwitchListTile(
      title: Text(title, style: theme.bodyLarge),
      subtitle: Text(subtitle,
          style: theme.bodySmall.copyWith(color: theme.secondaryText)),
      value: value,
      onChanged: onChanged,
      activeColor: theme.primary,
    );
  }

  Widget _buildActionTile(
    FlutterFlowTheme theme,
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: theme.bodyLarge.copyWith(color: color)),
      subtitle: Text(subtitle,
          style: theme.bodySmall.copyWith(color: theme.secondaryText)),
      trailing: Icon(Icons.chevron_right, color: theme.secondaryText),
      onTap: onTap,
    );
  }

  // ============================================================================
  // ACTIONS
  // ============================================================================

  void _handleMemberAction(String action, Map<String, dynamic> member) {
    final userId = member['userId'] as String;

    switch (action) {
      case 'change_role':
        _showChangeRoleDialog(member);
        break;
      case 'mute':
        _muteMember(userId);
        break;
      case 'unmute':
        _unmuteMember(userId);
        break;
      case 'remove':
        _showRemoveConfirmation(member);
        break;
      case 'ban':
        _showBanConfirmation(member);
        break;
    }
  }

  void _showChangeRoleDialog(Map<String, dynamic> member) {
    final user = member['user'] as Map<String, dynamic>?;
    String selectedRole = member['role'] ?? 'MEMBER';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Change Role'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Select new role for ${user?['displayName'] ?? 'this user'}:'),
            const SizedBox(height: 16),
            StatefulBuilder(
              builder: (context, setDialogState) => Column(
                children: [
                  RadioListTile<String>(
                    title: const Text('Admin'),
                    subtitle: const Text('Can manage members and settings'),
                    value: 'ADMIN',
                    groupValue: selectedRole,
                    onChanged: (value) =>
                        setDialogState(() => selectedRole = value!),
                  ),
                  RadioListTile<String>(
                    title: const Text('Moderator'),
                    subtitle: const Text('Can manage chat'),
                    value: 'MODERATOR',
                    groupValue: selectedRole,
                    onChanged: (value) =>
                        setDialogState(() => selectedRole = value!),
                  ),
                  RadioListTile<String>(
                    title: const Text('Member'),
                    subtitle: const Text('Regular participant'),
                    value: 'MEMBER',
                    groupValue: selectedRole,
                    onChanged: (value) =>
                        setDialogState(() => selectedRole = value!),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _changeRole(member['userId'], selectedRole);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _changeRole(String userId, String newRole) async {
    HapticFeedback.lightImpact();

    final result = await ApiService.instance.updateMemberRole(
      pulseId: widget.pulseId,
      userId: userId,
      role: newRole,
    );

    if (result?['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Role updated to $newRole')),
      );
      _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result?['error'] ?? 'Failed to update role'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _muteMember(String userId) async {
    final result = await ApiService.instance.mutePulseMember(
      pulseId: widget.pulseId,
      userId: userId,
    );

    if (result?['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Member muted')),
      );
      _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result?['error'] ?? 'Failed to mute member'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _unmuteMember(String userId) async {
    final result = await ApiService.instance.unmutePulseMember(
      pulseId: widget.pulseId,
      userId: userId,
    );

    if (result?['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Member unmuted')),
      );
      _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result?['error'] ?? 'Failed to unmute member'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showRemoveConfirmation(Map<String, dynamic> member) {
    final user = member['user'] as Map<String, dynamic>?;
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Remove ${user?['displayName'] ?? 'this user'} from the pulse?'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () {
              Navigator.pop(context);
              _removeMember(member['userId'], controller.text);
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Future<void> _removeMember(String userId, String? reason) async {
    final result = await ApiService.instance.removePulseMember(
      pulseId: widget.pulseId,
      userId: userId,
      reason: reason?.isNotEmpty == true ? reason : null,
    );

    if (result?['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Member removed')),
      );
      _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result?['error'] ?? 'Failed to remove member'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showBanConfirmation(Map<String, dynamic> member) {
    final user = member['user'] as Map<String, dynamic>?;
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ban Member'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ban ${user?['displayName'] ?? 'this user'} from the pulse?',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'This will remove them and prevent them from rejoining.',
              style: TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _banMember(member['userId'], controller.text);
            },
            child: const Text('Ban'),
          ),
        ],
      ),
    );
  }

  Future<void> _banMember(String userId, String? reason) async {
    final result = await ApiService.instance.banPulseMember(
      pulseId: widget.pulseId,
      userId: userId,
      reason: reason?.isNotEmpty == true ? reason : null,
    );

    if (result?['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Member banned')),
      );
      _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result?['error'] ?? 'Failed to ban member'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _unbanMember(String userId) async {
    final result = await ApiService.instance.unbanPulseMember(
      pulseId: widget.pulseId,
      userId: userId,
    );

    if (result?['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Member unbanned')),
      );
      _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result?['error'] ?? 'Failed to unban member'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _updateSetting(String setting, bool value) async {
    setState(() {
      if (setting == 'allowGuestInvites') _allowGuestInvites = value;
      if (setting == 'requireApproval') _requireApproval = value;
    });

    final result = await ApiService.instance.updatePulseSettings(
      pulseId: widget.pulseId,
      allowGuestInvites: setting == 'allowGuestInvites' ? value : null,
      requireApproval: setting == 'requireApproval' ? value : null,
    );

    if (result?['success'] != true) {
      // Revert on failure
      setState(() {
        if (setting == 'allowGuestInvites') _allowGuestInvites = !value;
        if (setting == 'requireApproval') _requireApproval = !value;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result?['error'] ?? 'Failed to update setting'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showTransferOwnershipDialog() {
    final admins = _members.where((m) => m['role'] == 'ADMIN').toList();

    if (admins.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No admins available. Promote someone to Admin first.'),
        ),
      );
      return;
    }

    String? selectedUserId;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transfer Ownership'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select an admin to become the new owner:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'You will become an admin after transfer.',
              style: TextStyle(color: Colors.orange),
            ),
            const SizedBox(height: 16),
            StatefulBuilder(
              builder: (context, setDialogState) => Column(
                children: admins.map((admin) {
                  final user = admin['user'] as Map<String, dynamic>?;
                  return RadioListTile<String>(
                    title: Text(user?['displayName'] ?? 'Unknown'),
                    value: admin['userId'] as String,
                    groupValue: selectedUserId,
                    onChanged: (value) =>
                        setDialogState(() => selectedUserId = value),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: selectedUserId != null
                ? () {
                    Navigator.pop(context);
                    _transferOwnership(selectedUserId!);
                  }
                : null,
            child: const Text('Transfer'),
          ),
        ],
      ),
    );
  }

  Future<void> _transferOwnership(String newOwnerId) async {
    final result = await ApiService.instance.transferPulseOwnership(
      pulseId: widget.pulseId,
      newOwnerId: newOwnerId,
    );

    if (result?['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ownership transferred')),
      );
      _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result?['error'] ?? 'Failed to transfer ownership'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _archivePulse() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive Pulse'),
        content: const Text(
            'Archive this pulse? It will be hidden from listings but can be restored.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final result = await ApiService.instance.archivePulse(widget.pulseId);
      if (result?['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pulse archived')),
        );
        Navigator.pop(context, {'archived': true});
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result?['error'] ?? 'Failed to archive pulse'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Pulse'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to permanently delete this pulse?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'This action cannot be undone. All members will be removed and all data will be lost.',
              style: TextStyle(color: Colors.red),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _deletePulse();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePulse() async {
    final result = await ApiService.instance.deletePulse(widget.pulseId);
    if (result?['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pulse deleted')),
      );
      // Pop back to home
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result?['error'] ?? 'Failed to delete pulse'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Color _getRoleColor(String? role, FlutterFlowTheme theme) {
    switch (role) {
      case 'OWNER':
        return Colors.amber;
      case 'ADMIN':
        return Colors.blue;
      case 'MODERATOR':
        return Colors.green;
      default:
        return theme.secondaryText;
    }
  }
}

/// Optimized member avatar widget with caching
class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({
    required this.imageUrl,
    required this.isMuted,
    required this.theme,
  });

  final String? imageUrl;
  final bool isMuted;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: theme.alternate,
          child: imageUrl != null
              ? ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: imageUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    memCacheWidth: 96,
                    memCacheHeight: 96,
                    placeholder: (context, url) => Icon(
                      Icons.person,
                      color: theme.primaryText,
                    ),
                    errorWidget: (context, url, error) => Icon(
                      Icons.person,
                      color: theme.primaryText,
                    ),
                  ),
                )
              : Icon(Icons.person, color: theme.primaryText),
        ),
        if (isMuted)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.volume_off, size: 12, color: Colors.white),
            ),
          ),
      ],
    );
  }
}
