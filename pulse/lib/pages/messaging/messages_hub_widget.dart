import '/flutter_flow/flutter_flow_theme.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '/components/navbar_widget.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/firebase_auth/auth_util.dart';
import '../../backend/api_service.dart';
import '../../backend/socket_service.dart';
import 'enhanced_messaging_page.dart';
import 'live_group_chat_page.dart';
import 'group_chat_page.dart';
import 'create_group_chat_page.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'dart:async';

class MessagesHubWidget extends StatefulWidget {
  const MessagesHubWidget({super.key});

  static String routeName = 'messages';
  static String routePath = '/messages';

  @override
  State<MessagesHubWidget> createState() => _MessagesHubWidgetState();
}

final _conversationsProvider = StreamProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, uid) {
  final controller = StreamController<List<Map<String, dynamic>>>();
  List<Map<String, dynamic>> items = [];
  DateTime _lastReload = DateTime.fromMillisecondsSinceEpoch(0);

  List<Map<String, dynamic>> _normalize(List<Map<String, dynamic>> raw) {
    // Ensure consistent sorting (most recent updatedAt desc)
    raw.sort((a, b) {
      final ta = DateTime.tryParse(a['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final tb = DateTime.tryParse(b['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return raw;
  }

  Future<void> _load({bool silent = false}) async {
    try {
      // Prefer strict direct conversations endpoint
      List<Map<String, dynamic>>? list =
          await ApiService.instance.listDirectConversations();

      // Fallback: if the direct endpoint is unavailable or returns empty,
      // fall back to the general conversations list and let the UI filter.
      if (list == null || list.isEmpty) {
        if (!silent) {
          // ignore: avoid_print
          print(
              '[DMProvider] direct endpoint returned ${list == null ? 'null' : 'empty'}; falling back to /conversations');
        }
        final all = await ApiService.instance.listConversations();
        list = all;
      }

      // Keep all; UI separates DMs vs group/pulse deterministically
      final convs = (list ?? []).whereType<Map<String, dynamic>>().toList();
      items =
          _normalize(convs.map((c) => Map<String, dynamic>.from(c)).toList());
      _lastReload = DateTime.now();
      controller.add(items);
      // Debug: counts
      // ignore: avoid_print
      if (!silent) {
        print('[DMProvider] loaded total=' + (list?.length.toString() ?? '0'));
      }
    } catch (e) {
      if (!silent) {
        // ignore: avoid_print
        print('Conversations load error: $e');
      }
    }
  }

  _load();
  final sub = SocketService.instance.conversationUpdates
      .listen((_) => _load(silent: true));
  final subMsg = SocketService.instance.messages.listen((msg) {
    try {
      final cid = msg['conversationId']?.toString();
      if (cid == null) return;
      final idx = items.indexWhere((c) => c['id']?.toString() == cid);
      if (idx != -1) {
        items[idx]['lastMessageText'] =
            msg['text']?.toString() ?? items[idx]['lastMessageText'];
        items[idx]['updatedAt'] =
            msg['createdAt']?.toString() ?? DateTime.now().toIso8601String();
        // Re-sort
        items = List<Map<String, dynamic>>.from(items);
        items.sort((a, b) {
          final ta = DateTime.tryParse(a['updatedAt']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final tb = DateTime.tryParse(b['updatedAt']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return tb.compareTo(ta);
        });
        controller.add(items);
      } else {
        // Unknown conversation; throttle reloads to avoid frequent refreshes from group chat traffic
        final now = DateTime.now();
        if (now.difference(_lastReload).inMilliseconds > 1200) {
          _load(silent: true);
        }
      }
    } catch (_) {}
  });

  ref.onDispose(() {
    sub.cancel();
    subMsg.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Group conversations stream (standalone group chats not tied to pulses)
final _groupConversationsProvider = StreamProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, uid) {
  final controller = StreamController<List<Map<String, dynamic>>>();
  List<Map<String, dynamic>> items = [];
  DateTime _lastReload = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _load({bool silent = false}) async {
    try {
      final list = await ApiService.instance.listGroupConversations();
      final allItems = (list ?? []).whereType<Map<String, dynamic>>().toList();

      // Deduplicate by conversation ID
      final seenIds = <String>{};
      items = allItems.where((c) {
        final id = c['id']?.toString();
        if (id == null || id.isEmpty)
          return true; // Keep items without IDs just in case
        if (seenIds.contains(id)) return false;
        seenIds.add(id);
        return true;
      }).toList();

      items.sort((a, b) {
        final ta = DateTime.tryParse(a['updatedAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final tb = DateTime.tryParse(b['updatedAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return tb.compareTo(ta);
      });
      _lastReload = DateTime.now();
      controller.add(items);
      if (!silent) {
        print(
            '[GroupChats] loaded ${items.length} group conversations (${allItems.length} before dedup)');
      }
    } catch (e) {
      if (!silent) {
        print('Group conversations load error: $e');
      }
    }
  }

  _load();
  final sub = SocketService.instance.conversationUpdates
      .listen((_) => _load(silent: true));
  final subMsg = SocketService.instance.messages.listen((msg) {
    try {
      final cid = msg['conversationId']?.toString();
      if (cid == null) return;
      final idx = items.indexWhere((c) => c['id']?.toString() == cid);
      if (idx != -1) {
        items[idx]['lastMessageText'] =
            msg['text']?.toString() ?? items[idx]['lastMessageText'];
        items[idx]['updatedAt'] =
            msg['createdAt']?.toString() ?? DateTime.now().toIso8601String();
        items = List<Map<String, dynamic>>.from(items);

        // Deduplicate after update (in case message triggered a duplicate)
        final seenIds = <String>{};
        items = items.where((c) {
          final id = c['id']?.toString();
          if (id == null || id.isEmpty) return true;
          if (seenIds.contains(id)) return false;
          seenIds.add(id);
          return true;
        }).toList();

        items.sort((a, b) {
          final ta = DateTime.tryParse(a['updatedAt']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final tb = DateTime.tryParse(b['updatedAt']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return tb.compareTo(ta);
        });
        controller.add(items);
      } else {
        final now = DateTime.now();
        if (now.difference(_lastReload).inMilliseconds > 1200) {
          _load(silent: true);
        }
      }
    } catch (_) {}
  });

  ref.onDispose(() {
    sub.cancel();
    subMsg.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Pulse group chat conversations stream. "Re-enabled" by broadening
/// detection logic for conversations associated with a Pulse.
/// Backends might use different keys; we accept several fallbacks.
final _pulseConversationsProvider = StreamProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, uid) {
  final controller = StreamController<List<Map<String, dynamic>>>();
  List<Map<String, dynamic>> items = [];

  bool isPulseGroup(Map<String, dynamic> conv) {
    // Backend guarantees pulseId for pulse group conversations
    if (conv['pulseId'] != null && conv['pulseId'].toString().isNotEmpty) {
      return true;
    }
    return false;
  }

  (() async {
    final list = await ApiService.instance.listPulseConversations();
    final pulseGroupList = (list ?? []).where(isPulseGroup).toList();

    // Debug: Log all IDs before dedup
    print(
        '[PulseChats] RAW IDs from API: ${list?.map((c) => c['id']).toList()}');
    print(
        '[PulseChats] After isPulseGroup filter: ${pulseGroupList.map((c) => c['id']).toList()}');

    // Filter out conversations with no messages (empty auto-created pulse chats)
    final withMessages = pulseGroupList.where((c) {
      final lastMessage = c['lastMessageText']?.toString();
      return lastMessage != null && lastMessage.isNotEmpty;
    }).toList();

    // Deduplicate by conversation ID
    final seenIds = <String>{};
    final duplicates = <String>[];
    items = withMessages.where((c) {
      final id = c['id']?.toString();
      if (id == null || id.isEmpty) return false;
      if (seenIds.contains(id)) {
        duplicates.add(id);
        return false;
      }
      seenIds.add(id);
      return true;
    }).toList();

    // Debug: counts
    // ignore: avoid_print
    print(
        '[PulseChats] total=${list?.length ?? 0} pulseGroups=${pulseGroupList.length} afterDedup=${items.length}');
    if (duplicates.isNotEmpty) {
      print(
          '[PulseChats] ⚠️ REMOVED ${duplicates.length} duplicates: $duplicates');
    }
    if (items.isEmpty && (list?.isNotEmpty ?? false)) {
      final withPulseField =
          (list ?? []).where((c) => c['pulseId'] != null).take(3).toList();
      // ignore: avoid_print
      print('[PulseChats] first3WithPulseId=' + withPulseField.toString());
      if (withPulseField.isEmpty) {
        // ignore: avoid_print
        print('[PulseChats] No pulseId present in any conversation objects.');
      }
    }
    controller.add(items);
  })();

  final sub = SocketService.instance.conversationUpdates.listen((_) async {
    final list = await ApiService.instance.listPulseConversations();
    final pulseGroupList = (list ?? []).where(isPulseGroup).toList();

    // Filter out conversations with no messages (empty auto-created pulse chats)
    final withMessages = pulseGroupList.where((c) {
      final lastMessage = c['lastMessageText']?.toString();
      return lastMessage != null && lastMessage.isNotEmpty;
    }).toList();

    // Deduplicate by conversation ID
    final seenIds = <String>{};
    items = withMessages.where((c) {
      final id = c['id']?.toString();
      if (id == null || id.isEmpty) return false;
      if (seenIds.contains(id)) return false;
      seenIds.add(id);
      return true;
    }).toList();

    controller.add(items);
  });

  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });

  return controller.stream;
});

class _MessagesHubWidgetState extends State<MessagesHubWidget> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Activity status tracking
  final Map<String, String> _userStatuses = {}; // userId -> status
  StreamSubscription? _statusSubscription;
  StreamSubscription? _gcStartedSub;
  StreamSubscription? _gcStoppedSub;
  StreamSubscription? _gcParticipantsSub;
  StreamSubscription? _gcStatusSub;
  StreamSubscription? _gcAllStatusSub;
  final Set<String> _activeCalls = <String>{};
  final Map<String, bool> _activeCallIsVideo = <String, bool>{};
  final Map<String, int> _activeCallParticipantCounts = <String, int>{};

  @override
  void initState() {
    super.initState();
    _listenToStatusChanges();
    _listenToGroupCalls();
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _gcStartedSub?.cancel();
    _gcStoppedSub?.cancel();
    _gcParticipantsSub?.cancel();
    _gcStatusSub?.cancel();
    _gcAllStatusSub?.cancel();
    super.dispose();
  }

  /// Listen for real-time activity status updates
  void _listenToStatusChanges() {
    _statusSubscription =
        SocketService.instance.userStatusChanged.listen((data) {
      final userId = data['userId'] as String?;
      final status = data['status'] as String?;
      if (userId != null && status != null) {
        setState(() {
          _userStatuses[userId] = status;
        });
      }
    });
  }

  /// Global listener for group call start events
  void _listenToGroupCalls() {
    print('[MessagesHub] Setting up group call listeners');
    _gcStartedSub = SocketService.instance.groupCallStarted.listen((m) async {
      try {
        print('[MessagesHub] groupCallStarted event received: $m');
        final cid = m['conversationId']?.toString();
        if (cid == null || cid.isEmpty) return;
        final isVideo = m['isVideo'] == true;
        if (mounted) {
          setState(() {
            print('[MessagesHub] Adding call from groupCallStarted: $cid');
            print('[MessagesHub] setState called - widget should rebuild');
            _activeCalls.add(cid);
            _activeCallIsVideo[cid] = isVideo;
          });
        }
      } catch (e) {
        print('[MessagesHub] Error in groupCallStarted: $e');
      }
    });

    _gcStoppedSub = SocketService.instance.groupCallStopped.listen((m) async {
      try {
        final cid = m['conversationId']?.toString();
        if (cid == null || cid.isEmpty) return;
        if (mounted) {
          setState(() {
            _activeCalls.remove(cid);
            _activeCallIsVideo.remove(cid);
            _activeCallParticipantCounts.remove(cid);
          });
        }
      } catch (_) {}
    });

    _gcParticipantsSub =
        SocketService.instance.groupCallParticipants.listen((m) async {
      try {
        final cid = m['conversationId']?.toString();
        if (cid == null || cid.isEmpty) return;
        final list = (m['participants'] as List?) ?? const [];
        if (mounted) {
          setState(() {
            _activeCallParticipantCounts[cid] = list.length;
            if (list.isNotEmpty) _activeCalls.add(cid);
          });
        }
      } catch (_) {}
    });

    // Listen for call status updates (sent when app starts or joins conversation)
    _gcStatusSub = SocketService.instance.groupCallStatus.listen((m) async {
      try {
        final cid = m['conversationId']?.toString();
        if (cid == null || cid.isEmpty) return;
        final isActive = m['isActive'] == true;
        final isVideo = m['isVideo'] == true;
        final participants = (m['participants'] as List?)?.cast<String>() ?? [];

        if (mounted && isActive) {
          setState(() {
            _activeCalls.add(cid);
            _activeCallIsVideo[cid] = isVideo;
            _activeCallParticipantCounts[cid] = participants.length;
          });
        }
      } catch (_) {}
    });

    // Listen for bulk status updates (sent when app requests all call statuses)
    _gcAllStatusSub =
        SocketService.instance.groupCallAllStatus.listen((response) async {
      try {
        final activeCalls = (response['activeCalls'] as List?) ?? [];
        if (mounted) {
          setState(() {
            for (final callData in activeCalls) {
              if (callData is! Map<String, dynamic>) continue;
              final cid = callData['conversationId']?.toString();
              if (cid == null || cid.isEmpty) continue;
              final isActive = callData['isActive'] == true;
              final isVideo = callData['isVideo'] == true;
              final participants =
                  (callData['participants'] as List?)?.cast<String>() ?? [];

              if (isActive) {
                print(
                    '[MessagesHub] Adding active call for conversation $cid with ${participants.length} participants');
                _activeCalls.add(cid);
                _activeCallIsVideo[cid] = isVideo;
                _activeCallParticipantCounts[cid] = participants.length;
              }
            }
            print(
                '[MessagesHub] Current _activeCalls after update: $_activeCalls');
          });
        }
      } catch (e) {
        print('[MessagesHub] Error processing groupCallAllStatus: $e');
      }
    });

    // Request all call statuses after a short delay to ensure socket is connected
    print('[MessagesHub] Requesting all call statuses...');
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        print('[MessagesHub] Delayed request for all call statuses');
        SocketService.instance.requestAllCallStatuses();
      }
    });
  }

  /// Load activity statuses for a list of user IDs
  Future<void> _loadActivityStatuses(List<String> userIds) async {
    if (userIds.isEmpty) return;

    final statuses = await ApiService.instance.getActivityStatuses(userIds);
    if (statuses != null && mounted) {
      setState(() {
        statuses.forEach((userId, statusData) {
          if (statusData != null) {
            _userStatuses[userId] = statusData['status'];
          }
        });
      });
    }
  }

  /// Build a status indicator widget
  Widget _buildStatusIndicator(String? status) {
    if (status == null) return const SizedBox.shrink();

    Color color;
    switch (status) {
      case 'online':
        color = Colors.green;
        break;
      case 'away':
        color = Colors.orange;
        break;
      case 'offline':
      default:
        return const SizedBox.shrink(); // Don't show indicator for offline
    }

    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }

  Widget _buildPulseGroupChatTile(BuildContext context,
      Map<String, dynamic> data, FlutterFlowTheme theme, String uid) {
    final chatName = data['name']?.toString() ?? 'Pulse Group Chat';
    final lastMessage = (data['lastMessageText'] as String?) ?? '';
    final updatedAt = DateTime.tryParse(data['updatedAt']?.toString() ?? '');
    final pulseId = data['pulseId']?.toString() ?? '';

    // Get participant count
    final List<dynamic> participants =
        (data['participants'] as List<dynamic>? ?? []);
    final participantCount = participants.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.primary.withOpacity(0.2), width: 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Stack(
          children: [
            CircleAvatar(
              backgroundColor: theme.primary.withOpacity(0.1),
              child: Icon(
                Icons.group_rounded,
                color: theme.primary,
                size: 24,
              ),
            ),
            // Ongoing call indicator (non-intrusive)
            if (_activeCalls.contains(data['id']?.toString()))
              Positioned(
                top: -2,
                left: -2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: theme.secondaryBackground, width: 2),
                  ),
                  child: Icon(
                    _activeCallIsVideo[data['id']?.toString()] == true
                        ? Icons.videocam_rounded
                        : Icons.call_rounded,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
            if (participantCount > 0)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: theme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 20,
                    minHeight: 20,
                  ),
                  child: Text(
                    participantCount.toString(),
                    style: theme.bodySmall.override(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          chatName,
          style: theme.titleMedium.override(fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Active call status (Discord-style)
            if (_activeCalls.contains(data['id']?.toString()))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color:
                            (_activeCallIsVideo[data['id']?.toString()] == true
                                    ? Colors.purple
                                    : Colors.green)
                                .withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              _activeCallIsVideo[data['id']?.toString()] == true
                                  ? Colors.purple
                                  : Colors.green,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _activeCallIsVideo[data['id']?.toString()] == true
                                ? Icons.videocam_rounded
                                : Icons.call_rounded,
                            size: 14,
                            color: _activeCallIsVideo[data['id']?.toString()] ==
                                    true
                                ? Colors.purple
                                : Colors.green,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _activeCallParticipantCounts[
                                        data['id']?.toString()] !=
                                    null
                                ? '${_activeCallParticipantCounts[data['id']?.toString()]} in call'
                                : 'Call active',
                            style: theme.bodySmall.override(
                              color:
                                  _activeCallIsVideo[data['id']?.toString()] ==
                                          true
                                      ? Colors.purple
                                      : Colors.green,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Tap to join',
                      style: theme.bodySmall.override(
                        color: theme.secondaryText.withOpacity(0.7),
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            if (pulseId.isNotEmpty)
              Text(
                'Pulse Group • $participantCount members',
                style: theme.bodySmall.override(
                  color: theme.primary,
                  fontSize: 12,
                ),
              ),
            const SizedBox(height: 2),
            Text(
              lastMessage.isNotEmpty
                  ? lastMessage
                  : 'Start chatting with your pulse group! 🚀',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.bodySmall.override(color: theme.secondaryText),
            ),
          ],
        ),
        trailing: updatedAt != null
            ? Text(
                dateTimeFormat('relative', updatedAt),
                style: theme.bodySmall.override(color: theme.secondaryText),
              )
            : null,
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => LiveGroupChatPage(
                    chatId: data['id']?.toString() ?? '',
                    groupName: chatName,
                    pulseName: pulseId.isNotEmpty ? pulseId : null,
                    members: participants
                        .whereType<Map<String, dynamic>>()
                        .map((e) => e)
                        .toList(),
                  )));
        },
      ),
    );
  }

  Widget _buildGroupChatTile(BuildContext context, Map<String, dynamic> data,
      FlutterFlowTheme theme, String uid) {
    final chatName = data['name']?.toString() ?? 'Group Chat';
    final description = data['description']?.toString();
    final lastMessage = (data['lastMessageText'] as String?) ?? '';
    final updatedAt = DateTime.tryParse(data['updatedAt']?.toString() ?? '');
    final avatarUrl = data['avatarUrl']?.toString();

    // Get participant count
    final List<dynamic> participants =
        (data['participants'] as List<dynamic>? ?? []);
    final participantCount = participants.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accent2.withOpacity(0.3), width: 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Stack(
          children: [
            CircleAvatar(
              backgroundColor: theme.accent2.withOpacity(0.1),
              backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                  ? NetworkImage(avatarUrl)
                  : null,
              child: avatarUrl == null || avatarUrl.isEmpty
                  ? Icon(
                      Icons.people,
                      color: theme.accent2,
                      size: 24,
                    )
                  : null,
            ),
            // Ongoing call indicator (non-intrusive)
            if (_activeCalls.contains(data['id']?.toString()))
              Positioned(
                top: -2,
                left: -2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: theme.secondaryBackground, width: 2),
                  ),
                  child: Icon(
                    _activeCallIsVideo[data['id']?.toString()] == true
                        ? Icons.videocam_rounded
                        : Icons.call_rounded,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
            if (participantCount > 0)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: theme.accent2,
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: theme.secondaryBackground, width: 2),
                  ),
                  constraints:
                      const BoxConstraints(minWidth: 20, minHeight: 20),
                  child: Center(
                    child: Text(
                      participantCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          chatName,
          style: theme.titleSmall.override(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Active call status (Discord-style)
            if (_activeCalls.contains(data['id']?.toString()))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color:
                            (_activeCallIsVideo[data['id']?.toString()] == true
                                    ? Colors.purple
                                    : Colors.green)
                                .withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              _activeCallIsVideo[data['id']?.toString()] == true
                                  ? Colors.purple
                                  : Colors.green,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _activeCallIsVideo[data['id']?.toString()] == true
                                ? Icons.videocam_rounded
                                : Icons.call_rounded,
                            size: 14,
                            color: _activeCallIsVideo[data['id']?.toString()] ==
                                    true
                                ? Colors.purple
                                : Colors.green,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _activeCallParticipantCounts[
                                        data['id']?.toString()] !=
                                    null
                                ? '${_activeCallParticipantCounts[data['id']?.toString()]} in call'
                                : 'Call active',
                            style: theme.bodySmall.override(
                              color:
                                  _activeCallIsVideo[data['id']?.toString()] ==
                                          true
                                      ? Colors.purple
                                      : Colors.green,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Tap to join',
                      style: theme.bodySmall.override(
                        color: theme.secondaryText.withOpacity(0.7),
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            if (description != null && description.isNotEmpty)
              Text(
                description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.bodySmall.override(
                  color: theme.secondaryText,
                  fontSize: 11,
                ),
              ),
            Text(
              lastMessage.isNotEmpty ? lastMessage : 'No messages yet',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.bodySmall.override(color: theme.secondaryText),
            ),
          ],
        ),
        trailing: updatedAt != null
            ? Text(
                dateTimeFormat('relative', updatedAt),
                style: theme.bodySmall.override(color: theme.secondaryText),
              )
            : null,
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => GroupChatPage(
                    chatId: data['id']?.toString() ?? '',
                    groupName: chatName,
                    groupDescription: description,
                    groupAvatarUrl: avatarUrl,
                    members: participants
                        .whereType<Map<String, dynamic>>()
                        .map((e) => e)
                        .toList(),
                  )));
        },
      ),
    );
  }

  Widget _buildDirectChatTile(BuildContext context, Map<String, dynamic> data,
      FlutterFlowTheme theme, String uid) {
    // Participants may be under participants/members/users
    List<dynamic> participants = (data['participants'] as List?) ?? [];
    if (participants.isEmpty) participants = (data['members'] as List?) ?? [];
    if (participants.isEmpty) participants = (data['users'] as List?) ?? [];

    Map<String, dynamic> _normalizeUser(dynamic u) {
      if (u is Map<String, dynamic>) return u;
      return <String, dynamic>{};
    }

    String _userId(Map<String, dynamic> u) =>
        (u['id'] ?? u['userId'] ?? u['uid'] ?? '').toString();
    String _userPhoto(Map<String, dynamic> u) => (u['profileImageUrl'] ??
            u['photoUrl'] ??
            u['avatar'] ??
            u['imageUrl'] ??
            '')
        .toString();
    String _userName(Map<String, dynamic> u) {
      final first = (u['firstName'] ?? u['first_name'])?.toString();
      final last = (u['lastName'] ?? u['last_name'])?.toString();
      final combined =
          [first, last].where((e) => e != null && e.isNotEmpty).join(' ');
      return (u['displayName'] ??
              u['fullName'] ??
              u['username'] ??
              u['name'] ??
              combined)
          .toString();
    }

    final normalized =
        participants.map(_normalizeUser).where((m) => m.isNotEmpty).toList();
    Map<String, dynamic> other = <String, dynamic>{};
    for (final p in normalized) {
      if (_userId(p) != uid) {
        other = p;
        break;
      }
    }
    final otherId = _userId(other);
    final convoTitleFallback =
        (data['title'] ?? data['name'] ?? data['displayName'] ?? '').toString();
    final otherNameRaw = _userName(other);
    final otherName = otherNameRaw.isNotEmpty
        ? otherNameRaw
        : (convoTitleFallback.isNotEmpty ? convoTitleFallback : 'Unknown');
    final otherPhoto = _userPhoto(other).isNotEmpty
        ? _userPhoto(other)
        : (data['avatar'] ?? data['photoUrl'] ?? data['imageUrl'] ?? '')
            .toString();

    // last message fallback keys
    String lastMessage = (data['lastMessageText'] ??
                data['lastMessage'] ??
                data['last_message'] ??
                '')
            ?.toString() ??
        '';
    // message object maybe nested
    if (lastMessage.isEmpty && data['lastMessageObj'] is Map) {
      lastMessage = (data['lastMessageObj']['text'] ?? '').toString();
    }
    final updatedAt = DateTime.tryParse(data['updatedAt']?.toString() ?? '') ??
        DateTime.tryParse(data['lastActivityAt']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);

    // Load status for this user if we don't have it
    if (otherId.isNotEmpty && !_userStatuses.containsKey(otherId)) {
      _loadActivityStatuses([otherId]);
    }

    final userStatus = _userStatuses[otherId];

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundImage:
                otherPhoto.isNotEmpty ? NetworkImage(otherPhoto) : null,
            child: otherPhoto.isEmpty ? const Icon(Icons.person) : null,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: _buildStatusIndicator(userStatus),
          ),
        ],
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              otherName,
              style: theme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (userStatus == 'online')
            Container(
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Active',
                style: theme.bodySmall.override(
                  color: Colors.green,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      subtitle: Text(
        lastMessage.isNotEmpty ? lastMessage : 'Say hi 👋',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        dateTimeFormat('relative', updatedAt),
        style: theme.bodySmall.override(color: theme.secondaryText),
      ),
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => EnhancedMessagingPage(
                  chatId: data['id']?.toString() ?? '',
                  recipientUserId: otherId,
                  recipientName: otherName,
                  recipientPhotoUrl: otherPhoto,
                )));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final uid = currentUserUid;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.secondaryBackground,
        elevation: 0.5,
        title: Text(
          'Messages',
          style: theme.titleLarge,
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: uid.isEmpty
            ? Center(
                child: Text(
                  'Please log in to view messages',
                  style: theme.bodyMedium.override(color: theme.secondaryText),
                ),
              )
            : Consumer(builder: (context, ref, _) {
                SocketService.instance.connect();
                final asyncConvos = ref.watch(_conversationsProvider(uid));
                final asyncPulseConvos =
                    ref.watch(_pulseConversationsProvider(uid));
                final asyncGroupConvos =
                    ref.watch(_groupConversationsProvider(uid));

                return asyncConvos.when(
                  data: (directChats) {
                    return asyncPulseConvos.when(
                      data: (pulseChats) {
                        return asyncGroupConvos.when(
                          data: (groupChats) {
                            // Filter direct chats with robust classification
                            final pulseIds = pulseChats
                                .map((c) => c['id']?.toString())
                                .whereType<String>()
                                .toSet();

                            bool hasPulseMarker(Map<String, dynamic> conv) => [
                                  'pulseId',
                                  'pulse_id',
                                  'pulseID',
                                  'pulse',
                                  'pulseUuid'
                                ].any((k) =>
                                    conv[k] != null &&
                                    conv[k].toString().isNotEmpty);

                            List<dynamic> _parts(Map<String, dynamic> c) =>
                                (c['participants'] as List?) ??
                                (c['members'] as List?) ??
                                (c['users'] as List?) ??
                                const [];

                            bool isLikelyDirect(Map<String, dynamic> conv) {
                              // Hard exclusions: any pulse-linked or group conversation is NOT a DM
                              if (conv['isGroup'] == true) return false;
                              if (hasPulseMarker(conv)) return false;
                              final id = conv['id']?.toString();
                              if (id != null && pulseIds.contains(id))
                                return false;
                              // If it passes the exclusions above, treat it as a DM
                              return true;
                            }

                            final filteredDirectChats =
                                directChats.where(isLikelyDirect).toList();

                            // Fallback 1: exactly two participants
                            List<Map<String, dynamic>> fallbackTwoParticipant =
                                [];
                            if (filteredDirectChats.isEmpty) {
                              fallbackTwoParticipant = directChats
                                  .where((c) {
                                    // Exclude pulse/groups even in fallback
                                    if (hasPulseMarker(c)) return false;
                                    if (c['isGroup'] == true) return false;
                                    final id = c['id']?.toString();
                                    if (id != null && pulseIds.contains(id))
                                      return false;
                                    final parts = _parts(c);
                                    return parts.length ==
                                        2; // treat as direct fallback
                                  })
                                  .map((e) => Map<String, dynamic>.from(e))
                                  .toList();
                            }

                            // Fallback 2: any non-pulse conversation that is not flagged as group
                            List<Map<String, dynamic>>
                                fallbackNonPulseNonGroup = [];
                            if (filteredDirectChats.isEmpty &&
                                fallbackTwoParticipant.isEmpty &&
                                directChats.isNotEmpty) {
                              fallbackNonPulseNonGroup = directChats
                                  .where((c) {
                                    if (hasPulseMarker(c)) return false;
                                    if (c['isGroup'] == true) return false;
                                    final id = c['id']?.toString();
                                    if (id != null && pulseIds.contains(id))
                                      return false;
                                    return true;
                                  })
                                  .map((e) => Map<String, dynamic>.from(e))
                                  .toList();
                            }

                            final displayDirectChats =
                                filteredDirectChats.isNotEmpty
                                    ? filteredDirectChats
                                    : (fallbackTwoParticipant.isNotEmpty
                                        ? fallbackTwoParticipant
                                        : fallbackNonPulseNonGroup);

                            if (displayDirectChats.isEmpty &&
                                directChats.isNotEmpty) {
                              // Diagnostic logs (compact)
                              // ignore: avoid_print
                              print(
                                  '[DM-DIAG] No DMs after all fallbacks. totalConvos=' +
                                      directChats.length.toString());
                              for (final c in directChats.take(2)) {
                                try {
                                  final id = (c['id'] ?? '').toString();
                                  final typeField =
                                      (c['type'] ?? c['conversationType'])
                                          ?.toString();
                                  final isGroup = c['isGroup'];
                                  final pulseMarker = hasPulseMarker(c);
                                  final partsLen = _parts(c).length;
                                  print('[DM-DIAG] id=' +
                                      id +
                                      ' type=' +
                                      (typeField ?? '') +
                                      ' isGroup=' +
                                      (isGroup?.toString() ?? 'null') +
                                      ' pulse=' +
                                      pulseMarker.toString() +
                                      ' participants=' +
                                      partsLen.toString());
                                } catch (_) {
                                  // ignore
                                }
                              }
                            }

                            if (displayDirectChats.isEmpty &&
                                pulseChats.isEmpty &&
                                groupChats.isEmpty) {
                              return Center(
                                child: Text(
                                  'No conversations yet',
                                  style: theme.bodyMedium
                                      .override(color: theme.secondaryText),
                                ),
                              );
                            }

                            // Join socket rooms for all visible conversations so we receive
                            // room-scoped events (e.g., groupcall:started) while on the hub.
                            try {
                              final idsToJoin = <String>{
                                ...groupChats
                                    .map((c) => c['id']?.toString())
                                    .whereType<String>()
                                    .where((s) => s.isNotEmpty),
                                ...pulseChats
                                    .map((c) => c['id']?.toString())
                                    .whereType<String>()
                                    .where((s) => s.isNotEmpty),
                                ...displayDirectChats
                                    .map((c) => c['id']?.toString())
                                    .whereType<String>()
                                    .where((s) => s.isNotEmpty),
                              };
                              // Fire-and-forget; SocketService will dedupe room joins.
                              for (final id in idsToJoin) {
                                SocketService.instance.joinConversation(id);
                              }
                            } catch (_) {}

                            // Debug: Check if any active calls are missing from the conversation list
                            final allConvoIds = <String>{
                              ...groupChats
                                  .map((c) => c['id']?.toString())
                                  .whereType<String>(),
                              ...pulseChats
                                  .map((c) => c['id']?.toString())
                                  .whereType<String>(),
                              ...displayDirectChats
                                  .map((c) => c['id']?.toString())
                                  .whereType<String>(),
                            };
                            final missingCallConvos = _activeCalls
                                .where(
                                    (callId) => !allConvoIds.contains(callId))
                                .toSet();
                            if (missingCallConvos.isNotEmpty) {
                              print(
                                  '[MessagesHub] ⚠️ WARNING: Active calls in conversations NOT in hub: $missingCallConvos');
                              print(
                                  '[MessagesHub] This means the API endpoints are not returning these conversations');
                            }

                            print(
                                '[MessagesHub] Building ListView with _activeCalls: $_activeCalls');
                            return ListView(
                              key: ValueKey(_activeCalls.join('_')),
                              children: [
                                // Group Chats Section
                                if (groupChats.isNotEmpty) ...[
                                  Container(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 16, 16, 8),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.people,
                                          color: theme.accent2,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Group Chats',
                                          style: theme.titleMedium.override(
                                            fontWeight: FontWeight.w600,
                                            color: theme.accent2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ...groupChats.map((data) =>
                                      _buildGroupChatTile(
                                          context, data, theme, uid)),
                                  if (pulseChats.isNotEmpty ||
                                      displayDirectChats.isNotEmpty)
                                    Divider(height: 24, color: theme.alternate),
                                ],

                                // Pulse Group Chats Section
                                if (pulseChats.isNotEmpty) ...[
                                  Container(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 16, 16, 8),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.group_rounded,
                                          color: theme.primary,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Pulse Group Chats',
                                          style: theme.titleMedium.override(
                                            fontWeight: FontWeight.w600,
                                            color: theme.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ...pulseChats.map((data) =>
                                      _buildPulseGroupChatTile(
                                          context, data, theme, uid)),
                                  if (displayDirectChats.isNotEmpty)
                                    Divider(height: 24, color: theme.alternate),
                                ],

                                // Direct Messages Section
                                if (displayDirectChats.isNotEmpty) ...[
                                  Container(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 16, 16, 8),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.chat_rounded,
                                          color: theme.secondaryText,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Direct Messages',
                                          style: theme.titleMedium.override(
                                            fontWeight: FontWeight.w600,
                                            color: theme.secondaryText,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ...displayDirectChats.map((data) =>
                                      _buildDirectChatTile(
                                          context, data, theme, uid)),
                                ],
                              ],
                            );
                          },
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (_, __) => Center(
                            child: Text(
                              'Failed to load group conversations',
                              style: theme.bodyMedium
                                  .override(color: theme.secondaryText),
                            ),
                          ),
                        );
                      },
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, __) => Center(
                        child: Text(
                          'Failed to load pulse conversations',
                          style: theme.bodyMedium
                              .override(color: theme.secondaryText),
                        ),
                      ),
                    );
                  },
                  loading: () => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  error: (_, __) => Center(
                    child: Text(
                      'Failed to load conversations',
                      style:
                          theme.bodyMedium.override(color: theme.secondaryText),
                    ),
                  ),
                );
              }),
      ),
      floatingActionButton: uid.isEmpty
          ? null
          : _CreateMessageFab(
              onNewMessage: () async {
                await showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor:
                      FlutterFlowTheme.of(context).secondaryBackground,
                  shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  builder: (ctx) => const _NewMessageSheet(),
                );
              },
              onFindNearby: () async {
                await showDialog(
                  context: context,
                  builder: (ctx) => const _NearbyUsersDialog(),
                );
              },
              onCreateGroup: () async {
                final result = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CreateGroupChatPage(),
                  ),
                );
                if (result != null && context.mounted) {
                  setState(() {});
                }
              },
            ),
      bottomNavigationBar: const NavbarWidget(),
    );
  }
}

