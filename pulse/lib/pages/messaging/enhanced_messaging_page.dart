// Clean rebuilt Enhanced Messaging Page: pinned messages, unread divider, swipe reply, reactions, action sheet, media & reply support.
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../auth/firebase_auth/auth_util.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import '../../backend/api_service.dart';
import '../../backend/chat_transport.dart';
import '../../backend/webrtc_call_service.dart';
import '../calling/call_screen.dart';
import '../calling/group_call_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../backend/socket_service.dart';

// ================= Models =================
class RepliedMessage {
  RepliedMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    this.text,
    this.imageUrl,
    this.videoUrl,
  });
  final String id;
  final String senderId;
  final String senderName;
  final String? text;
  final String? imageUrl;
  final String? videoUrl;

  bool get isImage => imageUrl != null && imageUrl!.isNotEmpty;
  bool get isVideo => videoUrl != null && videoUrl!.isNotEmpty;

  factory RepliedMessage.fromJson(Map<String, dynamic> json) => RepliedMessage(
        id: json['id'] as String,
        senderId: json['senderId'] as String,
        senderName: json['senderName'] as String? ?? 'Unknown',
        text: json['text'] as String?,
        imageUrl: json['imageUrl'] as String?,
        videoUrl: json['videoUrl'] as String?,
      );
}

class EnhancedMessage {
  EnhancedMessage({
    required this.id,
    required this.senderId,
    required this.timestamp,
    this.text,
    this.imageUrl,
    this.videoUrl,
    this.reactions,
    this.senderName,
    this.senderPhotoUrl,
    this.isSystemMessage = false,
    this.linkPreview,
    this.location,
    this.readBy,
    this.deliveredTo,
    this.repliedTo,
    this.editedAt,
  });
  final String id;
  final String senderId;
  final DateTime timestamp;
  final String? text;
  final String? imageUrl;
  final String? videoUrl;
  final Map<String, List<String>>? reactions; // emoji -> userIds
  final String? senderName;
  final String? senderPhotoUrl;
  final bool isSystemMessage;
  final LinkPreview? linkPreview;
  final LocationData? location;
  final List<String>? readBy;
  final List<String>? deliveredTo;
  final RepliedMessage? repliedTo;
  final DateTime? editedAt;
  bool get isImage => imageUrl != null && imageUrl!.isNotEmpty;
  bool get isVideo => videoUrl != null && videoUrl!.isNotEmpty;
  bool get isLocation => location != null;
  bool get hasLinkPreview => linkPreview != null;
  bool get isEdited => editedAt != null;
  factory EnhancedMessage.fromSocket(Map<String, dynamic> data) =>
      EnhancedMessage(
        id: data['id'] as String,
        senderId: data['senderId'] as String,
        timestamp: DateTime.tryParse(data['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        text: data['text'] as String?,
        imageUrl: data['imageUrl'] as String?,
        videoUrl: data['videoUrl'] as String?,
        reactions: data['reactions'] != null
            ? Map<String, List<String>>.from(
                (data['reactions'] as Map<String, dynamic>).map(
                (k, v) => MapEntry(k, List<String>.from(v)),
              ))
            : null,
        senderName: data['senderName'] as String?,
        senderPhotoUrl: data['senderPhotoUrl'] as String?,
        isSystemMessage: data['isSystemMessage'] == true,
        linkPreview: data['linkPreview'] != null
            ? LinkPreview.fromJson(data['linkPreview'])
            : null,
        location: data['location'] != null
            ? LocationData.fromJson(data['location'])
            : null,
        readBy:
            data['readBy'] != null ? List<String>.from(data['readBy']) : null,
        deliveredTo: data['deliveredTo'] != null
            ? List<String>.from(data['deliveredTo'])
            : null,
        repliedTo: data['repliedTo'] != null
            ? RepliedMessage.fromJson(data['repliedTo'] as Map<String, dynamic>)
            : null,
        editedAt: data['editedAt'] != null
            ? DateTime.tryParse(data['editedAt'].toString())
            : null,
      );
}

class LinkPreview {
  LinkPreview({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
  });
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;
  factory LinkPreview.fromJson(Map<String, dynamic> json) => LinkPreview(
        url: json['url'] as String,
        title: json['title'] as String?,
        description: json['description'] as String?,
        imageUrl: json['imageUrl'] as String?,
        siteName: json['siteName'] as String?,
      );
}

class LocationData {
  LocationData({
    required this.latitude,
    required this.longitude,
    this.address,
  });
  final double latitude;
  final double longitude;
  final String? address;
  factory LocationData.fromJson(Map<String, dynamic> json) => LocationData(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        address: json['address'] as String?,
      );
}

// ================= Providers =================
/// Current transport mode provider.
final chatTransportModeProvider =
    StateProvider<ChatTransportMode>((_) => ChatTransportMode.network);

final _enhancedMessagesStreamProvider = StreamProvider.autoDispose
    .family<List<EnhancedMessage>, String>((ref, cid) {
  final mode = ref.watch(chatTransportModeProvider);
  final controller = StreamController<List<EnhancedMessage>>();
  final byId = <String, EnhancedMessage>{};
  bool initialized = false;

  void _publish() {
    final list = byId.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    controller.add(list);
  }

  Future<void> hydrate() async {
    if (initialized)
      return; // avoid duplicate initial loads when mode changes fast
    initialized = true;
    final raw = await ChatTransportManager.instance.initialMessages(cid);
    for (final r in raw) {
      final m = EnhancedMessage.fromSocket(r);
      byId[m.id] = m;
    }
    _publish();
  }

  // Listen to active transport's streams scoped by conversation id.
  final transport = ChatTransportManager.instance.transportFor(mode);
  final sub = transport.messages.listen((data) {
    if (data['conversationId'] == cid) {
      final m = EnhancedMessage.fromSocket(Map<String, dynamic>.from(data));
      byId[m.id] = m;
      _publish();
    }
  });

  // Listen to message status updates (delivered/read)
  final statusSub = SocketService.instance.messageStatusUpdates.listen((data) {
    if (data['conversationId'] == cid) {
      final messageId = data['messageId']?.toString();
      if (messageId != null && byId.containsKey(messageId)) {
        final existing = byId[messageId]!;
        final updatedReadBy = data['readBy'] != null
            ? List<String>.from(data['readBy'])
            : existing.readBy;
        final updatedDeliveredTo = data['deliveredTo'] != null
            ? List<String>.from(data['deliveredTo'])
            : existing.deliveredTo;

        // Create updated message with new status
        byId[messageId] = EnhancedMessage(
          id: existing.id,
          senderId: existing.senderId,
          timestamp: existing.timestamp,
          text: existing.text,
          imageUrl: existing.imageUrl,
          videoUrl: existing.videoUrl,
          reactions: existing.reactions,
          senderName: existing.senderName,
          senderPhotoUrl: existing.senderPhotoUrl,
          isSystemMessage: existing.isSystemMessage,
          linkPreview: existing.linkPreview,
          location: existing.location,
          readBy: updatedReadBy,
          deliveredTo: updatedDeliveredTo,
          repliedTo: existing.repliedTo,
          editedAt: existing.editedAt,
        );
        _publish();
      }
    }
  });

  hydrate();

  ref.onDispose(() {
    sub.cancel();
    statusSub.cancel();
    controller.close();
  });
  return controller.stream;
});

final _typingStreamProvider = StreamProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, chatId) {
  final mode = ref.watch(chatTransportModeProvider);
  final transport = ChatTransportManager.instance.transportFor(mode);
  return transport.typing.map((data) {
    try {
      final m = Map<String, dynamic>.from(data);
      if (m['conversationId']?.toString() == chatId &&
          m['userId']?.toString() != currentUserUid) {
        return {
          'userId': m['userId'].toString(),
          'isTyping': m['isTyping'] == true,
          'userName': m['userName']?.toString() ?? 'Someone'
        };
      }
    } catch (_) {}
    return <String, dynamic>{};
  });
});

