import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../backend/api_service.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import '../../utils/snackbar_utils.dart';
import '../../utils/haptic_utils.dart';

class PulseInvitationsPage extends StatefulWidget {
  const PulseInvitationsPage({super.key});

  static String routeName = 'Invitations';
  static String routePath = '/invitations';

  @override
  State<PulseInvitationsPage> createState() => _PulseInvitationsPageState();
}

class _PulseInvitationsPageState extends State<PulseInvitationsPage> {
  Future<List<Map<String, dynamic>>?>? _future;
  final Set<String> _respondingIds = {};
  String _selectedFilter = 'all'; // 'all', 'PULSE_CHAT', 'GROUP_CHAT'

  @override
  void initState() {
    super.initState();
    _loadInvitations();
  }

  void _loadInvitations() {
    setState(() {
      if (_selectedFilter == 'all') {
        _future = ApiService.instance.getAllInvitations();
      } else {
        _future = ApiService.instance.getAllInvitations(type: _selectedFilter);
      }
    });
  }

  Future<void> _refresh() async {
    _loadInvitations();
    await _future;
  }

  Future<void> _respondToInvitation({
    required String invitationId,
    required bool accept,
  }) async {
    if (_respondingIds.contains(invitationId)) return;

    setState(() => _respondingIds.add(invitationId));
    await HapticUtils.medium();

    try {
      final result = await ApiService.instance.respondToInvitationUnified(
        invitationId: invitationId,
        accept: accept,
      );

      if (mounted) {
        if (result != null && result['success'] == true) {
          await HapticUtils.success();
          CustomSnackbar.showSuccess(
            context,
            message: accept ? 'Invitation accepted!' : 'Invitation declined',
          );
          _loadInvitations();
        } else {
          await HapticUtils.error();
          CustomSnackbar.showError(
            context,
            message: 'Failed to respond to invitation',
          );
        }
      }
    } catch (e) {
      print('Error responding to invitation: $e');
      if (mounted) {
        await HapticUtils.error();
        CustomSnackbar.showError(
          context,
          message: 'Error responding to invitation',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _respondingIds.remove(invitationId));
      }
    }
  }

