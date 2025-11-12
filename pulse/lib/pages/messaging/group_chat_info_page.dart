import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import '../../components/micro_interactions.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/snackbar_utils.dart';
import '../../auth/firebase_auth/auth_util.dart';
import '../../backend/api_service.dart';
import '../../backend/socket_service.dart';
import '../profile/ProfilePage.dart';
import 'enhanced_messaging_page.dart';

/// 🎨 Group Chat Info Page
///
/// Displays comprehensive information about the group chat including:
/// - Group name and avatar
/// - Pulse information (if applicable)
/// - Member list with roles
/// - Media gallery
/// - Group settings
/// - Leave/Delete group options
class GroupChatInfoPage extends StatefulWidget {
  const GroupChatInfoPage({
    super.key,
    required this.chatId,
    required this.groupName,
    this.pulseName,
    required this.members,
    this.groupAvatarUrl,
    this.isPulseLive,
    this.pulseActiveFrom,
    this.pulseActiveUntil,
  });

  final String chatId;
  final String groupName;
  final String? pulseName;
  final List<Map<String, dynamic>> members;
  final String? groupAvatarUrl;
  final bool? isPulseLive;
  final DateTime? pulseActiveFrom;
  final DateTime? pulseActiveUntil;

  @override
  State<GroupChatInfoPage> createState() => _GroupChatInfoPageState();
}