final _onlineUsersProvider =
    StreamProvider.autoDispose.family<Set<String>, String>((ref, chatId) {
  return Stream.periodic(const Duration(seconds: 10), (i) => <String>{})
      .asBroadcastStream();
});

// ================= Page =================
class EnhancedMessagingPage extends ConsumerStatefulWidget {
  const EnhancedMessagingPage({
    super.key,
    required this.chatId,
    required this.recipientUserId,
    required this.recipientName,
    required this.recipientPhotoUrl,
    this.isGroupChat = false,
    this.pulseId,
    this.groupMembers,
  });
  final String chatId;
  final String recipientUserId;
  final String recipientName;
  final String recipientPhotoUrl;
  final bool isGroupChat;
  final String? pulseId;
  final List<Map<String, dynamic>>? groupMembers;
  @override
  ConsumerState<EnhancedMessagingPage> createState() =>
      _EnhancedMessagingPageState();
}

class _EnhancedMessagingPageState extends ConsumerState<EnhancedMessagingPage>
    with TickerProviderStateMixin {
  // Current conversation id (may be normalized by server acks or bootstrap)
  late String _chatId;
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  late AnimationController _badgeCtl;
  late Animation<double> _badgeAnim;
  bool _showEmoji = false;
  bool _isSending = false;
  bool _isAtBottom = true;
  bool _showNewBadge = false;
  int _newCount = 0;
  Timer? _typingDebounce;
  EnhancedMessage? _reply;
  final DateTime _openedAt = DateTime.now();
  final Set<String> _pinned = {};
  String? _firstUnreadId;
  final Set<String> _markedAsRead =
      {}; // Track which messages we've already marked as read
  Map<String, Map<String, dynamic>>? _groupMemberIndex; // userId -> member map

  // Activity status tracking
  String? _recipientStatus;
  StreamSubscription? _statusSubscription;

  void _indexGroupMembers() {
    final members = widget.groupMembers;
    if (members == null) return;
    final map = <String, Map<String, dynamic>>{};
    for (final raw in members) {
      final id = (raw['id'] ??
              raw['userId'] ??
              raw['uid'] ??
              raw['user_id'] ??
              raw['memberId'] ??
              raw['member_id'] ??
              raw['participantId'])
          ?.toString();
      if (id != null && id.isNotEmpty) map[id] = raw;
    }
    if (map.isNotEmpty) _groupMemberIndex = map;
  }

  String? _resolveSenderName(String userId) {
    final idx = _groupMemberIndex;
    if (idx == null) return null;
    final m = idx[userId];
    if (m == null) return null;
    final first = (m['firstName'] ?? m['first_name'])?.toString();
    final last = (m['lastName'] ?? m['last_name'])?.toString();
    final combined = ((first ?? '').isEmpty && (last ?? '').isEmpty)
        ? null
        : [first, last].where((e) => e != null && e.isNotEmpty).join(' ');
    return (m['displayName'] ??
            m['display_name'] ??
            m['fullName'] ??
            m['full_name'] ??
            combined ??
            m['name'] ??
            m['username'])
        ?.toString();
  }

  String? _resolveSenderPhoto(String userId) {
    final idx = _groupMemberIndex;
    if (idx == null) return null;
    final m = idx[userId];
    if (m == null) return null;
    return (m['photoUrl'] ??
            m['photo_url'] ??
            m['avatar'] ??
            m['profilePhoto'] ??
            m['profile_photo'] ??
            m['image'] ??
            m['imageUrl'])
        ?.toString();
  }

  @override
  void initState() {
    super.initState();
    _chatId = widget.chatId;
    _indexGroupMembers();
    _text.addListener(_handleTyping);
    _scroll.addListener(_handleScroll);
    _badgeCtl = AnimationController(vsync: this, duration: 250.ms);
    _badgeAnim = CurvedAnimation(parent: _badgeCtl, curve: Curves.easeOut);
    // Ensure active transport connected & joined
    ChatTransportManager.instance.ensureConnected();
    ChatTransportManager.instance.active.joinConversation(_chatId);

    // Normalize id from initial message load (handles pulse/direct/group id mapping)
    _normalizeConversationIdFromBootstrap();

    // Also normalize on message ack (server confirms canonical id)
    SocketService.instance.acks.listen((ack) {
      try {
        final cid = (ack['conversationId'] ?? ack['id'])?.toString();
        if (cid != null && cid.isNotEmpty && cid != _chatId) {
          final old = _chatId;
          setState(() => _chatId = cid);
          ChatTransportManager.instance.active.leaveConversation(old);
          ChatTransportManager.instance.active.joinConversation(_chatId);
        }
      } catch (_) {}
    });

    // Load recipient's activity status
    if (!widget.isGroupChat) {
      _loadRecipientStatus();
      _listenToStatusChanges();
    }

    // Listen for message status updates (delivered/read receipts)
    SocketService.instance.messageStatusUpdates.listen((data) {
      if (!mounted) return;
      if (data['conversationId']?.toString() != _chatId) return;

      final messageId = data['messageId']?.toString();
      if (messageId == null) return;

      // The status update is handled by the stream provider automatically
      // since it will receive the updated message from the backend
    });

    // Listen for group call start/stop and show a join banner (opt-in)
    if (widget.isGroupChat) {
      SocketService.instance.groupCallStarted.listen((m) {
        if (!mounted) return;
        if (m['conversationId']?.toString() != widget.chatId) return;
        final isVideo = m['isVideo'] == true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(isVideo
                ? 'Group video call started'
                : 'Group voice call started'),
            action: SnackBarAction(
              label: 'Join',
              onPressed: () async {
                if (isVideo) {
                  final res = await [Permission.microphone, Permission.camera]
                      .request();
                  if (res[Permission.microphone]?.isGranted != true ||
                      res[Permission.camera]?.isGranted != true) return;
                } else {
                  final p = await Permission.microphone.request();
                  if (!p.isGranted) return;
                }
                if (!mounted) return;
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => GroupCallScreen(
                    conversationId: widget.chatId,
                    isVideo: isVideo,
                  ),
                ));
              },
            ),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    _statusSubscription?.cancel();
    _text.removeListener(_handleTyping);
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    _badgeCtl.dispose();
    _setTyping(false);
    ChatTransportManager.instance.active.leaveConversation(_chatId);
    super.dispose();
  }

  Future<void> _normalizeConversationIdFromBootstrap() async {
    try {
      final res = await ApiService.instance.listMessages(_chatId);
      final msgs = (res?['messages'] as List?)?.whereType<Map>().toList() ??
          const <Map>[];
      if (msgs.isNotEmpty) {
        final canonical = msgs.first['conversationId']?.toString();
        if (canonical != null && canonical.isNotEmpty && canonical != _chatId) {
          final old = _chatId;
          setState(() => _chatId = canonical);
          ChatTransportManager.instance.active.leaveConversation(old);
          ChatTransportManager.instance.active.joinConversation(_chatId);
        }
      }
    } catch (_) {}
  }

  /// Load recipient's activity status
  Future<void> _loadRecipientStatus() async {
    if (widget.recipientUserId.isEmpty) return;

    final statuses =
        await ApiService.instance.getActivityStatuses([widget.recipientUserId]);
    if (statuses != null && mounted) {
      final statusData = statuses[widget.recipientUserId];
      if (statusData != null) {
        setState(() {
          _recipientStatus = statusData['status'];
        });
      }
    }
  }

  /// Listen for real-time activity status updates
  void _listenToStatusChanges() {
    _statusSubscription =
        SocketService.instance.userStatusChanged.listen((data) {
      final userId = data['userId'] as String?;
      final status = data['status'] as String?;

      if (userId == widget.recipientUserId && status != null && mounted) {
        setState(() {
          _recipientStatus = status;
        });
      }
    });
  }

  void _handleScroll() {
    final atBottom = _scroll.hasClients &&
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 100;
    if (atBottom != _isAtBottom) {
      setState(() {
        _isAtBottom = atBottom;
        if (atBottom) {
          _showNewBadge = false;
          _newCount = 0;
        }
      });
    }

    // Mark visible messages as read
    _markVisibleMessagesAsRead();
  }

  void _markVisibleMessagesAsRead() {
    final messagesAsync = ref.read(_enhancedMessagesStreamProvider(_chatId));
    messagesAsync.whenData((messages) {
      for (final message in messages) {
        // Skip if it's my own message or already marked
        if (message.senderId == currentUserUid) continue;
        if (_markedAsRead.contains(message.id)) continue;

        // Mark as read
        _markedAsRead.add(message.id);
        SocketService.instance.markMessageRead(
          conversationId: _chatId,
          messageId: message.id,
        );
      }
    });
  }

  void _handleTyping() {
    _typingDebounce?.cancel();
    _setTyping(true);
    _typingDebounce = Timer(const Duration(milliseconds: 900), () {
      _setTyping(false);
    });
  }

  Future<void> _setTyping(bool v) async {
    if (currentUserUid.isEmpty) return;
    ChatTransportManager.instance.active.setTyping(_chatId, v);
  }

  Future<void> _sendText() async {
    final txt = _text.text.trim();
    if (txt.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    try {
      HapticFeedback.lightImpact();
      ChatTransportManager.instance.active.sendMessage(
        conversationId: _chatId,
        text: txt,
        repliedToId: _reply?.id,
      );
      _text.clear();
      _clearReply();
      await _scrollToBottom();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _sendMedia(String? img, String? vid) async {
    try {
      HapticFeedback.lightImpact();
      ChatTransportManager.instance.active
          .sendMessage(conversationId: _chatId, imageUrl: img, videoUrl: vid);
      _clearReply();
      await _scrollToBottom();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send media')),
        );
      }
    }
  }

  Future<void> _sendLocation() async {
    try {
      ChatTransportManager.instance.active
          .sendMessage(conversationId: _chatId, text: '📍 Location shared');
      _clearReply();
      await _scrollToBottom();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send location')),
        );
      }
    }
  }

  Future<void> _scrollToBottom({bool animated = true}) async {
    await Future.delayed(const Duration(milliseconds: 40));
    if (!_scroll.hasClients) return;
    final off = _scroll.position.maxScrollExtent + 80;
    if (animated) {
      _scroll.animateTo(off,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      _scroll.jumpTo(off);
    }
  }

  void _replyToMessage(EnhancedMessage m) {
    setState(() => _reply = m);
    _focus.requestFocus();
  }

  void _clearReply() => setState(() => _reply = null);

  Future<void> _addReaction(String id, String emoji) async {
    try {
      HapticFeedback.selectionClick();
      ChatTransportManager.instance.active
          .addReaction(conversationId: _chatId, messageId: id, emoji: emoji);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to react')),
        );
      }
    }
  }

  void _togglePin(String id) => setState(
      () => _pinned.contains(id) ? _pinned.remove(id) : _pinned.add(id));
  void _copyMessage(EnhancedMessage m) {
    final t = m.text;
    if (t == null || t.isEmpty) return;
    Clipboard.setData(ClipboardData(text: t));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied')));
  }

  void _deleteMessage(EnhancedMessage m) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Delete not implemented')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final messagesAsync = ref.watch(_enhancedMessagesStreamProvider(_chatId));
    final typingData = ref
        .watch(_typingStreamProvider(_chatId))
        .maybeWhen(data: (d) => d, orElse: () => <String, dynamic>{});
    final online = ref
        .watch(_onlineUsersProvider(_chatId))
        .maybeWhen(data: (s) => s, orElse: () => <String>{});
    ref.listen(_enhancedMessagesStreamProvider(_chatId), (prev, next) {
      next.whenData((msgs) {
        if (!_isAtBottom && prev != null) {
          prev.whenData((old) {
            if (msgs.length > old.length) {
              setState(() {
                _showNewBadge = true;
                _newCount = msgs.length - old.length;
              });
              _badgeCtl.forward().then((_) => _badgeCtl.reverse());
            }
          });
        } else if (_isAtBottom) {
          _scrollToBottom();
        }
      });
    });
    return GestureDetector(
      onTap: () {
        if (_showEmoji) setState(() => _showEmoji = false);
        _focus.unfocus();
      },
      child: Scaffold(
        backgroundColor: theme.primaryBackground,
        appBar: _appBar(theme, typingData, online),
        body: SafeArea(
          child: Column(
            children: [
              if (_pinned.isNotEmpty)
                _PinnedBar(
                  ids: _pinned.toList(),
                  messagesAsync: messagesAsync,
                  theme: theme,
                  onUnpin: (id) => setState(() => _pinned.remove(id)),
                  onTap: (_) {},
                ),
              Expanded(
                child: Stack(
                  children: [
                    _messagesList(messagesAsync, theme),
                    _newBadge(theme),
                  ],
                ),
              ),
              _typingIndicator(typingData, theme),
              _replyBar(theme),
              _composer(theme),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar(
      FlutterFlowTheme t, Map<String, dynamic> typing, Set<String> online) {
    // Use our tracked status if available, otherwise fall back to online set
    final isOnline = _recipientStatus == 'online' ||
        (_recipientStatus == null && online.contains(widget.recipientUserId));
    final isAway = _recipientStatus == 'away';

    return AppBar(
      elevation: .5,
      backgroundColor: t.secondaryBackground,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: t.primaryText),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      titleSpacing: 0,
      title: Row(children: [
        Stack(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor:
                widget.isGroupChat ? t.primary.withOpacity(.1) : t.accent2,
            backgroundImage:
                !widget.isGroupChat && widget.recipientPhotoUrl.isNotEmpty
                    ? CachedNetworkImageProvider(widget.recipientPhotoUrl)
                    : null,
            child: widget.isGroupChat
                ? Icon(Icons.group_rounded, color: t.primary, size: 20)
                : (widget.recipientPhotoUrl.isEmpty
                    ? Icon(Icons.person, color: t.secondaryText, size: 20)
                    : null),
          ),
          if (!widget.isGroupChat && (isOnline || isAway))
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: isOnline ? Colors.green : Colors.orange,
                  shape: BoxShape.circle,
                  border: Border.all(color: t.secondaryBackground, width: 2),
                ),
              ),
            ),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.recipientName,
                  style: t.titleMedium.override(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(_subtitle(typing, online),
                  style:
                      t.bodySmall.override(color: _subtitleColor(typing, t))),
            ],
          ),
        )
      ]),
      actions: [
        _transportToggle(t),
        if (!widget.isGroupChat)
          IconButton(
            tooltip: 'Start video call',
            icon: Icon(Icons.videocam_rounded, color: t.primaryText),
            onPressed: () async {
              try {
                // Request camera & microphone permissions
                await [Permission.camera, Permission.microphone].request();
                if (!mounted) return;
                // Show ringing UI immediately
                Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(
                    builder: (_) => CallScreen(
                      peerUserId: widget.recipientUserId,
                      isVideo: true,
                    ),
                  ),
                );
                // Dial in the background with error feedback
                Future.microtask(() async {
                  try {
                    await WebRTCCallService.instance.callPeer(
                      toUserId: widget.recipientUserId,
                      isVideo: true,
                      conversationId: _chatId,
                    );
                  } catch (_) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Call failed')),
                    );
                    Navigator.of(context).maybePop();
                  }
                });
              } catch (_) {}
            },
          ),
        if (!widget.isGroupChat)
          IconButton(
            tooltip: 'Start voice call',
            icon: Icon(Icons.call_rounded, color: t.primaryText),
            onPressed: () async {
              try {
                await [Permission.microphone].request();
                if (!mounted) return;
                // Show ringing UI immediately
                Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(
                    builder: (_) => CallScreen(
                      peerUserId: widget.recipientUserId,
                      isVideo: false,
                    ),
                  ),
                );
                // Dial in the background with error feedback
                Future.microtask(() async {
                  try {
                    await WebRTCCallService.instance.callPeer(
                      toUserId: widget.recipientUserId,
                      isVideo: false,
                      conversationId: _chatId,
                    );
                  } catch (_) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Call failed')),
                    );
                    Navigator.of(context).maybePop();
                  }
                });
              } catch (_) {}
            },
          ),
        if (widget.isGroupChat)
          PopupMenuButton<String>(
            tooltip: 'Group call',
            onSelected: (v) async {
              if (v == 'voice') {
                final perm = await Permission.microphone.request();
                if (!perm.isGranted) return;
                if (!mounted) return;
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => GroupCallScreen(
                    conversationId: _chatId,
                    isVideo: false,
                  ),
                ));
              } else if (v == 'video') {
                final res =
                    await [Permission.microphone, Permission.camera].request();
                if (res[Permission.microphone]?.isGranted != true ||
                    res[Permission.camera]?.isGranted != true) return;
                if (!mounted) return;
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => GroupCallScreen(
                    conversationId: _chatId,
                    isVideo: true,
                  ),
                ));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'voice', child: Text('Start group voice call')),
              PopupMenuItem(
                  value: 'video', child: Text('Start group video call')),
            ],
            icon: Icon(Icons.groups_rounded, color: t.primaryText),
          ),
      ],
    );
  }

  Widget _transportToggle(FlutterFlowTheme t) {
    final mode = ref.watch(chatTransportModeProvider);
    final isBt = mode == ChatTransportMode.bluetooth;
    return IconButton(
      tooltip: isBt ? 'Bluetooth mesh (experimental)' : 'Network transport',
      icon: Icon(isBt ? Icons.bluetooth_rounded : Icons.wifi_rounded,
          color: isBt ? t.primary : t.primaryText),
      onPressed: () => _showTransportPicker(mode),
    );
  }

  Future<void> _showTransportPicker(ChatTransportMode current) async {
    final t = FlutterFlowTheme.of(context);
    await showModalBottomSheet(
        context: context,
        backgroundColor: t.secondaryBackground,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) {
          return SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 12),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: t.secondaryText.withOpacity(.3),
                    borderRadius: BorderRadius.circular(2))),
            ListTile(
              leading: const Icon(Icons.wifi_rounded),
              title: const Text('Network (Wi‑Fi / Mobile Data)'),
              subtitle: const Text('Real-time via backend server'),
              trailing: current == ChatTransportMode.network
                  ? Icon(Icons.check, color: t.primary)
                  : null,
              onTap: () {
                Navigator.pop(context);
                ref.read(chatTransportModeProvider.notifier).state =
                    ChatTransportMode.network;
                // Ensure conversation joined on new transport
                Future.microtask(() => ChatTransportManager.instance.active
                    .joinConversation(widget.chatId));
              },
            ),
            ListTile(
              leading: const Icon(Icons.bluetooth_rounded),
              title: const Text('Bluetooth Mesh (Experimental)'),
              subtitle: const Text('Offline, nearby only – prototype'),
              trailing: current == ChatTransportMode.bluetooth
                  ? Icon(Icons.check, color: t.primary)
                  : null,
              onTap: () {
                Navigator.pop(context);
                ref.read(chatTransportModeProvider.notifier).state =
                    ChatTransportMode.bluetooth;
                Future.microtask(() => ChatTransportManager.instance.active
                    .joinConversation(widget.chatId));
              },
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                'Bluetooth mode is a local prototype – messages are kept locally and broadcast simulation only.',
                style: t.bodySmall.override(color: t.secondaryText),
              ),
            )
          ]));
        });
  }

  String _subtitle(Map<String, dynamic> typing, Set<String> online) {
    if (typing['isTyping'] == true) {
      final n = typing['userName']?.toString();
      if (n != null) return '$n is typing...';
    }
    if (widget.isGroupChat) {
      final c = online.length;
      return c > 1 ? '$c members online' : 'Group chat';
    }
    return online.contains(widget.recipientUserId)
        ? 'Online'
        : 'Last seen recently';
  }

  Color _subtitleColor(Map<String, dynamic> typing, FlutterFlowTheme t) {
    if (typing['isTyping'] == true) return t.primary;
    if (widget.isGroupChat) return t.primary;
    return t.secondaryText;
  }

  Widget _messagesList(
      AsyncValue<List<EnhancedMessage>> async, FlutterFlowTheme t) {
    return async.when(
      data: (msgs) {
        if (msgs.isEmpty) return _empty(t);
        if (_firstUnreadId == null) {
          for (final m in msgs) {
            if (m.timestamp.isAfter(_openedAt)) {
              _firstUnreadId = m.id;
              break;
            }
          }
        }
        return RefreshIndicator(
          onRefresh: () async =>
              Future.delayed(const Duration(milliseconds: 300)),
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: msgs.length,
            itemBuilder: (_, i) {
              final m = msgs[i];
              final prev = i > 0 ? msgs[i - 1] : null;
              final next = i < msgs.length - 1 ? msgs[i + 1] : null;
              final showAvatar = _showAvatar(m, next);
              final showName = _showName(m, prev);
              final showDate = _showDate(m, prev);
              return Column(children: [
                if (showDate) _dateDivider(m.timestamp, t),
                if (_firstUnreadId != null && m.id == _firstUnreadId)
                  _UnreadDivider(theme: t),
                if (m.isSystemMessage)
                  _system(m, t)
                else
                  (() {
                    // Apply fallback sender info for group chats when backend omits it.
                    if (widget.isGroupChat &&
                        (m.senderName == null ||
                            m.senderName!.isEmpty ||
                            m.senderName == 'Unknown')) {
                      final fallbackName = _resolveSenderName(m.senderId);
                      final fallbackPhoto = _resolveSenderPhoto(m.senderId);
                      if (fallbackName != null || fallbackPhoto != null) {
                        final patched = EnhancedMessage(
                          id: m.id,
                          senderId: m.senderId,
                          timestamp: m.timestamp,
                          text: m.text,
                          imageUrl: m.imageUrl,
                          videoUrl: m.videoUrl,
                          reactions: m.reactions,
                          senderName: fallbackName ?? m.senderName,
                          senderPhotoUrl: fallbackPhoto ?? m.senderPhotoUrl,
                          isSystemMessage: m.isSystemMessage,
                          linkPreview: m.linkPreview,
                          location: m.location,
                          readBy: m.readBy,
                          repliedTo: m.repliedTo,
                          editedAt: m.editedAt,
                        );
                        return _EnhancedMessageBubble(
                          message: patched,
                          isMine: patched.senderId == currentUserUid,
                          theme: t,
                          isGroupChat: widget.isGroupChat,
                          showAvatar: showAvatar,
                          showSenderName: showName,
                          onReact: (e) => _addReaction(patched.id, e),
                          onReply: () => _replyToMessage(patched),
                          onPinToggle: () => _togglePin(patched.id),
                          onCopy: () => _copyMessage(patched),
                          onDelete: () => _deleteMessage(patched),
                          isPinned: _pinned.contains(patched.id),
                        );
                      }
                    }
                    return _EnhancedMessageBubble(
                      message: m,
                      isMine: m.senderId == currentUserUid,
                      theme: t,
                      isGroupChat: widget.isGroupChat,
                      showAvatar: showAvatar,
                      showSenderName: showName,
                      onReact: (e) => _addReaction(m.id, e),
                      onReply: () => _replyToMessage(m),
                      onPinToggle: () => _togglePin(m.id),
                      onCopy: () => _copyMessage(m),
                      onDelete: () => _deleteMessage(m),
                      isPinned: _pinned.contains(m.id),
                    );
                  })()
              ])
                  .animate()
                  .fadeIn(duration: 200.ms)
                  .slideY(begin: .1, end: 0, duration: 200.ms);
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _error(t),
    );
  }

  Widget _empty(FlutterFlowTheme t) => Center(
          child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline,
              size: 70, color: t.secondaryText.withOpacity(.5)),
          const SizedBox(height: 12),
          Text('No messages yet',
              style: t.titleLarge.override(
                  color: t.secondaryText, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Say hello 👋',
              style: t.bodyLarge.override(color: t.secondaryText))
        ],
      ));
  Widget _error(FlutterFlowTheme t) => Center(
          child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 70, color: t.error.withOpacity(.5)),
          const SizedBox(height: 12),
          Text('Unable to load messages',
              style: t.titleLarge
                  .override(color: t.error, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ElevatedButton(
              onPressed: () => ref
                  .invalidate(_enhancedMessagesStreamProvider(widget.chatId)),
              child: const Text('Retry'))
        ],
      ));

  bool _showAvatar(EnhancedMessage cur, EnhancedMessage? next) {
    if (cur.senderId == currentUserUid) return false;
    if (next == null) return true;
    if (next.senderId != cur.senderId) return true;
    return next.timestamp.difference(cur.timestamp).inMinutes > 2;
  }

  bool _showName(EnhancedMessage cur, EnhancedMessage? prev) {
    if (!widget.isGroupChat) return false;
    if (cur.senderId == currentUserUid) return false;
    if (prev == null) return true;
    if (prev.senderId != cur.senderId) return true;
    return cur.timestamp.difference(prev.timestamp).inMinutes > 2;
  }

  bool _showDate(EnhancedMessage cur, EnhancedMessage? prev) {
    if (prev == null) return true;
    final cD =
        DateTime(cur.timestamp.year, cur.timestamp.month, cur.timestamp.day);
    final pD =
        DateTime(prev.timestamp.year, prev.timestamp.month, prev.timestamp.day);
    return !cD.isAtSameMomentAs(pD);
  }

  Widget _dateDivider(DateTime d, FlutterFlowTheme t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final md = DateTime(d.year, d.month, d.day);
    String label;
    if (md.isAtSameMomentAs(today)) {
      label = 'Today';
    } else if (md.isAtSameMomentAs(yesterday)) {
      label = 'Yesterday';
    } else {
      label = '${d.month}/${d.day}/${d.year}';
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Expanded(child: Divider(color: t.secondaryText.withOpacity(.3))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(label,
              style: t.bodySmall.override(
                  color: t.secondaryText, fontWeight: FontWeight.w500)),
        ),
        Expanded(child: Divider(color: t.secondaryText.withOpacity(.3)))
      ]),
    );
  }

  Widget _system(EnhancedMessage m, FlutterFlowTheme t) => Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
          child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: t.secondaryText.withOpacity(.1),
            borderRadius: BorderRadius.circular(12)),
        child: Text(m.text ?? '',
            style: t.bodySmall
                .override(color: t.secondaryText, fontStyle: FontStyle.italic)),
      )));

  Widget _newBadge(FlutterFlowTheme t) {
    if (!_showNewBadge) return const SizedBox.shrink();
    return Positioned(
      bottom: 80,
      right: 16,
      child: ScaleTransition(
        scale: _badgeAnim,
        child: GestureDetector(
          onTap: () {
            setState(() {
              _showNewBadge = false;
              _newCount = 0;
            });
            _scrollToBottom();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: t.primary,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.keyboard_arrow_down,
                  color: Colors.white, size: 16),
              const SizedBox(width: 4),
              Text('$_newCount new',
                  style: t.bodySmall.override(
                      color: Colors.white, fontWeight: FontWeight.w500))
            ]),
          ),
        ),
      ),
    );
  }

  Widget _typingIndicator(Map<String, dynamic> typing, FlutterFlowTheme t) {
    if (typing['isTyping'] != true) return const SizedBox.shrink();
    final u = typing['userName']?.toString();
    if (u == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: t.secondaryBackground,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2))
              ]),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _TypingDots(color: t.primary),
            const SizedBox(width: 8),
            Text('$u is typing...',
                style: t.bodySmall
                    .override(color: t.primary, fontStyle: FontStyle.italic))
          ]),
        )
      ]),
    );
  }

  Widget _replyBar(FlutterFlowTheme t) {
    if (_reply == null) return const SizedBox.shrink();
    final label = _reply!.text ??
        (_reply!.isImage
            ? '📷 Image'
            : _reply!.isVideo
                ? '🎥 Video'
                : _reply!.isLocation
                    ? '📍 Location'
                    : 'Message');
    final replyToName = _reply!.senderName ?? 'Unknown';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: t.primary, width: 3)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Replying to $replyToName',
                  style: t.bodySmall
                      .override(color: t.primary, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(label,
                  style: t.bodySmall.override(color: t.secondaryText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)
            ],
          ),
        ),
        IconButton(
          onPressed: _clearReply,
          icon: Icon(Icons.close, color: t.secondaryText, size: 20),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        )
      ]),
    );
  }

  Widget _composer(FlutterFlowTheme t) {
    return SafeArea(
      top: false,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _text,
        builder: (_, v, __) {
          final canSend = v.text.trim().isNotEmpty && !_isSending;
          final mode = ref.watch(chatTransportModeProvider);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (mode == ChatTransportMode.bluetooth)
                Container(
                  width: double.infinity,
                  color: Colors.blue.withOpacity(.1),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Text('Bluetooth mesh prototype – messages stay local',
                      style: t.bodySmall.override(color: t.primary)),
                ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration:
                    BoxDecoration(color: t.secondaryBackground, boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(.04),
                      blurRadius: 8,
                      offset: const Offset(0, -2))
                ]),
                child: Row(children: [
                  _IconBtn(
                      icon: Icons.emoji_emotions_outlined,
                      tooltip: 'Emoji',
                      onTap: () => setState(() => _showEmoji = !_showEmoji),
                      color: _showEmoji ? t.primary : t.secondaryText),
                  _IconBtn(
                      icon: Icons.attach_file,
                      tooltip: 'Attach',
                      onTap: _showAttachmentOptions,
                      color: t.secondaryText),
                  Expanded(
                      child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                        color: t.primaryBackground,
                        borderRadius: BorderRadius.circular(25),
                        border:
                            Border.all(color: t.secondaryText.withOpacity(.2))),
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(minHeight: 44, maxHeight: 120),
                      child: TextField(
                        controller: _text,
                        focusNode: _focus,
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        style: t.bodyMedium,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Type a message...',
                          hintStyle:
                              t.bodyMedium.override(color: t.secondaryText),
                        ),
                      ),
                    ),
                  )),
                  AnimatedSwitcher(
                    duration: 200.ms,
                    child: canSend
                        ? IconButton(
                            key: const ValueKey('send'),
                            onPressed: _sendText,
                            icon: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                  color: t.primary, shape: BoxShape.circle),
                              child: const Icon(Icons.send_rounded,
                                  color: Colors.white, size: 20),
                            ))
                        : IconButton(
                            key: const ValueKey('mic'),
                            onPressed: () => ScaffoldMessenger.of(context)
                                .showSnackBar(const SnackBar(
                                    content:
                                        Text('Voice messages coming soon'))),
                            icon: Icon(Icons.mic_none_rounded,
                                color: t.secondaryText)),
                  )
                ]),
              ),
              if (_showEmoji)
                _EmojiPicker(
                    onPick: (e) {
                      _text.text += e;
                      _focus.requestFocus();
                    },
                    theme: t)
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAttachmentOptions() async {
    await showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _AttachmentOptionsSheet(
              onImageTap: _pickImage,
              onVideoTap: _pickVideo,
              onLocationTap: _sendLocation,
              theme: FlutterFlowTheme.of(context),
            ));
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
          maxWidth: 1024,
          maxHeight: 1024);
      if (file == null) return;
      showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(child: CircularProgressIndicator()));
      final bytes = await file.readAsBytes();
      final ref = FirebaseStorage.instance.ref().child(
          'chat_uploads/${widget.chatId}/${DateTime.now().millisecondsSinceEpoch}_${file.name}');
      final task =
          await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await task.ref.getDownloadURL();
      if (mounted) Navigator.of(context).pop();
      await _sendMedia(url, null);
    } catch (_) {
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  Future<void> _pickVideo() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickVideo(
          source: ImageSource.gallery, maxDuration: const Duration(minutes: 3));
      if (file == null) return;
      showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(child: CircularProgressIndicator()));
      final bytes = await file.readAsBytes();
      final ref = FirebaseStorage.instance.ref().child(
          'chat_uploads/${widget.chatId}/${DateTime.now().millisecondsSinceEpoch}_${file.name}');
      final task =
          await ref.putData(bytes, SettableMetadata(contentType: 'video/mp4'));
      final url = await task.ref.getDownloadURL();
      if (mounted) Navigator.of(context).pop();
      await _sendMedia(null, url);
    } catch (_) {
      if (mounted) Navigator.of(context).maybePop();
    }
  }
}

