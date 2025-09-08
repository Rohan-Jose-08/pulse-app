import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../backend/api_service.dart';
import '../../flutter_flow/flutter_flow_theme.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  static String routeName = 'Notifications';
  static String routePath = '/notifications';

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  Future<List<Map<String, dynamic>>?>? _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.instance.getNotifications();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = ApiService.instance.getNotifications();
    });
    await _future;
  }

  Future<void> _reloadList() async {
    setState(() {
      _future = ApiService.instance.getNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      appBar: AppBar(
        backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
        elevation: 0,
        title: Text(
          'Notifications',
          style: FlutterFlowTheme.of(context).titleLarge.override(
                font: GoogleFonts.interTight(
                  fontWeight: FontWeight.bold,
                ),
              ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.done_all_rounded),
            tooltip: 'Mark all as read',
            onPressed: () async {
              await ApiService.instance.markAllNotificationsRead();
              if (!mounted) return;
              await _reloadList();
            },
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Map<String, dynamic>>?>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: 6,
                itemBuilder: (_, __) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: FlutterFlowTheme.of(context).alternate,
                    child: Icon(Icons.notifications_rounded,
                        color: FlutterFlowTheme.of(context).secondaryText),
                  ),
                  title: Container(
                    height: 14,
                    color: FlutterFlowTheme.of(context).alternate,
                  ),
                  subtitle: Container(
                    height: 12,
                    margin: const EdgeInsets.only(top: 8),
                    color: FlutterFlowTheme.of(context).alternate,
                  ),
                ),
              );
            }
            final items = snapshot.data ?? const [];
            if (items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 80),
                  Icon(Icons.notifications_none_rounded,
                      size: 64,
                      color: FlutterFlowTheme.of(context).secondaryText),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'No notifications yet',
                      style: FlutterFlowTheme.of(context).titleMedium,
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: FlutterFlowTheme.of(context).alternate,
              ),
              itemBuilder: (context, index) {
                final n = items[index];
                final type = (n['type'] as String?) ?? 'Notification';
                final title = (n['title'] as String?) ?? '';
                final message = (n['message'] as String?) ?? '';
                final isRead = (n['isRead'] as bool?) ?? false;
                final createdAt =
                    DateTime.tryParse((n['createdAt'] ?? '') as String? ?? '');
                final timeText = createdAt != null ? _timeAgo(createdAt) : '';
                final icon = _iconForType(type);

                final isInvite = type.toLowerCase() == 'invite';
                final data = n['data'];
                final inviteStatus =
                    (data is Map ? (data['status']?.toString() ?? '') : '');
                final isInviteAccepted =
                    isInvite && inviteStatus.toUpperCase() == 'ACCEPTED';
                return InkWell(
                  onTap: () async {
                    final id = (n['id'] as String?) ?? '';
                    if (id.isNotEmpty) {
                      await ApiService.instance.markNotificationRead(id);
                    }
                    if (!mounted) return;
                    await _reloadList();
                  },
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            backgroundColor: isRead
                                ? FlutterFlowTheme.of(context)
                                    .secondaryBackground
                                : FlutterFlowTheme.of(context)
                                    .primary
                                    .withOpacity(0.15),
                            child: Icon(icon,
                                color: FlutterFlowTheme.of(context).primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Expanded(
                                      child: Text(title,
                                          style: FlutterFlowTheme.of(context)
                                              .titleSmall
                                              .override(
                                                font: GoogleFonts.interTight(
                                                    fontWeight:
                                                        FontWeight.w600),
                                              )),
                                    ),
                                    Text(timeText,
                                        style: FlutterFlowTheme.of(context)
                                            .labelSmall),
                                  ]),
                                  const SizedBox(height: 4),
                                  Text(
                                      isInviteAccepted && message.isEmpty
                                          ? 'You accepted this invitation'
                                          : message,
                                      style: FlutterFlowTheme.of(context)
                                          .bodySmall),
                                  if (isInvite && !isInviteAccepted) ...[
                                    const SizedBox(height: 8),
                                    _inviteActions(context, n),
                                  ]
                                ]),
                          )
                        ]),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  IconData _iconForType(String type) {
    switch (type.toLowerCase()) {
      case 'follow':
        return Icons.person_add_alt_1_rounded;
      case 'like':
        return Icons.favorite_rounded;
      case 'comment':
        return Icons.mode_comment_rounded;
      case 'pulse':
        return Icons.bolt_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Widget _inviteActions(BuildContext context, Map<String, dynamic> n) {
    final data = n['data'];
    final invitationId =
        (data is Map ? data['invitationId']?.toString() : null) ?? '';
    if (invitationId.isEmpty) return const SizedBox.shrink();
    return Row(children: [
      Expanded(
        child: OutlinedButton(
          onPressed: () async {
            await ApiService.instance.declineInvitation(invitationId);
            final id = (n['id'] as String?) ?? '';
            if (id.isNotEmpty)
              await ApiService.instance.markNotificationRead(id);
            if (!mounted) return;
            await _reloadList();
          },
          child: const Text('Decline'),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: ElevatedButton(
          onPressed: () async {
            final ok = await ApiService.instance.acceptInvitation(invitationId);
            if (ok) {
              final id = (n['id'] as String?) ?? '';
              if (id.isNotEmpty)
                await ApiService.instance.markNotificationRead(id);
              // TODO: optionally navigate directly to the conversation
            }
            if (!mounted) return;
            await _reloadList();
          },
          child: const Text('Join'),
        ),
      ),
    ]);
  }
}