class _CreateMessageFab extends StatefulWidget {
  const _CreateMessageFab({
    required this.onNewMessage,
    required this.onFindNearby,
    required this.onCreateGroup,
  });

  final VoidCallback onNewMessage;
  final VoidCallback onFindNearby;
  final VoidCallback onCreateGroup;

  @override
  State<_CreateMessageFab> createState() => _CreateMessageFabState();
}

class _CreateMessageFabState extends State<_CreateMessageFab>
    with SingleTickerProviderStateMixin {
  bool _isOpen = false;

  void _toggle() {
    setState(() {
      _isOpen = !_isOpen;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Speed dial options
        if (_isOpen) ...[
          _buildOption(
            label: 'New group',
            icon: Icons.group_add,
            onTap: () {
              _toggle();
              widget.onCreateGroup();
            },
            backgroundColor: theme.accent2,
          ),
          const SizedBox(height: 12),
          _buildOption(
            label: 'Find nearby',
            icon: Icons.radar_rounded,
            onTap: () {
              _toggle();
              widget.onFindNearby();
            },
          ),
          const SizedBox(height: 12),
          _buildOption(
            label: 'New message',
            icon: Icons.chat_bubble_outline_rounded,
            onTap: () {
              _toggle();
              widget.onNewMessage();
            },
          ),
          const SizedBox(height: 12),
        ],
        // Main FAB
        FloatingActionButton(
          onPressed: _toggle,
          child: AnimatedRotation(
            duration: const Duration(milliseconds: 200),
            turns: _isOpen ? 0.125 : 0,
            child: Icon(_isOpen ? Icons.close : Icons.add),
          ),
        ),
      ],
    );
  }

  Widget _buildOption({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    Color? backgroundColor,
  }) {
    final theme = FlutterFlowTheme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.secondaryBackground,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              label,
              style: theme.bodyMedium,
            ),
          ),
        ),
        const SizedBox(width: 12),
        FloatingActionButton(
          heroTag: 'fab_$label',
          onPressed: onTap,
          backgroundColor: backgroundColor,
          child: Icon(icon),
        ),
      ],
    );
  }
}