class _PinnedBar extends StatelessWidget {
  const _PinnedBar({
    required this.ids,
    required this.messagesAsync,
    required this.theme,
    required this.onUnpin,
    required this.onTap,
  });
  final List<String> ids;
  final AsyncValue<List<EnhancedMessage>> messagesAsync;
  final FlutterFlowTheme theme;
  final void Function(String) onUnpin;
  final void Function(String) onTap;
  @override
  Widget build(BuildContext context) {
    return messagesAsync.when(
      data: (msgs) {
        final pinned = msgs.where((m) => ids.contains(m.id)).toList();
        if (pinned.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 56,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            scrollDirection: Axis.horizontal,
            itemCount: pinned.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final m = pinned[i];
              final label = m.text?.trim().isNotEmpty == true
                  ? m.text!.trim()
                  : m.isImage
                      ? '📷 Image'
                      : m.isVideo
                          ? '🎥 Video'
                          : 'Message';
              return GestureDetector(
                onTap: () => onTap(m.id),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.secondaryBackground,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: theme.primary.withOpacity(.3)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(.04),
                          blurRadius: 4,
                          offset: const Offset(0, 2))
                    ],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.push_pin, size: 16, color: theme.primary),
                    const SizedBox(width: 6),
                    Flexible(
                        child: Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.bodySmall.override(
                                color: theme.primaryText,
                                fontWeight: FontWeight.w500))),
                    const SizedBox(width: 4),
                    GestureDetector(
                        onTap: () => onUnpin(m.id),
                        child: Icon(Icons.close,
                            size: 14, color: theme.secondaryText))
                  ]),
                ),
              );
            },
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _UnreadDivider extends StatelessWidget {
  const _UnreadDivider({required this.theme});
  final FlutterFlowTheme theme;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Expanded(child: Divider(color: theme.primary.withOpacity(.4))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: theme.primary, borderRadius: BorderRadius.circular(20)),
            child: Text('New Messages',
                style: theme.bodySmall.override(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Divider(color: theme.primary.withOpacity(.4)))
        ]),
      );
}