  String _timeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inDays > 365) {
      final years = (diff.inDays / 365).floor();
      return '$years${years == 1 ? ' year' : ' years'} ago';
    } else if (diff.inDays > 30) {
      final months = (diff.inDays / 30).floor();
      return '$months${months == 1 ? ' month' : ' months'} ago';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}${diff.inDays == 1 ? ' day' : ' days'} ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}${diff.inHours == 1 ? ' hour' : ' hours'} ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}${diff.inMinutes == 1 ? ' minute' : ' minutes'} ago';
    } else {
      return 'Just now';
    }
  }

  Widget _buildFilterChip(String label, String value, IconData icon) {
    final theme = FlutterFlowTheme.of(context);
    final isSelected = _selectedFilter == value;

    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 16, color: isSelected ? Colors.white : theme.primaryText),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (selected) async {
        await HapticUtils.light();
        setState(() => _selectedFilter = value);
        _loadInvitations();
      },
      selectedColor: theme.primary,
      backgroundColor: theme.secondaryBackground,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : theme.primaryText,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? theme.primary : theme.alternate,
          width: 1,
        ),
      ),
    );
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
          'Invitations',
          style: theme.titleLarge.override(
            font: GoogleFonts.interTight(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Filter chips
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.secondaryBackground,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('All', 'all', Icons.inbox_rounded),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                      'Pulses', 'PULSE_CHAT', Icons.podcasts_rounded),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                      'Groups', 'GROUP_CHAT', Icons.groups_rounded),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                      'Followers', 'FOLLOW_REQUEST', Icons.person_add_rounded),
                ],
              ),
            ),
          ),

          // Invitations list
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<List<Map<String, dynamic>>?>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: 3,
                      itemBuilder: (_, __) => Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.secondaryBackground,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 20,
                              width: 150,
                              color: theme.alternate,
                            ),
                            const SizedBox(height: 12),
                            Container(
                              height: 16,
                              width: double.infinity,
                              color: theme.alternate,
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: 16,
                              width: 200,
                              color: theme.alternate,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final invitations = snapshot.data ?? [];

                  if (invitations.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 100),
                        Icon(
                          Icons.mail_outline_rounded,
                          size: 80,
                          color: theme.secondaryText.withOpacity(.5),
                        ),
                        const SizedBox(height: 24),
                        Center(
                          child: Text(
                            'No pending invitations',
                            style: theme.titleMedium.override(
                              color: theme.secondaryText,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            _selectedFilter == 'all'
                                ? 'You\'re all caught up!'
                                : _selectedFilter == 'PULSE_CHAT'
                                    ? 'No pulse invitations'
                                    : 'No group invitations',
                            style: theme.bodyMedium.override(
                              color: theme.secondaryText,
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: invitations.length,
                    itemBuilder: (context, index) {
                      return _buildInvitationCard(invitations[index], theme);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvitationCard(
      Map<String, dynamic> invitation, FlutterFlowTheme theme) {
    final invitationId = invitation['id']?.toString() ?? '';
    final status = invitation['status']?.toString() ?? 'PENDING';
    final invitationType = invitation['type']?.toString() ?? 'GROUP_CHAT';

    // Extract data based on type
    final pulse = invitation['pulse'];
    final conversation = invitation['conversation'];

    String itemName;
    String? itemDescription;
    String? itemImageUrl;

    if (invitationType == 'FOLLOW_REQUEST') {
      // For follow requests, we don't need item info
      itemName = '';
      itemDescription = null;
      itemImageUrl = null;
    } else if (invitationType == 'PULSE_CHAT' && pulse != null) {
      itemName = pulse['title']?.toString() ?? 'Unnamed Pulse';
      itemDescription = pulse['description']?.toString();
      itemImageUrl = pulse['imageUrl']?.toString();
    } else if (conversation != null) {
      itemName = conversation['name']?.toString() ?? 'Group Chat';
      itemDescription = null;
      itemImageUrl = conversation['avatarUrl']?.toString();
    } else {
      itemName = 'Invitation';
      itemDescription = null;
      itemImageUrl = null;
    }

    // Inviter info
    final inviter = invitation['inviter'];
    final inviterName = inviter?['displayName']?.toString() ?? 'Someone';
    final inviterImage = inviter?['profileImageUrl']?.toString();
    final inviterBio = inviter?['bio']?.toString();
    final followersCount = inviter?['followersCount'] as int? ?? 0;
    final followingCount = inviter?['followingCount'] as int? ?? 0;

    // Time
    final createdAt =
        DateTime.tryParse(invitation['createdAt']?.toString() ?? '');
    final timeText = createdAt != null ? _timeAgo(createdAt) : '';

    final isResponding = _respondingIds.contains(invitationId);
    final isPending = status.toUpperCase() == 'PENDING';
    final isPulseChat = invitationType == 'PULSE_CHAT';
    final isFollowRequest = invitationType == 'FOLLOW_REQUEST';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with inviter info
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: inviterImage != null
                      ? CachedNetworkImageProvider(inviterImage)
                      : null,
                  child: inviterImage == null
                      ? Icon(Icons.person, color: theme.secondaryText)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: inviterName,
                              style: theme.bodyLarge.override(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: isFollowRequest
                                  ? ' wants to follow you'
                                  : isPulseChat
                                      ? ' invited you to a pulse'
                                      : ' invited you to a group',
                              style: theme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      if (timeText.isNotEmpty)
                        Text(
                          timeText,
                          style: theme.bodySmall.override(
                            color: theme.secondaryText,
                          ),
                        ),
                    ],
                  ),
                ),
                // Type badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isFollowRequest
                        ? theme.tertiary.withOpacity(.1)
                        : isPulseChat
                            ? theme.primary.withOpacity(.1)
                            : theme.secondary.withOpacity(.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isFollowRequest
                            ? Icons.person_add_rounded
                            : isPulseChat
                                ? Icons.podcasts_rounded
                                : Icons.groups_rounded,
                        size: 12,
                        color: isFollowRequest
                            ? theme.tertiary
                            : isPulseChat
                                ? theme.primary
                                : theme.secondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isFollowRequest
                            ? 'FOLLOW'
                            : isPulseChat
                                ? 'PULSE'
                                : 'GROUP',
                        style: theme.bodySmall.override(
                          color: isFollowRequest
                              ? theme.tertiary
                              : isPulseChat
                                  ? theme.primary
                                  : theme.secondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Item card (Pulse, Group, or Follow Request Profile Info)
          if (!isFollowRequest)
            InkWell(
              onTap: isPulseChat && pulse?['id'] != null
                  ? () {
                      context.pushNamed(
                        'PulseDetail',
                        pathParameters: {'id': pulse['id'].toString()},
                      );
                    }
                  : null,
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isPulseChat
                      ? theme.primary.withOpacity(.05)
                      : theme.secondary.withOpacity(.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isPulseChat
                        ? theme.primary.withOpacity(.2)
                        : theme.secondary.withOpacity(.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    if (itemImageUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: itemImageUrl,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: isPulseChat
                              ? theme.primary.withOpacity(.2)
                              : theme.secondary.withOpacity(.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isPulseChat
                              ? Icons.podcasts_rounded
                              : Icons.groups_rounded,
                          color: isPulseChat ? theme.primary : theme.secondary,
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            itemName,
                            style: theme.bodyLarge.override(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (itemDescription != null)
                            Text(
                              itemDescription,
                              style: theme.bodySmall.override(
                                color: theme.secondaryText,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    if (isPulseChat)
                      Icon(
                        Icons.chevron_right_rounded,
                        color: theme.secondaryText,
                      ),
                  ],
                ),
              ),
            )
          else
            // Follow request profile info
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.tertiary.withOpacity(.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.tertiary.withOpacity(.2),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (inviterBio != null && inviterBio.isNotEmpty)
                          Text(
                            inviterBio,
                            style: theme.bodyMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.people_outline_rounded,
                              size: 16,
                              color: theme.secondaryText,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$followersCount followers',
                              style: theme.bodySmall.override(
                                color: theme.secondaryText,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '$followingCount following',
                              style: theme.bodySmall.override(
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
            ),

          // Action buttons
          if (isPending)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isResponding
                          ? null
                          : () => _respondToInvitation(
                                invitationId: invitationId,
                                accept: true,
                              ),
                      icon: isResponding
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded),
                      label: const Text('Accept'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isResponding
                          ? null
                          : () => _respondToInvitation(
                                invitationId: invitationId,
                                accept: false,
                              ),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Decline'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.error,
                        side: BorderSide(color: theme.error),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: status.toUpperCase() == 'ACCEPTED'
                      ? theme.success.withOpacity(.1)
                      : theme.error.withOpacity(.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      status.toUpperCase() == 'ACCEPTED'
                          ? Icons.check_circle_rounded
                          : Icons.cancel_rounded,
                      size: 16,
                      color: status.toUpperCase() == 'ACCEPTED'
                          ? theme.success
                          : theme.error,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      status.toUpperCase() == 'ACCEPTED'
                          ? 'Accepted'
                          : 'Declined',
                      style: theme.bodySmall.override(
                        color: status.toUpperCase() == 'ACCEPTED'
                            ? theme.success
                            : theme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