class _NewMessageSheet extends StatefulWidget {
  const _NewMessageSheet();

  @override
  State<_NewMessageSheet> createState() => _NewMessageSheetState();
}

class _NewMessageSheetState extends State<_NewMessageSheet> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<Map<String, dynamic>> _following = [];
  List<Map<String, dynamic>> _followers = [];
  List<Map<String, dynamic>> _searchResults = [];
  bool _loadingBase = true;
  bool _searching = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    setState(() => _loadingBase = true);
    try {
      final uid = currentUserUid;
      if (uid.isEmpty) return;
      final results = await Future.wait<List<Map<String, dynamic>>?>([
        ApiService.instance.getUserFollowing(uid),
        ApiService.instance.getUserFollowers(uid),
      ]);
      _following = (results[0] ?? [])
          .where((u) => (u['id']?.toString() ?? '') != uid)
          .toList();
      _followers = (results[1] ?? [])
          .where((u) => (u['id']?.toString() ?? '') != uid)
          .toList();
    } catch (_) {
      // swallow
    } finally {
      if (mounted) setState(() => _loadingBase = false);
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final q = _searchController.text.trim();
      if (q.isEmpty) {
        if (mounted) setState(() => _searchResults = []);
        return;
      }
      setState(() => _searching = true);
      try {
        final res = await ApiService.instance.searchUsers(q);
        final uid = currentUserUid;
        if (mounted) {
          setState(() => _searchResults = (res ?? [])
              .where((u) => (u['id']?.toString() ?? '') != uid)
              .toList());
        }
      } catch (_) {
        if (mounted) setState(() => _searchResults = []);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  List<Map<String, dynamic>> get _mutuals {
    final followingIds = _following.map((e) => e['id']).toSet();
    return _followers.where((f) => followingIds.contains(f['id'])).toList();
  }

  Future<void> _startConversationWith(Map<String, dynamic> user) async {
    final otherId = user['id']?.toString() ?? '';
    if (otherId.isEmpty) return;
    final myId = currentUserUid;
    if (otherId == myId) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can't message yourself")),
      );
      return;
    }
    final convo =
        await ApiService.instance.getOrCreateConversationWith(otherId);
    if (convo == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to start conversation')),
      );
      return;
    }
    final participants = (convo['participants'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final other = participants.firstWhere(
      (p) => p['id'] != myId,
      orElse: () => user,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EnhancedMessagingPage(
        chatId: convo['id']?.toString() ?? '',
        recipientUserId: other['id']?.toString() ?? otherId,
        recipientName: (other['displayName']?.toString() ?? '').isNotEmpty
            ? other['displayName'] as String
            : other['id']?.toString() ?? 'User',
        recipientPhotoUrl: other['profileImageUrl']?.toString() ?? '',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final contentPadding = MediaQuery.of(context).viewInsets;
    final showSearch = _searchController.text.trim().isNotEmpty;
    final results = showSearch ? _searchResults : [];
    final mutuals = _mutuals;

    return Padding(
      padding: EdgeInsets.only(bottom: contentPadding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            height: 5,
            width: 44,
            decoration: BoxDecoration(
              color: theme.secondaryBackground,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: theme.secondaryBackground,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      decoration: const InputDecoration(
                        hintText: 'Search users',
                        border: InputBorder.none,
                        icon: Icon(Icons.search_rounded),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                )
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_loadingBase)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showSearch) ...[
                        _SectionHeader(
                          title: _searching
                              ? 'Searching…'
                              : 'Results (${results.length})',
                          theme: theme,
                        ),
                        ...results.map((u) => _UserTile(
                              user: u,
                              theme: theme,
                              onTap: () => _startConversationWith(u),
                            )),
                        const SizedBox(height: 12),
                      ] else ...[
                        if (mutuals.isNotEmpty) ...[
                          _SectionHeader(
                              title: 'Suggested (mutuals)', theme: theme),
                          ...mutuals.map((u) => _UserTile(
                                user: u,
                                theme: theme,
                                onTap: () => _startConversationWith(u),
                              )),
                          const SizedBox(height: 12),
                        ],
                        if (_following.isNotEmpty) ...[
                          _SectionHeader(title: 'You follow', theme: theme),
                          ..._following.map((u) => _UserTile(
                                user: u,
                                theme: theme,
                                onTap: () => _startConversationWith(u),
                              )),
                          const SizedBox(height: 12),
                        ],
                        if (_followers.isNotEmpty) ...[
                          _SectionHeader(title: 'Your followers', theme: theme),
                          ..._followers.map((u) => _UserTile(
                                user: u,
                                theme: theme,
                                onTap: () => _startConversationWith(u),
                              )),
                          const SizedBox(height: 12),
                        ],
                        if (mutuals.isEmpty &&
                            _following.isEmpty &&
                            _followers.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: Text(
                                'No suggestions yet. Try searching by name or email.',
                                style: theme.bodyMedium
                                    .override(color: theme.secondaryText),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.theme});
  final String title;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Text(
        title,
        style: theme.labelLarge,
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile(
      {required this.user, required this.theme, required this.onTap});
  final Map<String, dynamic> user;
  final FlutterFlowTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = (user['displayName']?.toString() ?? '').isNotEmpty
        ? user['displayName'].toString()
        : (user['email']?.toString() ?? user['id']?.toString() ?? 'User');
    final photo = user['profileImageUrl']?.toString() ?? '';
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
        child: photo.isEmpty ? const Icon(Icons.person) : null,
      ),
      title: Text(name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.titleMedium),
      subtitle: user['bio'] != null && (user['bio'] as String).isNotEmpty
          ? Text(user['bio'], maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: Icon(Icons.chevron_right_rounded, color: theme.secondaryText),
      onTap: onTap,
    );
  }
}

/// Dialog that fetches and displays nearby users allowing quick messaging.
class _NearbyUsersDialog extends StatefulWidget {
  const _NearbyUsersDialog();

  @override
  State<_NearbyUsersDialog> createState() => _NearbyUsersDialogState();
}

class _NearbyUsersDialogState extends State<_NearbyUsersDialog> {
  bool _loading = true;
  bool _error = false;
  List<Map<String, dynamic>> _users = [];
  double _radiusKm = 5;
  bool _refreshing = false;
  Position? _lastPosition;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = false;
      _errorMessage = null;
    });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _error = true;
          _errorMessage = 'Location services are disabled.';
        });
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        setState(() {
          _error = true;
          _errorMessage = 'Location permission denied. Enable it in settings.';
        });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      _lastPosition = pos;
      final res = await ApiService.instance.getNearbyUsers(
          latitude: pos.latitude,
          longitude: pos.longitude,
          radiusKm: _radiusKm);
      setState(() {
        _users = (res ?? [])
            .where((u) => (u['id']?.toString() ?? '') != currentUserUid)
            .toList();
      });
    } catch (e) {
      setState(() {
        _error = true;
        _errorMessage = 'Failed to get GPS location.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _startConversation(Map<String, dynamic> user) async {
    final otherId = user['id']?.toString() ?? '';
    if (otherId.isEmpty) return;
    if (otherId == currentUserUid) return;
    final convo =
        await ApiService.instance.getOrCreateConversationWith(otherId);
    if (convo == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to start conversation')));
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    final participants = (convo['participants'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final other = participants.firstWhere(
      (p) => p['id'] != currentUserUid,
      orElse: () => user,
    );
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EnhancedMessagingPage(
        chatId: convo['id']?.toString() ?? '',
        recipientUserId: other['id']?.toString() ?? otherId,
        recipientName: (other['displayName']?.toString() ?? '').isNotEmpty
            ? other['displayName'] as String
            : other['id']?.toString() ?? 'User',
        recipientPhotoUrl: other['profileImageUrl']?.toString() ?? '',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return AlertDialog(
      backgroundColor: theme.secondaryBackground,
      title: Row(
        children: [
          const Icon(Icons.radar_rounded),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                const Expanded(child: Text('Nearby users (GPS)')),
                if (_lastPosition != null)
                  Icon(Icons.gps_fixed, size: 16, color: theme.primary),
              ],
            ),
          ),
          DropdownButton<double>(
            value: _radiusKm,
            underline: const SizedBox.shrink(),
            items: const [5, 10, 20]
                .map((r) => DropdownMenuItem<double>(
                      value: r.toDouble(),
                      child: Text('${r}km'),
                    ))
                .toList(),
            onChanged: (v) async {
              if (v == null) return;
              setState(() {
                _radiusKm = v;
                _refreshing = true;
              });
              await _fetch();
              if (mounted) setState(() => _refreshing = false);
            },
          )
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _loading
            ? const Center(
                child: Padding(
                padding: EdgeInsets.all(24.0),
                child: CircularProgressIndicator(),
              ))
            : _error
                ? Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      _errorMessage ?? 'Unable to fetch nearby users.',
                      style:
                          theme.bodyMedium.override(color: theme.secondaryText),
                    ),
                  )
                : _users.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          'No users found within $_radiusKm km.',
                          style: theme.bodyMedium
                              .override(color: theme.secondaryText),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemBuilder: (_, i) {
                          final u = _users[i];
                          final name =
                              (u['displayName']?.toString() ?? '').isNotEmpty
                                  ? u['displayName'].toString()
                                  : (u['email']?.toString() ??
                                      u['id']?.toString() ??
                                      'User');
                          final photo = u['profileImageUrl']?.toString() ?? '';
                          final distanceKm =
                              (u['distanceKm'] as num?)?.toDouble();
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundImage:
                                  photo.isNotEmpty ? NetworkImage(photo) : null,
                              child: photo.isEmpty
                                  ? const Icon(Icons.person)
                                  : null,
                            ),
                            title: Text(name,
                                style: theme.titleMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            subtitle: distanceKm != null
                                ? Text(
                                    '${distanceKm.toStringAsFixed(1)} km away')
                                : null,
                            trailing: IconButton(
                              icon: const Icon(Icons.chat_rounded),
                              onPressed: () => _startConversation(u),
                            ),
                            onTap: () => _startConversation(u),
                          );
                        },
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: theme.alternate),
                        itemCount: _users.length,
                      ),
      ),
      actions: [
        TextButton(
          onPressed: _refreshing
              ? null
              : () async {
                  await _fetch();
                },
          child: _refreshing
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Refresh'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