class _EnhancedMessageBubble extends StatefulWidget {
  const _EnhancedMessageBubble({
    required this.message,
    required this.isMine,
    required this.theme,
    required this.isGroupChat,
    required this.showAvatar,
    required this.showSenderName,
    required this.onReact,
    required this.onReply,
    required this.onPinToggle,
    required this.onCopy,
    required this.onDelete,
    this.isPinned = false,
  });
  final EnhancedMessage message;
  final bool isMine;
  final FlutterFlowTheme theme;
  final bool isGroupChat;
  final bool showAvatar;
  final bool showSenderName;
  final Function(String emoji) onReact;
  final VoidCallback onReply;
  final VoidCallback onPinToggle;
  final VoidCallback onCopy;
  final VoidCallback onDelete;
  final bool isPinned;
  @override
  State<_EnhancedMessageBubble> createState() => _EnhancedMessageBubbleState();
}

class _EnhancedMessageBubbleState extends State<_EnhancedMessageBubble>
    with TickerProviderStateMixin {
  late AnimationController _reactionCtl;
  late Animation<double> _reactionAnim;
  @override
  void initState() {
    super.initState();
    _reactionCtl = AnimationController(vsync: this, duration: 180.ms);
    _reactionAnim =
        CurvedAnimation(parent: _reactionCtl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _reactionCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bubbleColor =
        widget.isMine ? widget.theme.primary : widget.theme.secondaryBackground;
    final textColor = widget.isMine ? Colors.white : widget.theme.primaryText;
    final align =
        widget.isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(widget.isMine ? 18 : 4),
      bottomRight: Radius.circular(widget.isMine ? 4 : 18),
    );
    final timeStr = _format(widget.message.timestamp);
    return Padding(
      padding: EdgeInsets.only(
          top: 4,
          bottom: 4,
          left: widget.isMine ? 80 : 16,
          right: widget.isMine ? 16 : 80),
      child: Column(crossAxisAlignment: align, children: [
        if (widget.showSenderName)
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (widget.showAvatar) ...[
                CircleAvatar(
                  radius: 12,
                  backgroundColor: widget.theme.primary.withOpacity(.1),
                  backgroundImage:
                      widget.message.senderPhotoUrl?.isNotEmpty == true
                          ? CachedNetworkImageProvider(
                              widget.message.senderPhotoUrl!)
                          : null,
                  child: widget.message.senderPhotoUrl?.isEmpty != false
                      ? Icon(Icons.person,
                          size: 16, color: widget.theme.primary)
                      : null,
                ),
                const SizedBox(width: 6)
              ],
              Flexible(
                  child: Text(widget.message.senderName ?? 'Unknown',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: widget.theme.bodySmall.override(
                          color: widget.theme.primary,
                          fontWeight: FontWeight.w600)))
            ]),
          ),
        GestureDetector(
          onLongPress: () => _actions(context),
          onDoubleTap: widget.onReply,
          child: Dismissible(
            key: ValueKey('swipe_${widget.message.id}'),
            direction: widget.isMine
                ? DismissDirection.startToEnd
                : DismissDirection.endToStart,
            confirmDismiss: (_) async {
              widget.onReply();
              return false; // Prevent actual dismissal
            },
            background: Align(
                alignment: widget.isMine
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Icon(Icons.reply, color: widget.theme.primary))),
            child: Container(
              decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: radius,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(.08),
                        blurRadius: 6,
                        offset: const Offset(0, 2))
                  ]),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * .72),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.isPinned) ...[
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.push_pin,
                              size: 14, color: Colors.amber.shade300),
                          const SizedBox(width: 4),
                          Text('Pinned',
                              style: widget.theme.bodySmall.override(
                                  color: textColor.withOpacity(.7),
                                  fontSize: 11))
                        ]),
                        const SizedBox(height: 4)
                      ],
                      if (widget.message.repliedTo != null) ...[
                        Container(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                    color: (widget.isMine
                                            ? Colors.white
                                            : widget.theme.primary)
                                        .withOpacity(.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border(
                                        left: BorderSide(
                                            color: widget.isMine
                                                ? Colors.white
                                                : widget.theme.primary,
                                            width: 3))),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(widget.message.repliedTo!.senderName,
                                          style: widget.theme.bodySmall
                                              .override(
                                                  color: textColor,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 12)),
                                      const SizedBox(height: 2),
                                      Text(
                                          widget.message.repliedTo!.text ??
                                              (widget.message.repliedTo!.isImage
                                                  ? '📷 Photo'
                                                  : widget.message.repliedTo!
                                                          .isVideo
                                                      ? '🎥 Video'
                                                      : 'Media'),
                                          style: widget.theme.bodySmall
                                              .override(
                                                  color:
                                                      textColor.withOpacity(.7),
                                                  fontStyle: FontStyle.italic,
                                                  fontSize: 11),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis)
                                    ])))
                      ],
                      if (widget.message.isImage) ...[
                        ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                                imageUrl: widget.message.imageUrl!,
                                fit: BoxFit.cover,
                                placeholder: (c, _) => Container(
                                    height: 160,
                                    width: 240,
                                    color: Colors.black12,
                                    child: const Center(
                                        child: CircularProgressIndicator())),
                                errorWidget: (c, _, __) => Container(
                                      height: 160,
                                      width: 240,
                                      color: Colors.black12,
                                      alignment: Alignment.center,
                                      child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.broken_image,
                                                size: 32),
                                            const SizedBox(height: 8),
                                            Text('Failed to load image',
                                                style: widget.theme.bodySmall)
                                          ]),
                                    ))),
                        if ((widget.message.text ?? '').isNotEmpty)
                          const SizedBox(height: 8)
                      ],
                      if (widget.message.isVideo) ...[
                        Container(
                            width: 240,
                            height: 160,
                            decoration: BoxDecoration(
                                color: Colors.black12,
                                borderRadius: BorderRadius.circular(12)),
                            child:
                                Stack(alignment: Alignment.center, children: [
                              Icon(Icons.play_circle_fill,
                                  size: 48,
                                  color: Colors.white.withOpacity(.9)),
                              Positioned(
                                  bottom: 8,
                                  left: 8,
                                  child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(.6),
                                          borderRadius:
                                              BorderRadius.circular(4)),
                                      child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.videocam,
                                                color: Colors.white, size: 12),
                                            const SizedBox(width: 4),
                                            Text('Video',
                                                style: widget.theme.bodySmall
                                                    .override(
                                                        color: Colors.white,
                                                        fontSize: 10))
                                          ])))
                            ])),
                        if ((widget.message.text ?? '').isNotEmpty)
                          const SizedBox(height: 8)
                      ],
                      if (widget.message.isLocation) ...[
                        Container(
                            width: 240,
                            height: 120,
                            decoration: BoxDecoration(
                                color: widget.theme.accent2.withOpacity(.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color:
                                        widget.theme.accent2.withOpacity(.3))),
                            child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.location_on,
                                      size: 32, color: widget.theme.error),
                                  const SizedBox(height: 8),
                                  Text('Location',
                                      style: widget.theme.bodyMedium.override(
                                          color: textColor,
                                          fontWeight: FontWeight.w500)),
                                  if (widget.message.location?.address !=
                                      null) ...[
                                    const SizedBox(height: 4),
                                    Text(widget.message.location!.address!,
                                        style: widget.theme.bodySmall.override(
                                            color: textColor.withOpacity(.7)),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center)
                                  ]
                                ])),
                        if ((widget.message.text ?? '').isNotEmpty)
                          const SizedBox(height: 8)
                      ],
                      if (widget.message.hasLinkPreview) ...[
                        Container(
                            decoration: BoxDecoration(
                                color: (widget.isMine
                                        ? Colors.white
                                        : widget.theme.primary)
                                    .withOpacity(.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: (widget.isMine
                                            ? Colors.white
                                            : widget.theme.primary)
                                        .withOpacity(.3))),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (widget.message.linkPreview!.imageUrl !=
                                      null) ...[
                                    ClipRRect(
                                        borderRadius:
                                            const BorderRadius.vertical(
                                                top: Radius.circular(8)),
                                        child: CachedNetworkImage(
                                            imageUrl: widget
                                                .message.linkPreview!.imageUrl!,
                                            height: 120,
                                            width: double.infinity,
                                            fit: BoxFit.cover)),
                                  ],
                                  Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (widget.message.linkPreview!
                                                    .title !=
                                                null) ...[
                                              Text(
                                                  widget.message.linkPreview!
                                                      .title!,
                                                  style: widget.theme.bodyMedium
                                                      .override(
                                                          color: textColor,
                                                          fontWeight:
                                                              FontWeight.w600),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis),
                                              const SizedBox(height: 4)
                                            ],
                                            if (widget.message.linkPreview!
                                                    .description !=
                                                null) ...[
                                              Text(
                                                  widget.message.linkPreview!
                                                      .description!,
                                                  style: widget.theme.bodySmall
                                                      .override(
                                                          color: textColor
                                                              .withOpacity(.7)),
                                                  maxLines: 3,
                                                  overflow:
                                                      TextOverflow.ellipsis),
                                              const SizedBox(height: 4)
                                            ],
                                            Text(
                                                widget.message.linkPreview!.url,
                                                style: widget.theme.bodySmall
                                                    .override(
                                                        color: widget
                                                                .isMine
                                                            ? Colors
                                                                .white
                                                                .withOpacity(.8)
                                                            : widget
                                                                .theme.primary,
                                                        decoration:
                                                            TextDecoration
                                                                .underline),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis)
                                          ]))
                                ])),
                        if ((widget.message.text ?? '').isNotEmpty)
                          const SizedBox(height: 8)
                      ],
                      if ((widget.message.text ?? '').isNotEmpty)
                        SelectableText(widget.message.text!,
                            style: widget.theme.bodyMedium
                                .override(color: textColor))
                    ]),
              ),
            ),
          ),
        ),
        if (widget.message.reactions?.isNotEmpty == true) ...[
          const SizedBox(height: 4),
          Align(
              alignment:
                  widget.isMine ? Alignment.centerRight : Alignment.centerLeft,
              child: Wrap(
                  alignment:
                      widget.isMine ? WrapAlignment.end : WrapAlignment.start,
                  children: [
                    for (final e in widget.message.reactions!.entries)
                      _reactionBubble(e.key, e.value)
                  ]))
        ],
        const SizedBox(height: 4),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(timeStr,
              style: widget.theme.bodySmall
                  .override(color: widget.theme.secondaryText, fontSize: 11)),
          if (widget.message.isEdited) ...[
            const SizedBox(width: 4),
            Text('• edited',
                style: widget.theme.bodySmall.override(
                    color: widget.theme.secondaryText,
                    fontSize: 10,
                    fontStyle: FontStyle.italic))
          ],
          if (widget.isMine) ...[
            const SizedBox(width: 4),
            // Show delivered/read status
            (() {
              final readBy = widget.message.readBy ?? [];
              final deliveredTo = widget.message.deliveredTo ?? [];

              // If anyone has read it (excluding sender), show blue double check
              if (readBy.isNotEmpty) {
                return Icon(Icons.done_all,
                    size: 14, color: widget.theme.primary);
              }
              // If delivered to anyone (excluding sender), show gray double check
              else if (deliveredTo.isNotEmpty) {
                return Icon(Icons.done_all,
                    size: 14, color: widget.theme.secondaryText);
              }
              // Otherwise show single check (sent but not delivered)
              else {
                return Icon(Icons.check,
                    size: 14, color: widget.theme.secondaryText);
              }
            })()
          ]
        ])
      ]),
    );
  }

  Widget _reactionBubble(String emoji, List<String> users) {
    final hasMine = users.contains(currentUserUid);
    return ScaleTransition(
      scale: _reactionAnim,
      child: GestureDetector(
        onTap: () {
          widget.onReact(emoji);
          _reactionCtl.forward().then((_) => _reactionCtl.reverse());
        },
        child: Container(
          margin: const EdgeInsets.only(right: 4, bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: hasMine
                ? widget.theme.primary.withOpacity(.2)
                : widget.theme.secondaryBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: hasMine
                    ? widget.theme.primary
                    : widget.theme.secondaryText.withOpacity(.3),
                width: hasMine ? 1.5 : 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            if (users.length > 1) ...[
              const SizedBox(width: 4),
              Text(users.length.toString(),
                  style: widget.theme.bodySmall.override(
                      color: hasMine
                          ? widget.theme.primary
                          : widget.theme.secondaryText,
                      fontSize: 11,
                      fontWeight: FontWeight.w600))
            ]
          ]),
        ),
      ),
    );
  }

  void _actions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          decoration: BoxDecoration(
              color: widget.theme.secondaryBackground,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: widget.theme.secondaryText.withOpacity(.3),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            Wrap(
                spacing: 4,
                children: ['❤️', '😂', '🔥', '👍', '😮', '😢']
                    .map((e) => GestureDetector(
                          onTap: () {
                            Navigator.pop(ctx);
                            widget.onReact(e);
                          },
                          child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(e,
                                  style: const TextStyle(fontSize: 24))),
                        ))
                    .toList()),
            const Divider(),
            _tile(Icons.reply, 'Reply', widget.onReply, ctx),
            _tile(widget.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                widget.isPinned ? 'Unpin' : 'Pin', widget.onPinToggle, ctx),
            if ((widget.message.text ?? '').isNotEmpty)
              _tile(Icons.copy, 'Copy', widget.onCopy, ctx),
            if (widget.isMine)
              _tile(Icons.delete_outline, 'Delete', widget.onDelete, ctx),
            const SizedBox(height: 8)
          ]),
        ),
      ),
    );
  }

  Widget _tile(IconData i, String l, VoidCallback cb, BuildContext ctx) =>
      ListTile(
        leading: Icon(i, color: widget.theme.primary),
        title: Text(l),
        onTap: () {
          Navigator.pop(ctx);
          cb();
        },
      );
  String _format(DateTime t) {
    final now = DateTime.now();
    final isToday =
        t.year == now.year && t.month == now.month && t.day == now.day;
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final a = t.hour >= 12 ? 'PM' : 'AM';
    return isToday ? '$h:$m $a' : '${t.month}/${t.day} $h:$m $a';
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots({required this.color});
  final Color color;
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with TickerProviderStateMixin {
  late List<AnimationController> _ctls;
  late List<Animation<double>> _anims;
  @override
  void initState() {
    super.initState();
    _ctls = List.generate(
        3, (_) => AnimationController(vsync: this, duration: 600.ms));
    _anims = _ctls
        .map((c) => Tween<double>(begin: .4, end: 1)
            .animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)))
        .toList();
    for (var i = 0; i < _ctls.length; i++) {
      Future.delayed(Duration(milliseconds: i * 200), () {
        if (mounted) _ctls[i].repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _ctls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          3,
          (i) => AnimatedBuilder(
            animation: _anims[i],
            builder: (_, __) => Container(
              margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: widget.color.withOpacity(_anims[i].value),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      );
}

class _IconBtn extends StatelessWidget {
  const _IconBtn(
      {required this.icon,
      required this.tooltip,
      required this.onTap,
      this.color});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final t = FlutterFlowTheme.of(context);
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: color ?? t.secondaryText),
      tooltip: tooltip,
      splashRadius: 20,
    );
  }
}

class _EmojiPicker extends StatelessWidget {
  const _EmojiPicker({required this.onPick, required this.theme});
  final void Function(String) onPick;
  final FlutterFlowTheme theme;
  @override
  Widget build(BuildContext context) {
    final emojis = [
      '😀',
      '😃',
      '😄',
      '😁',
      '😆',
      '😅',
      '😂',
      '🤣',
      '😊',
      '😇',
      '🙂',
      '🙃',
      '😉',
      '😍',
      '🥰',
      '😘',
      '😗',
      '😙',
      '😚',
      '😋',
      '😛',
      '😝',
      '😜',
      '🤪',
      '🤨',
      '🧐',
      '🤓',
      '😎',
      '🤩',
      '🥳',
      '😏',
      '😒',
      '😞',
      '😔',
      '😟',
      '😕',
      '🙁',
      '☹️',
      '😣',
      '😖',
      '😫',
      '😩',
      '🥺',
      '😢',
      '😭',
      '😤',
      '😠',
      '😡',
      '🤬',
      '🤯',
      '😳',
      '🥵',
      '🥶',
      '😱',
      '😨',
      '😰',
      '😥',
      '😓',
      '🤗',
      '🤔',
      '🤭',
      '🤫',
      '🤥',
      '😶',
      '😐',
      '😑',
      '😬',
      '🙄',
      '😯',
      '😦',
      '😧',
      '😮',
      '😲',
      '🥱',
      '😴',
      '🤤',
      '😪',
      '😵',
      '🤐'
    ];
    return Container(
      height: 250,
      color: theme.secondaryBackground,
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Container(
          height: 4,
          width: 40,
          decoration: BoxDecoration(
            color: theme.secondaryText.withOpacity(.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8, mainAxisSpacing: 8, crossAxisSpacing: 8),
            itemCount: emojis.length,
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => onPick(emojis[i]),
              child: Center(
                  child: Text(emojis[i], style: const TextStyle(fontSize: 24))),
            ),
          ),
        )
      ]),
    );
  }
}