class _GroupChatInfoPageState extends State<GroupChatInfoPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _notificationsEnabled = true;
  String? _currentGroupAvatarUrl;
  String _currentGroupName = '';
  bool _isUploadingPhoto = false;
  List<Map<String, dynamic>> _mediaMessages = [];
  bool _isLoadingMedia = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _currentGroupAvatarUrl = widget.groupAvatarUrl;
    _currentGroupName = widget.groupName;
    _loadMedia();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadMedia() async {
    if (_isLoadingMedia) return;

    setState(() => _isLoadingMedia = true);

    try {
      print('[MediaTab] Starting to load media for chat: ${widget.chatId}');
      final List<Map<String, dynamic>> allMedia = [];
      String? cursor;
      int totalMessages = 0;

      // Fetch messages in batches until we have enough media or run out
      for (int i = 0; i < 10; i++) {
        // Max 10 pages (300 messages)
        print('[MediaTab] Fetching page ${i + 1}, cursor: $cursor');

        final result = await ApiService.instance.listMessages(
          widget.chatId,
          cursor: cursor,
          limit: 30,
        );

        if (result == null) {
          print('[MediaTab] Result is null, stopping');
          break;
        }

        final messages = (result['messages'] as List<dynamic>?) ?? [];
        totalMessages += messages.length;
        print(
            '[MediaTab] Page ${i + 1}: Got ${messages.length} messages, total so far: $totalMessages');

        // Filter messages with media (imageUrl or videoUrl)
        for (final msg in messages) {
          if (msg is Map<String, dynamic>) {
            final imageUrl = msg['imageUrl'] as String?;
            final videoUrl = msg['videoUrl'] as String?;

            if ((imageUrl != null && imageUrl.isNotEmpty) ||
                (videoUrl != null && videoUrl.isNotEmpty)) {
              print(
                  '[MediaTab] Found message with media: ${msg['id']}, image: ${imageUrl != null}, video: ${videoUrl != null}');
              allMedia.add(msg);
            }
          }
        }

        cursor = result['nextCursor'] as String?;
        print(
            '[MediaTab] Next cursor: $cursor, media found so far: ${allMedia.length}');

        // Stop if no more pages or we have enough media
        if (cursor == null) {
          print('[MediaTab] No more pages');
          break;
        }
        if (allMedia.length >= 100) {
          print('[MediaTab] Reached 100 media items');
          break;
        }
      }

      print(
          '[MediaTab] Finished loading. Total messages: $totalMessages, Media messages: ${allMedia.length}');

      if (mounted) {
        setState(() {
          _mediaMessages = allMedia;
          _isLoadingMedia = false;
        });
      }
    } catch (e) {
      print('[MediaTab] Error loading media: $e');
      if (mounted) {
        setState(() => _isLoadingMedia = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.primaryBackground,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(theme, isDark),
          SliverToBoxAdapter(child: _buildGroupHeader(theme)),
          SliverToBoxAdapter(child: _buildPulseInfo(theme)),
          SliverToBoxAdapter(child: _buildQuickActions(theme)),
          SliverToBoxAdapter(child: _buildTabs(theme)),
          _buildTabContent(theme),
        ],
      ),
    );
  }

  Widget _buildAppBar(FlutterFlowTheme theme, bool isDark) {
    return SliverAppBar(
      expandedHeight: 120,
      pinned: true,
      backgroundColor: theme.secondaryBackground,
      leading: HapticIconButton(
        icon: Icons.arrow_back_ios_new_rounded,
        color: theme.primaryText,
        onPressed: () => Navigator.of(context).pop(),
        feedbackType: HapticsType.light,
      ),
      actions: [
        HapticIconButton(
          icon: Icons.edit_rounded,
          color: theme.primaryText,
          onPressed: _editGroupInfo,
          feedbackType: HapticsType.selection,
        ),
        const SizedBox(width: 8),
      ],
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: true,
        title: Text(
          'Group Info',
          style: theme.titleMedium.override(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildGroupHeader(FlutterFlowTheme theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Group Avatar with loading indicator
          Stack(
            children: [
              Hero(
                tag: 'group_avatar_${widget.chatId}',
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [theme.primary, theme.tertiary],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: theme.primary.withOpacity(.3),
                        blurRadius: 20,
                        spreadRadius: 2,
                      )
                    ],
                  ),
                  padding: const EdgeInsets.all(3),
                  child: CircleAvatar(
                    backgroundColor: theme.secondaryBackground,
                    backgroundImage: _currentGroupAvatarUrl != null
                        ? CachedNetworkImageProvider(_currentGroupAvatarUrl!)
                        : null,
                    child: _currentGroupAvatarUrl == null
                        ? Icon(
                            Icons.group_rounded,
                            color: theme.secondaryText,
                            size: 48,
                          )
                        : null,
                  ),
                ),
              ),
              if (_isUploadingPhoto)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // Group Name
          Text(
            _currentGroupName,
            style: theme.headlineSmall.override(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          // Member Count
          Text(
            '${widget.members.length} ${widget.members.length == 1 ? "member" : "members"}',
            style: theme.bodyMedium.override(
              color: theme.secondaryText,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildPulseInfo(FlutterFlowTheme theme) {
    if (widget.pulseName == null) return const SizedBox.shrink();

    final isPulseLive = widget.isPulseLive ?? false;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: isPulseLive
            ? LinearGradient(
                colors: [
                  theme.primary.withOpacity(.1),
                  theme.tertiary.withOpacity(.1),
                ],
              )
            : null,
        color: isPulseLive ? null : theme.secondaryBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPulseLive
              ? theme.primary.withOpacity(.3)
              : theme.secondaryText.withOpacity(.1),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.motion_photos_on_rounded,
                color: isPulseLive ? theme.primary : theme.secondaryText,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Pulse Chat',
                  style: theme.titleSmall.override(
                    fontWeight: FontWeight.w700,
                    color: isPulseLive ? theme.primary : theme.primaryText,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isPulseLive ? theme.primary : theme.secondaryText,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isPulseLive ? 'LIVE' : 'ENDED',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.pulseName!,
            style: theme.bodyMedium.override(
              color: theme.primaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (widget.pulseActiveFrom != null) ...[
            const SizedBox(height: 8),
            Text(
              _formatPulseTime(),
              style: theme.bodySmall.override(
                color: theme.secondaryText,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickActions(FlutterFlowTheme theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: _quickActionButton(
              theme,
              icon: Icons.volume_up_rounded,
              label: 'Mute',
              onTap: _toggleNotifications,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _quickActionButton(
              theme,
              icon: Icons.search_rounded,
              label: 'Search',
              onTap: _searchInChat,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _quickActionButton(
              theme,
              icon: Icons.wallpaper_rounded,
              label: 'Media',
              onTap: () => _tabController.animateTo(1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionButton(
    FlutterFlowTheme theme, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return AnimatedButton(
      onPressed: () async {
        await HapticUtils.light();
        onTap();
      },
      scaleAmount: 0.95,
      backgroundColor: theme.secondaryBackground,
      borderRadius: BorderRadius.circular(12),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Icon(icon, color: theme.primaryText, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.bodySmall.override(
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs(FlutterFlowTheme theme) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        border: Border(
          bottom: BorderSide(
            color: theme.secondaryText.withOpacity(.1),
            width: 1,
          ),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorColor: theme.primary,
        labelColor: theme.primary,
        unselectedLabelColor: theme.secondaryText,
        labelStyle: theme.bodyMedium.override(fontWeight: FontWeight.w700),
        tabs: const [
          Tab(text: 'Members'),
          Tab(text: 'Media'),
          Tab(text: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildTabContent(FlutterFlowTheme theme) {
    return SliverFillRemaining(
      child: TabBarView(
        controller: _tabController,
        children: [
          _buildMembersTab(theme),
          _buildMediaTab(theme),
          _buildSettingsTab(theme),
        ],
      ),
    );
  }

  Widget _buildMembersTab(FlutterFlowTheme theme) {
    final sortedMembers = List<Map<String, dynamic>>.from(widget.members)
      ..sort((a, b) {
        final aName = (a['displayName'] ?? a['name'] ?? 'User').toString();
        final bName = (b['displayName'] ?? b['name'] ?? 'User').toString();
        return aName.compareTo(bName);
      });

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sortedMembers.length + 1, // +1 for "Add Members" button
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildAddMemberTile(theme);
        }

        final member = sortedMembers[index - 1];
        final memberId = (member['id'] ?? member['userId'] ?? '').toString();
        final isCurrentUser = memberId == currentUserUid;

        return _buildMemberTile(theme, member, isCurrentUser);
      },
    );
  }

  Widget _buildAddMemberTile(FlutterFlowTheme theme) {
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: theme.primary.withOpacity(.1),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.person_add_rounded, color: theme.primary),
      ),
      title: Text(
        'Add Members',
        style: theme.bodyLarge.override(
          color: theme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: () async {
        await HapticUtils.selection();
        _addMembers();
      },
    );
  }

  Widget _buildMemberTile(
    FlutterFlowTheme theme,
    Map<String, dynamic> member,
    bool isCurrentUser,
  ) {
    final name = (member['displayName'] ?? member['name'] ?? 'User').toString();
    final avatarUrl = (member['photoUrl'] ?? member['avatar'])?.toString();
    final memberId = (member['id'] ?? member['userId'] ?? '').toString();

    return ListTile(
      leading: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [theme.primary, theme.tertiary],
          ),
        ),
        padding: const EdgeInsets.all(2),
        child: CircleAvatar(
          radius: 22,
          backgroundColor: theme.secondaryBackground,
          backgroundImage:
              avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
          child: avatarUrl == null
              ? Icon(Icons.person, color: theme.secondaryText, size: 24)
              : null,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: theme.bodyLarge.override(
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isCurrentUser)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.primary.withOpacity(.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'You',
                style: theme.bodySmall.override(
                  color: theme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
      subtitle: member['email'] != null
          ? Text(
              member['email'].toString(),
              style: theme.bodySmall.override(
                color: theme.secondaryText,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: !isCurrentUser
          ? PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: theme.secondaryText),
              onSelected: (value) => _handleMemberAction(value, memberId, name),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'view_profile',
                  child: Row(
                    children: [
                      Icon(Icons.person_rounded, color: theme.primaryText),
                      const SizedBox(width: 12),
                      const Text('View Profile'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'message',
                  child: Row(
                    children: [
                      Icon(Icons.message_rounded, color: theme.primaryText),
                      const SizedBox(width: 12),
                      const Text('Send Message'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'remove',
                  child: Row(
                    children: [
                      Icon(Icons.person_remove_rounded, color: theme.error),
                      const SizedBox(width: 12),
                      Text('Remove', style: TextStyle(color: theme.error)),
                    ],
                  ),
                ),
              ],
            )
          : null,
    );
  }

  Widget _buildMediaTab(FlutterFlowTheme theme) {
    if (_isLoadingMedia) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: theme.primary),
            const SizedBox(height: 16),
            Text(
              'Loading media...',
              style: theme.bodyMedium.override(color: theme.secondaryText),
            ),
          ],
        ),
      );
    }

    if (_mediaMessages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.photo_library_rounded,
                size: 64,
                color: theme.secondaryText.withOpacity(.5),
              ),
              const SizedBox(height: 16),
              Text(
                'No Media Yet',
                style: theme.titleMedium.override(
                  color: theme.secondaryText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Photos and videos shared in this chat will appear here',
                style: theme.bodySmall.override(
                  color: theme.secondaryText,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Build grid of media
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: _mediaMessages.length,
      itemBuilder: (context, index) {
        final message = _mediaMessages[index];
        final imageUrl = message['imageUrl'] as String?;
        final videoUrl = message['videoUrl'] as String?;

        // Determine media type and URL
        final isVideo = videoUrl != null && videoUrl.isNotEmpty;
        final mediaUrl = isVideo ? videoUrl : imageUrl;

        if (mediaUrl == null || mediaUrl.isEmpty)
          return const SizedBox.shrink();

        return GestureDetector(
          onTap: () {
            // TODO: Open full-screen media viewer
            HapticUtils.light();
          },
          child: Container(
            decoration: BoxDecoration(
              color: theme.secondaryBackground,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (!isVideo)
                    CachedNetworkImage(
                      imageUrl: mediaUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: theme.secondaryBackground,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: theme.primary,
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: theme.secondaryBackground,
                        child: Icon(
                          Icons.broken_image_rounded,
                          color: theme.secondaryText,
                        ),
                      ),
                    )
                  else if (isVideo)
                    Stack(
                      fit: StackFit.expand,
                      children: [
                        // Video thumbnail (if available) or placeholder
                        Container(
                          color: theme.secondaryBackground,
                          child: Icon(
                            Icons.play_circle_outline_rounded,
                            size: 40,
                            color: Colors.white.withOpacity(.9),
                          ),
                        ),
                        // Play icon overlay
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Container(
                      color: theme.secondaryBackground,
                      child: Icon(
                        Icons.insert_drive_file_rounded,
                        color: theme.secondaryText,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingsTab(FlutterFlowTheme theme) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        SwitchListTile(
          value: _notificationsEnabled,
          onChanged: (value) {
            HapticUtils.selection();
            setState(() => _notificationsEnabled = value);
            CustomSnackbar.showSuccess(
              context,
              message: value ? 'Notifications enabled' : 'Notifications muted',
            );
          },
          title: Text(
            'Notifications',
            style: theme.bodyLarge,
          ),
          subtitle: Text(
            _notificationsEnabled ? 'You will receive notifications' : 'Muted',
            style: theme.bodySmall.override(color: theme.secondaryText),
          ),
          secondary: Icon(
            _notificationsEnabled
                ? Icons.notifications_active_rounded
                : Icons.notifications_off_rounded,
            color: theme.primaryText,
          ),
          activeColor: theme.primary,
        ),
        const Divider(height: 1),
        ListTile(
          leading: Icon(Icons.photo_rounded, color: theme.primaryText),
          title: Text('Change Group Photo', style: theme.bodyLarge),
          trailing:
              Icon(Icons.chevron_right_rounded, color: theme.secondaryText),
          onTap: () async {
            await HapticUtils.selection();
            _changeGroupPhoto();
          },
        ),
        ListTile(
          leading: Icon(Icons.edit_rounded, color: theme.primaryText),
          title: Text('Change Group Name', style: theme.bodyLarge),
          trailing:
              Icon(Icons.chevron_right_rounded, color: theme.secondaryText),
          onTap: () async {
            await HapticUtils.selection();
            _changeGroupName();
          },
        ),
        const Divider(height: 1),
        ListTile(
          leading: Icon(Icons.report_rounded, color: theme.error),
          title: Text(
            'Report Group',
            style: theme.bodyLarge.override(color: theme.error),
          ),
          onTap: () async {
            await HapticUtils.selection();
            _reportGroup();
          },
        ),
        ListTile(
          leading: Icon(Icons.exit_to_app_rounded, color: theme.error),
          title: Text(
            'Leave Group',
            style: theme.bodyLarge.override(color: theme.error),
          ),
          onTap: () async {
            await HapticUtils.selection();
            _leaveGroup();
          },
        ),
      ],
    );
  }

  String _formatPulseTime() {
    if (widget.pulseActiveFrom == null) return '';

    final now = DateTime.now();
    final from = widget.pulseActiveFrom!;
    final until = widget.pulseActiveUntil;

    if (until != null && now.isAfter(until)) {
      return 'Ended ${_formatRelativeTime(until)}';
    } else if (now.isBefore(from)) {
      return 'Starts ${_formatRelativeTime(from)}';
    } else {
      return until != null
          ? 'Ends ${_formatRelativeTime(until)}'
          : 'Started ${_formatRelativeTime(from)}';
    }
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = dateTime.difference(now);

    if (difference.isNegative) {
      final absDiff = difference.abs();
      if (absDiff.inMinutes < 60) {
        return '${absDiff.inMinutes}m ago';
      } else if (absDiff.inHours < 24) {
        return '${absDiff.inHours}h ago';
      } else {
        return '${absDiff.inDays}d ago';
      }
    } else {
      if (difference.inMinutes < 60) {
        return 'in ${difference.inMinutes}m';
      } else if (difference.inHours < 24) {
        return 'in ${difference.inHours}h';
      } else {
        return 'in ${difference.inDays}d';
      }
    }
  }

  void _editGroupInfo() {
    CustomSnackbar.showInfo(context, message: 'Edit group info');
  }

  void _toggleNotifications() {
    setState(() => _notificationsEnabled = !_notificationsEnabled);
    CustomSnackbar.showSuccess(
      context,
      message: _notificationsEnabled
          ? 'Notifications enabled'
          : 'Notifications muted',
    );
  }

  void _addMembers() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddMembersSheet(
        chatId: widget.chatId,
        existingMemberIds:
            widget.members.map((m) => m['id']?.toString() ?? '').toSet(),
        onMembersAdded: (addedCount) {
          if (mounted) {
            CustomSnackbar.showSuccess(
              context,
              message:
                  '$addedCount member${addedCount > 1 ? 's' : ''} added successfully',
            );
            // Refresh the page to show new members
            Navigator.of(context).pop(); // Close the info page
          }
        },
      ),
    );
  }

  void _handleMemberAction(String action, String memberId, String memberName) {
    switch (action) {
      case 'view_profile':
        _viewProfile(memberId);
        break;
      case 'message':
        _sendMessage(memberId, memberName);
        break;
      case 'remove':
        _showRemoveMemberDialog(memberId, memberName);
        break;
    }
  }

  void _viewProfile(String userId) async {
    try {
      HapticUtils.light();
      // Navigate to ProfilePage
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProfilePage(userId: userId),
        ),
      );
    } catch (e) {
      print('Error navigating to profile: $e');
      CustomSnackbar.showError(context, message: 'Unable to view profile');
    }
  }

  void _sendMessage(String userId, String userName) async {
    try {
      HapticUtils.light();

      // Show loading
      CustomSnackbar.showInfo(context, message: 'Starting conversation...');

      // Get or create direct conversation
      final convo =
          await ApiService.instance.getOrCreateConversationWith(userId);

      if (convo == null) {
        CustomSnackbar.showError(context,
            message: 'Unable to start conversation');
        return;
      }

      final chatId = (convo['id'] ?? '').toString();

      // Get user profile info for the messaging page
      final profileData = await ApiService.instance.getUserProfileById(userId);
      final photoUrl = profileData?['profileImageUrl']?.toString() ?? '';

      // Notify socket service
      try {
        SocketService.instance.notifyConversationLocally(chatId);
      } catch (_) {}

      // Navigate to messaging page
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EnhancedMessagingPage(
              chatId: chatId,
              recipientUserId: userId,
              recipientName: userName,
              recipientPhotoUrl: photoUrl,
            ),
          ),
        );
      }
    } catch (e) {
      print('Error starting conversation: $e');
      if (mounted) {
        CustomSnackbar.showError(context,
            message: 'Unable to start conversation');
      }
    }
  }

  void _showRemoveMemberDialog(String memberId, String memberName) {
    showDialog(
      context: context,
      builder: (context) {
        final theme = FlutterFlowTheme.of(context);
        return AlertDialog(
          title: Text('Remove Member?', style: theme.titleMedium),
          content: Text(
            'Are you sure you want to remove $memberName from this group?',
            style: theme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  Text('Cancel', style: TextStyle(color: theme.secondaryText)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                CustomSnackbar.showSuccess(
                  context,
                  message: '$memberName removed from group',
                );
              },
              child: Text('Remove', style: TextStyle(color: theme.error)),
            ),
          ],
        );
      },
    );
  }

  void _changeGroupPhoto() async {
    await HapticUtils.selection();

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    if (pickedFile == null || !mounted) return;

    setState(() => _isUploadingPhoto = true);

    try {
      // Upload to Firebase Storage
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('group_avatars')
          .child(
              '${widget.chatId}_${DateTime.now().millisecondsSinceEpoch}.jpg');

      final uploadTask = await storageRef.putFile(File(pickedFile.path));
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      // Update via API
      final result = await ApiService.instance.updateGroupConversation(
        widget.chatId,
        avatarUrl: downloadUrl,
      );

      if (mounted) {
        setState(() => _isUploadingPhoto = false);

        if (result != null) {
          setState(() => _currentGroupAvatarUrl = downloadUrl);
          CustomSnackbar.showSuccess(
            context,
            message: 'Group photo updated successfully',
          );
        } else {
          CustomSnackbar.showError(
            context,
            message: 'Failed to update group photo',
          );
        }
      }
    } catch (e) {
      print('Error changing group photo: $e');
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
        CustomSnackbar.showError(
          context,
          message: 'Failed to update group photo',
        );
      }
    }
  }

  void _changeGroupName() async {
    await HapticUtils.selection();

    final controller = TextEditingController(text: _currentGroupName);

    if (!mounted) return;

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        final theme = FlutterFlowTheme.of(context);
        return AlertDialog(
          title: Text('Change Group Name', style: theme.titleMedium),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 50,
            decoration: InputDecoration(
              hintText: 'Enter new group name',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: theme.primary, width: 2),
              ),
            ),
            style: theme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  Text('Cancel', style: TextStyle(color: theme.secondaryText)),
            ),
            TextButton(
              onPressed: () {
                final newName = controller.text.trim();
                if (newName.isNotEmpty) {
                  Navigator.pop(context, newName);
                }
              },
              child: Text('Save', style: TextStyle(color: theme.primary)),
            ),
          ],
        );
      },
    );

    if (result != null && result.isNotEmpty && result != _currentGroupName) {
      try {
        // Update via API
        final apiResult = await ApiService.instance.updateGroupConversation(
          widget.chatId,
          name: result,
        );

        if (mounted) {
          if (apiResult != null) {
            setState(() => _currentGroupName = result);
            CustomSnackbar.showSuccess(
              context,
              message: 'Group name updated successfully',
            );
          } else {
            CustomSnackbar.showError(
              context,
              message: 'Failed to update group name',
            );
          }
        }
      } catch (e) {
        print('Error changing group name: $e');
        if (mounted) {
          CustomSnackbar.showError(
            context,
            message: 'Failed to update group name',
          );
        }
      }
    }

    controller.dispose();
  }

  void _searchInChat() async {
    await HapticUtils.selection();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SearchSheet(
        chatId: widget.chatId,
        members: widget.members,
      ),
    );
  }

  void _reportGroup() {
    CustomSnackbar.showWarning(context, message: 'Report group');
  }

  void _leaveGroup() {
    showDialog(
      context: context,
      builder: (context) {
        final theme = FlutterFlowTheme.of(context);
        return AlertDialog(
          title: Text('Leave Group?', style: theme.titleMedium),
          content: Text(
            'Are you sure you want to leave "${widget.groupName}"? You won\'t be able to see new messages.',
            style: theme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  Text('Cancel', style: TextStyle(color: theme.secondaryText)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context); // Close info page
                Navigator.pop(context); // Close chat page
                CustomSnackbar.showSuccess(
                  context,
                  message: 'Left the group',
                );
              },
              child: Text('Leave', style: TextStyle(color: theme.error)),
            ),
          ],
        );
      },
    );
  }
}

/// Search Sheet Widget for searching messages in chat
class _SearchSheet extends StatefulWidget {
  final String chatId;
  final List<Map<String, dynamic>> members;

  const _SearchSheet({
    required this.chatId,
    required this.members,
  });

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // Auto-focus on the search field
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _searchQuery = '';
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchQuery = query;
    });

    try {
      // Call the API to search messages
      final results = await ApiService.instance.searchMessages(
        widget.chatId,
        query,
        limit: 50,
      );

      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      print('Search error: $e');
      if (mounted) {
        setState(() => _isSearching = false);
        CustomSnackbar.showError(
          context,
          message: 'Search failed',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: theme.primaryBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.secondaryText.withOpacity(.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Search header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Search Messages',
                    style: theme.headlineSmall.override(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: theme.secondaryText),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Search input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: theme.secondaryBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.primary.withOpacity(.15),
                  width: 1.5,
                ),
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _focusNode,
                onChanged: _performSearch,
                style: theme.bodyMedium,
                decoration: InputDecoration(
                  hintText: 'Search for messages...',
                  hintStyle: theme.bodyMedium.override(
                    color: theme.secondaryText.withOpacity(.6),
                  ),
                  prefixIcon: Icon(Icons.search_rounded, color: theme.primary),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear_rounded,
                              color: theme.secondaryText),
                          onPressed: () {
                            _searchController.clear();
                            _performSearch('');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Search results
          Expanded(
            child: _buildSearchResults(theme),
          ),

          // Keyboard spacer
          SizedBox(height: keyboardHeight),
        ],
      ),
    );
  }

  Widget _buildSearchResults(FlutterFlowTheme theme) {
    if (_isSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: theme.primary),
            const SizedBox(height: 16),
            Text(
              'Searching...',
              style: theme.bodyMedium.override(color: theme.secondaryText),
            ),
          ],
        ),
      );
    }

    if (_searchQuery.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_rounded,
              size: 64,
              color: theme.secondaryText.withOpacity(.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Search Messages',
              style: theme.titleMedium.override(color: theme.secondaryText),
            ),
            const SizedBox(height: 8),
            Text(
              'Type to search for messages in this chat',
              style: theme.bodySmall.override(color: theme.secondaryText),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 64,
              color: theme.secondaryText.withOpacity(.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No Results Found',
              style: theme.titleMedium.override(color: theme.secondaryText),
            ),
            const SizedBox(height: 8),
            Text(
              'Try searching with different keywords',
              style: theme.bodySmall.override(color: theme.secondaryText),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final result = _searchResults[index];
        return _buildSearchResultItem(theme, result);
      },
    );
  }

  Widget _buildSearchResultItem(
    FlutterFlowTheme theme,
    Map<String, dynamic> result,
  ) {
    final text = result['text']?.toString() ?? '';
    final senderId = result['senderId']?.toString() ?? '';

    // Handle timestamp - could be string or DateTime
    DateTime? timestamp;
    if (result['createdAt'] != null) {
      if (result['createdAt'] is DateTime) {
        timestamp = result['createdAt'] as DateTime;
      } else if (result['createdAt'] is String) {
        timestamp = DateTime.tryParse(result['createdAt'] as String);
      }
    }

    // Get sender info from result or members
    String senderName = 'User';
    String? senderAvatar;

    if (result['sender'] != null && result['sender'] is Map) {
      final senderData = result['sender'] as Map<String, dynamic>;
      senderName = senderData['displayName']?.toString() ?? 'User';
      senderAvatar = senderData['profileImageUrl']?.toString();
    } else {
      // Fallback to members list
      final sender = widget.members.firstWhere(
        (m) => (m['id'] ?? m['userId']) == senderId,
        orElse: () => <String, dynamic>{},
      );
      if (sender.isNotEmpty) {
        senderName =
            (sender['displayName'] ?? sender['name'] ?? 'User').toString();
        senderAvatar = sender['photoUrl']?.toString() ??
            sender['profileImageUrl']?.toString();
      }
    }

    return ListTile(
      leading: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: senderAvatar == null
              ? LinearGradient(
                  colors: [theme.primary, theme.tertiary],
                )
              : null,
        ),
        padding: senderAvatar == null ? const EdgeInsets.all(2) : null,
        child: CircleAvatar(
          radius: 20,
          backgroundColor: theme.secondaryBackground,
          backgroundImage: senderAvatar != null
              ? CachedNetworkImageProvider(senderAvatar)
              : null,
          child: senderAvatar == null
              ? Icon(Icons.person, color: theme.secondaryText, size: 20)
              : null,
        ),
      ),
      title: Text(
        senderName,
        style: theme.bodyMedium.override(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: theme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (timestamp != null) ...[
            const SizedBox(height: 4),
            Text(
              _formatTimestamp(timestamp),
              style: theme.bodySmall.override(
                color: theme.secondaryText,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
      onTap: () async {
        await HapticUtils.selection();
        // TODO: Navigate to message in chat
        Navigator.pop(context);
        CustomSnackbar.showInfo(context, message: 'Jump to message');
      },
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 7) {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}

/// Bottom sheet for adding members to a group chat
class _AddMembersSheet extends StatefulWidget {
  const _AddMembersSheet({
    required this.chatId,
    required this.existingMemberIds,
    required this.onMembersAdded,
  });

  final String chatId;
  final Set<String> existingMemberIds;
  final Function(int) onMembersAdded;

  @override
  State<_AddMembersSheet> createState() => _AddMembersSheetState();
}

class _AddMembersSheetState extends State<_AddMembersSheet> {
  final _searchController = TextEditingController();
  final Set<String> _selectedUserIds = {};
  List<Map<String, dynamic>> _allFollowers = [];
  List<Map<String, dynamic>> _filteredFollowers = [];
  bool _isLoadingFollowers = false;
  bool _isAdding = false;

  @override
  void initState() {
    super.initState();
    _loadFollowers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFollowers() async {
    setState(() => _isLoadingFollowers = true);

    try {
      final userId = currentUserUid;
      if (userId.isEmpty) {
        if (mounted) {
          setState(() => _isLoadingFollowers = false);
        }
        return;
      }

      // Load both followers and following
      final followers = await ApiService.instance.getUserFollowers(userId);
      final following = await ApiService.instance.getUserFollowing(userId);

      if (mounted) {
        // Combine followers and following, remove duplicates and existing members
        final allUsers = <String, Map<String, dynamic>>{};

        if (followers != null) {
          for (var user in followers) {
            final id = user['id']?.toString();
            if (id != null &&
                id != userId &&
                !widget.existingMemberIds.contains(id)) {
              allUsers[id] = user;
            }
          }
        }

        if (following != null) {
          for (var user in following) {
            final id = user['id']?.toString();
            if (id != null &&
                id != userId &&
                !widget.existingMemberIds.contains(id)) {
              allUsers[id] = user;
            }
          }
        }

        setState(() {
          _allFollowers = allUsers.values.toList();
          _filteredFollowers = _allFollowers;
          _isLoadingFollowers = false;
        });
      }
    } catch (e) {
      print('Error loading followers: $e');
      if (mounted) {
        setState(() => _isLoadingFollowers = false);
      }
    }
  }

  void _filterFollowers(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _filteredFollowers = _allFollowers;
      });
      return;
    }

    final lowerQuery = query.toLowerCase();
    setState(() {
      _filteredFollowers = _allFollowers.where((user) {
        final name = (user['displayName']?.toString() ?? '').toLowerCase();
        final email = (user['email']?.toString() ?? '').toLowerCase();
        return name.contains(lowerQuery) || email.contains(lowerQuery);
      }).toList();
    });
  }

  Future<void> _addSelectedMembers() async {
    if (_selectedUserIds.isEmpty) {
      CustomSnackbar.showError(context,
          message: 'Please select at least one member');
      return;
    }

    setState(() => _isAdding = true);

    try {
      final result = await ApiService.instance.addMembersToConversation(
        widget.chatId,
        _selectedUserIds.toList(),
      );

      if (result != null) {
        HapticUtils.success();
        widget.onMembersAdded(_selectedUserIds.length);
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        if (mounted) {
          CustomSnackbar.showError(context, message: 'Failed to add members');
        }
      }
    } catch (e) {
      print('Error adding members: $e');
      if (mounted) {
        CustomSnackbar.showError(context, message: 'Error adding members');
      }
    } finally {
      if (mounted) {
        setState(() => _isAdding = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: theme.primaryBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.secondaryBackground,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(
                bottom: BorderSide(color: theme.alternate, width: 1),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.close, color: theme.secondaryText),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add Members',
                        style: theme.titleMedium.override(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_selectedUserIds.isNotEmpty)
                        Text(
                          '${_selectedUserIds.length} selected',
                          style: theme.bodySmall.override(
                            color: theme.primary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (_selectedUserIds.isNotEmpty)
                  ElevatedButton(
                    onPressed: _isAdding ? null : _addSelectedMembers,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                    child: _isAdding
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('Add'),
                  ),
              ],
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name or email',
                filled: true,
                fillColor: theme.secondaryBackground,
                prefixIcon: Icon(Icons.search, color: theme.secondaryText),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: _filterFollowers,
            ),
          ),

          // Selected members chips
          if (_selectedUserIds.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _allFollowers
                    .where((user) => _selectedUserIds.contains(user['id']))
                    .map((user) => Chip(
                          avatar: CircleAvatar(
                            backgroundImage: user['profileImageUrl'] != null
                                ? NetworkImage(user['profileImageUrl'])
                                : null,
                            child: user['profileImageUrl'] == null
                                ? Text(
                                    (user['displayName']?.toString() ?? '?')[0]
                                        .toUpperCase(),
                                    style: const TextStyle(fontSize: 12),
                                  )
                                : null,
                          ),
                          label: Text(user['displayName'] ?? 'Unknown'),
                          deleteIcon: Icon(Icons.close, size: 18),
                          onDeleted: () {
                            HapticUtils.light();
                            setState(() {
                              _selectedUserIds.remove(user['id']);
                            });
                          },
                        ))
                    .toList(),
              ),
            ),
            const Divider(height: 1),
          ],

          // Followers list
          Expanded(
            child: _isLoadingFollowers
                ? Center(
                    child: CircularProgressIndicator(color: theme.primary),
                  )
                : _allFollowers.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.people_outline,
                                size: 64,
                                color: theme.secondaryText.withOpacity(0.5),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No users available',
                                style: theme.titleMedium.override(
                                  color: theme.secondaryText,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'All your followers and following are already in this group',
                                style: theme.bodySmall.override(
                                  color: theme.secondaryText,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : _filteredFollowers.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.search_off,
                                    size: 64,
                                    color: theme.secondaryText.withOpacity(0.5),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No results found',
                                    style: theme.titleMedium.override(
                                      color: theme.secondaryText,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Try a different search term',
                                    style: theme.bodySmall.override(
                                      color: theme.secondaryText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: EdgeInsets.only(bottom: keyboardHeight),
                            itemCount: _filteredFollowers.length,
                            itemBuilder: (context, index) {
                              final user = _filteredFollowers[index];
                              final userId = user['id'] as String;
                              final isSelected =
                                  _selectedUserIds.contains(userId);

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundImage: user['profileImageUrl'] !=
                                          null
                                      ? NetworkImage(user['profileImageUrl'])
                                      : null,
                                  backgroundColor:
                                      theme.primary.withOpacity(0.1),
                                  child: user['profileImageUrl'] == null
                                      ? Text(
                                          (user['displayName']?.toString() ??
                                                  '?')[0]
                                              .toUpperCase(),
                                          style: TextStyle(
                                            color: theme.primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      : null,
                                ),
                                title: Text(
                                  user['displayName'] ?? 'Unknown',
                                  style: theme.bodyLarge,
                                ),
                                subtitle: user['email'] != null
                                    ? Text(
                                        user['email'],
                                        style: theme.bodySmall.override(
                                          color: theme.secondaryText,
                                        ),
                                      )
                                    : null,
                                trailing: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  child: isSelected
                                      ? Icon(
                                          Icons.check_circle,
                                          color: theme.primary,
                                          key: ValueKey('selected_$userId'),
                                        )
                                      : Icon(
                                          Icons.add_circle_outline,
                                          color: theme.secondaryText,
                                          key: ValueKey('unselected_$userId'),
                                        ),
                                ),
                                onTap: () {
                                  HapticUtils.selection();
                                  setState(() {
                                    if (isSelected) {
                                      _selectedUserIds.remove(userId);
                                    } else {
                                      _selectedUserIds.add(userId);
                                    }
                                  });
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