class _AttachmentOptionsSheet extends StatelessWidget {
  const _AttachmentOptionsSheet({
    required this.onImageTap,
    required this.onVideoTap,
    required this.onLocationTap,
    required this.theme,
  });
  final VoidCallback onImageTap;
  final VoidCallback onVideoTap;
  final VoidCallback onLocationTap;
  final FlutterFlowTheme theme;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(
              height: 4,
              width: 40,
              decoration: BoxDecoration(
                  color: theme.secondaryText.withOpacity(.3),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              _AttachmentOption(
                icon: Icons.image_rounded,
                label: 'Photo',
                color: theme.primary,
                onTap: () {
                  Navigator.of(context).pop();
                  onImageTap();
                },
              ),
              const SizedBox(height: 16),
              _AttachmentOption(
                icon: Icons.videocam_rounded,
                label: 'Video',
                color: theme.error,
                onTap: () {
                  Navigator.of(context).pop();
                  onVideoTap();
                },
              ),
              const SizedBox(height: 16),
              _AttachmentOption(
                icon: Icons.location_on_rounded,
                label: 'Location',
                color: theme.tertiary,
                onTap: () {
                  Navigator.of(context).pop();
                  onLocationTap();
                },
              ),
            ]),
          ),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}

class _AttachmentOption extends StatelessWidget {
  const _AttachmentOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = FlutterFlowTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(.3)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Text(label,
              style: t.titleMedium
                  .override(color: t.primaryText, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
