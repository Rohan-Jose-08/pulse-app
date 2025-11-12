import 'dart:async';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:confetti/confetti.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:characters/characters.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:image_picker/image_picker.dart';
import '../../auth/firebase_auth/auth_util.dart';
import '../../backend/api_service.dart';
import '../../backend/socket_service.dart';
import '../../backend/chat_transport.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import '../../components/skeleton_loader.dart';
import '../../components/error_state_widget.dart';
import '../../components/micro_interactions.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/snackbar_utils.dart';
import 'package:permission_handler/permission_handler.dart';
import '../calling/group_call_screen.dart';
import 'group_chat_info_page.dart';

/// 🎨 REDESIGNED: Modern, polished group chat with enhanced UX
///
/// Key improvements:
/// - Skeleton loading states
/// - Haptic feedback throughout
/// - Smooth animations
/// - Better error handling
/// - Modern design language
/// - Enhanced reactions UI
/// - Improved messaging experience
class LiveGroupChatPage extends ConsumerStatefulWidget {
  const LiveGroupChatPage({
    super.key,
    required this.chatId,
    required this.groupName,
    this.pulseName,
    this.members,
  });
  final String chatId;
  final String groupName;
  final String? pulseName;
  final List<Map<String, dynamic>>? members;

  @override
  ConsumerState<LiveGroupChatPage> createState() => _LiveGroupChatPageState();
}

class _LiveGroupChatPageState extends ConsumerState<LiveGroupChatPage>
    with TickerProviderStateMixin {
  // Controllers
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _reactionInputCtl = TextEditingController();
  final _reactionFocus = FocusNode();
  late ConfettiController _confetti;

  // State
  final List<_LiveMsg> _messages = [];
  final StreamController<_FloatingReaction> _floatingCtl =
      StreamController.broadcast();
  bool _sending = false;
  bool _isLoading = true;
  bool _hasError = false;
  int _messageCount = 0;
  Timer? _typingDebounce;
  bool _someoneTyping = false;
  final _random = Random();
  String? _reactingToMessageId;

  // Pulse status
  bool _isPulseLive = true;
  DateTime? _pulseActiveFrom;
  DateTime? _pulseActiveUntil;

  // Active call state
  bool _isCallActive = false;
  bool _isCallVideo = true;
  int _callParticipantCount = 0;
  List<String> _callParticipants = [];

  // Socket subscriptions
  StreamSubscription<Map<String, dynamic>>? _msgSub;
  StreamSubscription<Map<String, dynamic>>? _typingSub;
  StreamSubscription<Map<String, dynamic>>? _ackSub;
  StreamSubscription<Map<String, dynamic>>? _gcStartedSub;
  StreamSubscription<Map<String, dynamic>>? _gcStoppedSub;
  StreamSubscription<Map<String, dynamic>>? _gcParticipantsSub;
  StreamSubscription<Map<String, dynamic>>? _gcParticipantJoinedSub;
  StreamSubscription<Map<String, dynamic>>? _gcParticipantLeftSub;
  late String _chatId;

  // Bluetooth transport mode
  ChatTransportMode _transportMode = ChatTransportMode.network;

  // Member index
  late final Map<String, Map<String, dynamic>> _memberIndex = {
    for (final m in (widget.members ?? []))
      (m['id'] ?? m['userId'] ?? m['uid']).toString(): m
  };

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 2));
    _chatId = widget.chatId;
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      // Initialize transport manager
      _transportMode = ChatTransportManager.instance.mode;
      await ChatTransportManager.instance.ensureConnected();

      // Connect socket for network mode
      if (_transportMode == ChatTransportMode.network) {
        await SocketService.instance.connect();
      }

      // Setup listeners ASAP to avoid missing early events
      _setupSocketListeners();

      // Join the requested conversation room (may be normalized later)
      ChatTransportManager.instance.active.joinConversation(_chatId);

      // Load messages and normalize conversation id if needed
      await _bootstrap();

      if (mounted) {
        setState(() => _isLoading = false);
        await HapticUtils.light();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
        await HapticUtils.error();
        CustomSnackbar.showError(
          context,
          message: 'Failed to load chat',
          actionLabel: 'Retry',
          onAction: _initializeChat,
        );
      }
    }
  }

  void _setupSocketListeners() {
    // Use ChatTransportManager for messages and typing
    final transport = ChatTransportManager.instance.active;

    _msgSub = transport.messages.listen(_onSocketMessage);
    _typingSub = transport.typing.listen(_onTyping);

    // For network mode, also listen to socket acks for conversation ID normalization
    if (_transportMode == ChatTransportMode.network) {
      _ackSub = SocketService.instance.acks.listen((ack) {
        try {
          final cid = (ack['conversationId'] ?? ack['id'])?.toString();
          if (cid != null && cid.isNotEmpty && cid != _chatId) {
            // Leave old room and join canonical conversation id from ack
            final old = _chatId;
            setState(() => _chatId = cid);
            if (old.isNotEmpty) {
              SocketService.instance.leaveConversation(old);
            }
            SocketService.instance.joinConversation(_chatId);
          }
        } catch (_) {}
      });
    }

    // Listen for group call events to show Discord-style status bar
    _gcStartedSub = SocketService.instance.groupCallStarted.listen((m) async {
      try {
        if (m['conversationId']?.toString() != _chatId) return;
        final isVideo = m['isVideo'] == true;

        // Update state to show call banner
        if (mounted) {
          setState(() {
            _isCallActive = true;
            _isCallVideo = isVideo;
            _callParticipantCount = 0;
            _callParticipants = [];
          });

          // Light haptic feedback
          await HapticUtils.light();
        }
      } catch (_) {}
    });

    _gcStoppedSub = SocketService.instance.groupCallStopped.listen((m) async {
      try {
        if (m['conversationId']?.toString() != _chatId) return;

        if (mounted) {
          setState(() {
            _isCallActive = false;
            _callParticipantCount = 0;
            _callParticipants = [];
          });
        }
      } catch (_) {}
    });

    _gcParticipantsSub =
        SocketService.instance.groupCallParticipants.listen((m) async {
      try {
        if (m['conversationId']?.toString() != _chatId) return;
        final participants = (m['participants'] as List?)?.cast<String>() ?? [];

        if (mounted) {
          setState(() {
            _callParticipants = participants;
            _callParticipantCount = participants.length;
            if (participants.isNotEmpty) _isCallActive = true;
          });
        }
      } catch (_) {}
    });

    _gcParticipantJoinedSub =
        SocketService.instance.groupCallParticipantJoined.listen((m) async {
      try {
        if (m['conversationId']?.toString() != _chatId) return;
        final userId = m['userId']?.toString();

        if (userId != null && mounted) {
          setState(() {
            if (!_callParticipants.contains(userId)) {
              _callParticipants.add(userId);
              _callParticipantCount = _callParticipants.length;
            }
          });
        }
      } catch (_) {}
    });

    _gcParticipantLeftSub =
        SocketService.instance.groupCallParticipantLeft.listen((m) async {
      try {
        if (m['conversationId']?.toString() != _chatId) return;
        final userId = m['userId']?.toString();

        if (userId != null && mounted) {
          setState(() {
            _callParticipants.remove(userId);
            _callParticipantCount = _callParticipants.length;
          });
        }
      } catch (_) {}
    });

    // Listen for call status updates (sent when joining conversation)
    SocketService.instance.groupCallStatus.listen((m) async {
      try {
        if (m['conversationId']?.toString() != _chatId) return;
        final isActive = m['isActive'] == true;
        final isVideo = m['isVideo'] == true;
        final participants = (m['participants'] as List?)?.cast<String>() ?? [];

        if (mounted && isActive) {
          setState(() {
            _isCallActive = true;
            _isCallVideo = isVideo;
            _callParticipants = participants;
            _callParticipantCount = participants.length;
          });
          print(
              '[LiveGroupChat] Restored active call state: ${participants.length} participants');
        }
      } catch (_) {}
    });
  }

  Future<void> _bootstrap() async {
    print('[LiveGroupChat] Bootstrap starting with chatId: $_chatId');

    // Use ChatTransportManager for loading initial messages
    final rawMessages =
        await ChatTransportManager.instance.initialMessages(_chatId);
    final msgs = rawMessages.map((m) => _LiveMsg.fromJson(m)).toList();

    print('[LiveGroupChat] Loaded ${msgs.length} messages');

    // If API returns messages with a canonical conversationId that differs,
    // switch rooms so live updates arrive for this chat (network mode only).
    if (_transportMode == ChatTransportMode.network && msgs.isNotEmpty) {
      final canonicalId = msgs.first.conversationId;
      if (canonicalId != null &&
          canonicalId.isNotEmpty &&
          canonicalId != _chatId) {
        final old = _chatId;
        print(
            '[LiveGroupChat] Switching conversation ID from $old to $canonicalId');
        setState(() => _chatId = canonicalId);
        if (old.isNotEmpty) {
          SocketService.instance.leaveConversation(old);
        }
        SocketService.instance.joinConversation(_chatId);
      }
    }

    setState(() => _messages.addAll(msgs));

    // Fetch pulse status if this is a pulse group chat
    if (widget.pulseName != null && widget.pulseName!.isNotEmpty) {
      await _fetchPulseStatus();
    }

    // Check for active group calls
    await _checkActiveCall();

    _jumpBottom();
    print('[LiveGroupChat] Bootstrap complete, final chatId: $_chatId');
  }

  /// Check if there's an active group call when entering the chat
  Future<void> _checkActiveCall() async {
    try {
      // Simply listen for the socket events - if there's an active call,
      // the groupcall:started event would have been emitted already and stored.
      // The listeners will update state if new events come in.

      // For now, we rely on the backend to maintain state and broadcast updates.
      // When someone starts/joins/leaves a call, we'll get notified via socket.
      print('[LiveGroupChat] Active call listeners set up for $_chatId');
    } catch (e) {
      print('[LiveGroupChat] Error checking active call: $e');
    }
  }

  Future<void> _fetchPulseStatus() async {
    try {
      final pulseData =
          await ApiService.instance.getPulseById(widget.pulseName!);
      if (pulseData != null) {
        final now = DateTime.now();
        DateTime? activeFrom;
        DateTime? activeUntil;

        final activeFromStr = pulseData['activeFrom'];
        if (activeFromStr != null) {
          activeFrom = DateTime.tryParse(activeFromStr.toString());
        }

        final activeUntilStr = pulseData['activeUntil'];
        if (activeUntilStr != null) {
          activeUntil = DateTime.tryParse(activeUntilStr.toString());
        }

        bool isLive = true;
        if (activeFrom != null && now.isBefore(activeFrom)) {
          isLive = false; // hasn't started yet
        } else if (activeUntil != null && now.isAfter(activeUntil)) {
          isLive = false; // has ended
        }

        setState(() {
          _isPulseLive = isLive;
          _pulseActiveFrom = activeFrom;
          _pulseActiveUntil = activeUntil;
        });
      }
    } catch (e) {
      print('Error fetching pulse status: $e');
      // Keep default state (live)
    }
  }

  void _onSocketMessage(dynamic raw) {
    try {
      final map = Map<String, dynamic>.from(raw as Map);
      print(
          '[LiveGroupChat] Received socket message: ${map['id']}, conversationId: ${map['conversationId']}, expected: $_chatId');

      if (map['conversationId'] != _chatId) {
        print('[LiveGroupChat] Message ignored - wrong conversation');
        return;
      }

      final maybeId = map['id']?.toString() ?? map['messageId']?.toString();

      // Handle reaction updates
      if (maybeId != null && map['reactions'] != null) {
        _handleReactionUpdate(maybeId, map['reactions']);
        return;
      }

      // Handle incremental reactions
      if (maybeId != null && map['emoji'] != null && map['userId'] != null) {
        _handleIncrementalReaction(maybeId, map['emoji'], map['userId']);
        return;
      }

      // New message - check for duplicates
      final msg = _LiveMsg.fromJson(map);

      // Prevent duplicate messages
      final isDuplicate = _messages.any((m) => m.id == msg.id);
      if (isDuplicate) {
        print('[LiveGroupChat] Duplicate message ignored: ${msg.id}');
        return;
      }

      print('[LiveGroupChat] Adding new message: ${msg.id}');
      setState(() => _messages.add(msg));
      _messageCount++;
      _maybeCelebrate();
      _animateInReactionAuto(msg);
      _autoScroll();

      // ✨ UX: Haptic feedback for new messages
      HapticUtils.light();
    } catch (e) {
      print('[LiveGroupChat] Error processing socket message: $e');
    }
  }

  void _handleReactionUpdate(String messageId, dynamic reactions) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      final parsed = _parseReactions(reactions);
      if (parsed.isNotEmpty) {
        final updated = _messages[idx].copyWith(reactions: parsed);
        setState(() => _messages[idx] = updated);
      }
    }
  }

  void _handleIncrementalReaction(
      String messageId, dynamic emoji, dynamic userId) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      final emojiStr = emoji.toString();
      final userIdStr = userId.toString();
      final current = Map<String, List<String>>.from(_messages[idx].reactions);
      final list = List<String>.from(current[emojiStr] ?? []);

      if (list.contains(userIdStr)) {
        list.remove(userIdStr);
      } else {
        list.add(userIdStr);
      }

      if (list.isEmpty) {
        current.remove(emojiStr);
      } else {
        current[emojiStr] = list;
      }

      setState(
          () => _messages[idx] = _messages[idx].copyWith(reactions: current));
    }
  }

  void _onTyping(dynamic raw) {
    try {
      final map = Map<String, dynamic>.from(raw as Map);
      if (map['conversationId'] != _chatId) return;
      final isOther = map['userId'] != currentUserUid;
      if (isOther) {
        setState(() => _someoneTyping = map['isTyping'] == true);
      }
    } catch (_) {}
  }

  void _autoScroll() {
    if (!_scroll.hasClients) return;
    final nearBottom =
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 160;
    if (nearBottom) {
      Future.delayed(40.ms, _animateToBottom);
    }
  }

  void _jumpBottom() {
    if (!_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent + 200);
      }
    });
  }

  Future<void> _animateToBottom() async {
    if (!_scroll.hasClients) return;
    await _scroll.animateTo(
      _scroll.position.maxScrollExtent + 120,
      duration: 300.ms,
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    final txt = _input.text.trim();
    if (txt.isEmpty || _sending) return;

    print('[LiveGroupChat] Sending message to conversation: $_chatId');
    setState(() => _sending = true);

    // ✨ UX: Haptic feedback on send
    await HapticUtils.medium();

    try {
      // Ensure transport is connected before sending
      await ChatTransportManager.instance.ensureConnected();

      print('[LiveGroupChat] Transport connected, sending message');
      ChatTransportManager.instance.active.sendMessage(
        conversationId: _chatId,
        text: txt,
      );
      _input.clear();
      _setTyping(false);

      // Wait a bit for the message to propagate before scrolling
      await Future.delayed(const Duration(milliseconds: 100));
      _animateToBottom();

      print('[LiveGroupChat] Message sent successfully');
      // ✨ UX: Success feedback
      await HapticUtils.light();
    } catch (e) {
      print('[LiveGroupChat] Error sending message: $e');
      // ✨ UX: Error feedback
      await HapticUtils.error();
      if (mounted) {
        CustomSnackbar.showError(
          context,
          message: 'Failed to send message',
          actionLabel: 'Retry',
          onAction: () {
            _input.text = txt;
            _send();
          },
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _setTyping(bool v) {
    ChatTransportManager.instance.active.setTyping(_chatId, v);
  }

  Future<void> _toggleTransportMode() async {
    await HapticUtils.selection();

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final t = FlutterFlowTheme.of(context);
        return Container(
          decoration: BoxDecoration(
            color: t.secondaryBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: t.secondaryText.withOpacity(.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Choose Connection Mode',
                    style:
                        t.headlineSmall.override(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Icon(Icons.wifi_rounded, color: t.primary),
                title: const Text('Network (Wi-Fi / Mobile Data)'),
                subtitle: const Text('Full-featured with cloud sync'),
                trailing: _transportMode == ChatTransportMode.network
                    ? Icon(Icons.check, color: t.primary)
                    : null,
                onTap: () async {
                  Navigator.pop(context);
                  if (_transportMode != ChatTransportMode.network) {
                    await _switchTransportMode(ChatTransportMode.network);
                  }
                },
              ),
              ListTile(
                leading:
                    Icon(Icons.bluetooth_rounded, color: Colors.blueAccent),
                title: const Text('Bluetooth Mesh (Experimental)'),
                subtitle: const Text('Peer-to-peer local messaging'),
                trailing: _transportMode == ChatTransportMode.bluetooth
                    ? const Icon(Icons.check, color: Colors.blueAccent)
                    : null,
                onTap: () async {
                  Navigator.pop(context);
                  if (_transportMode != ChatTransportMode.bluetooth) {
                    await _switchTransportMode(ChatTransportMode.bluetooth);
                  }
                },
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(
                  'Bluetooth mode is experimental – messages are kept locally and broadcast to nearby devices.',
                  style: t.bodySmall.override(color: t.secondaryText),
                ),
              )
            ]),
          ),
        );
      },
    );
  }

  Future<void> _switchTransportMode(ChatTransportMode newMode) async {
    setState(() => _transportMode = newMode);
    ChatTransportManager.instance.mode = newMode;

    // Cancel existing subscriptions
    await _msgSub?.cancel();
    await _typingSub?.cancel();
    await _ackSub?.cancel();

    // Reconnect with new transport
    await ChatTransportManager.instance.ensureConnected();

    // Re-setup listeners with new transport
    final transport = ChatTransportManager.instance.active;
    _msgSub = transport.messages.listen(_onSocketMessage);
    _typingSub = transport.typing.listen(_onTyping);

    // Join conversation with new transport
    transport.joinConversation(_chatId);

    if (mounted) {
      CustomSnackbar.showInfo(
        context,
        message: newMode == ChatTransportMode.bluetooth
            ? 'Switched to Bluetooth mode'
            : 'Switched to Network mode',
      );
    }
  }

  String _buildStatusText() {
    final messageCount = '${_messages.length} messages';
    final memberCount = '${_memberIndex.length} members';

    final now = DateTime.now();

    // Check if pulse hasn't started yet
    if (_pulseActiveFrom != null && now.isBefore(_pulseActiveFrom!)) {
      final timeUntilStart = _pulseActiveFrom!.difference(now);
      if (timeUntilStart.inHours > 0) {
        return '$messageCount • $memberCount • Starts in ${timeUntilStart.inHours}h';
      } else if (timeUntilStart.inMinutes > 0) {
        return '$messageCount • $memberCount • Starts in ${timeUntilStart.inMinutes}m';
      }
    }

    // If we have pulse end time and it's live, show time left
    if (_pulseActiveUntil != null) {
      if (_isPulseLive) {
        final timeLeft = _pulseActiveUntil!.difference(now);
        if (timeLeft.inHours > 0) {
          return '$messageCount • $memberCount • Ends in ${timeLeft.inHours}h';
        } else if (timeLeft.inMinutes > 0) {
          return '$messageCount • $memberCount • Ends in ${timeLeft.inMinutes}m';
        }
      } else {
        // Pulse has ended
        return '$messageCount • $memberCount • Event ended';
      }
    }

    return '$messageCount • $memberCount';
  }

  Map<String, dynamic> _getPulseBadgeInfo() {
    final now = DateTime.now();

    // Check if pulse hasn't started yet
    if (_pulseActiveFrom != null && now.isBefore(_pulseActiveFrom!)) {
      return {
        'text': 'SOON',
        'icon': Icons.schedule,
        'isLive': false,
        'color': 'warning',
      };
    }

    // Check if pulse is live
    if (_isPulseLive) {
      return {
        'text': 'LIVE',
        'icon': Icons.circle,
        'isLive': true,
        'color': 'primary',
      };
    }

    // Pulse has ended
    return {
      'text': 'ENDED',
      'icon': Icons.timer_off,
      'isLive': false,
      'color': 'secondary',
    };
  }

  void _maybeCelebrate() {
    if (_messageCount == 100 ||
        _messageCount == 250 ||
        _messageCount % 500 == 0) {
      _confetti.play();
      HapticUtils.success();
    }
  }

  void _animateInReactionAuto(_LiveMsg msg) {
    if ((msg.text ?? '').contains('🔥')) {
      _spawnReaction('🔥');
    }
  }

  void _spawnReaction(String emoji) {
    _floatingCtl.add(_FloatingReaction(
      emoji: emoji,
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      startX: _random.nextDouble(),
      drift: (_random.nextDouble() * .4) - .2,
      durationMs: 2600 + _random.nextInt(1600),
      scale: .8 + _random.nextDouble() * .8,
    ));
  }

  Future<void> _quickReaction(String emoji) async {
    // ✨ UX: Haptic feedback on reaction
    await HapticUtils.light();
    _spawnReaction(emoji);
    ChatTransportManager.instance.active
        .sendMessage(conversationId: _chatId, text: emoji);
  }

  void _openAddMembers() async {
    // ✨ UX: Haptic feedback
    await HapticUtils.selection();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddMembersSheet(
        chatId: _chatId,
        pulseName: widget.pulseName,
      ),
    );
  }

  void _openChatInfo() async {
    // ✨ UX: Haptic feedback
    await HapticUtils.selection();

    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupChatInfoPage(
          chatId: _chatId,
          groupName: widget.groupName,
          pulseName: widget.pulseName,
          members: widget.members ?? [],
          isPulseLive: _isPulseLive,
          pulseActiveFrom: _pulseActiveFrom,
          pulseActiveUntil: _pulseActiveUntil,
        ),
      ),
    );
  }

  Future<void> _chooseAttachment() async {
    // ✨ UX: Haptic feedback
    await HapticUtils.selection();

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = FlutterFlowTheme.of(context);
        return Container(
          decoration: BoxDecoration(
            color: theme.secondaryBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.secondaryText.withOpacity(.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: Icon(Icons.image_rounded, color: theme.primary),
                  title: const Text('Send image'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _sendImage();
                  },
                ),
                ListTile(
                  leading: Icon(Icons.videocam_rounded, color: theme.primary),
                  title: const Text('Send video'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _sendVideo();
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _sendImage() async {
    try {
      // ✨ UX: Haptic feedback
      await HapticUtils.light();

      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (file == null) return;

      // Show uploading indicator
      if (mounted) {
        CustomSnackbar.showInfo(
          context,
          message: 'Uploading image...',
        );
      }

      final bytes = await file.readAsBytes();
      final storageRef = FirebaseStorage.instance.ref().child(
          'chat_uploads/$_chatId/${DateTime.now().millisecondsSinceEpoch}_${file.name}');
      final uploadTask = await storageRef.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await uploadTask.ref.getDownloadURL();

      ChatTransportManager.instance.active.sendMessage(
        conversationId: _chatId,
        imageUrl: url,
      );

      _animateToBottom();

      // ✨ UX: Success feedback
      await HapticUtils.success();
    } on PlatformException catch (_) {
      // User may have denied permission; no-op UX
    } catch (e) {
      // ✨ UX: Error feedback
      await HapticUtils.error();
      if (mounted) {
        CustomSnackbar.showError(
          context,
          message: 'Failed to send image',
          actionLabel: 'Retry',
          onAction: _sendImage,
        );
      }
    }
  }

  Future<void> _sendVideo() async {
    try {
      // ✨ UX: Haptic feedback
      await HapticUtils.light();

      final picker = ImagePicker();
      final file = await picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 3),
      );
      if (file == null) return;

      // Show uploading indicator
      if (mounted) {
        CustomSnackbar.showInfo(
          context,
          message: 'Uploading video...',
        );
      }

      final bytes = await file.readAsBytes();
      final storageRef = FirebaseStorage.instance.ref().child(
          'chat_uploads/$_chatId/${DateTime.now().millisecondsSinceEpoch}_${file.name}');
      final uploadTask = await storageRef.putData(
        bytes,
        SettableMetadata(contentType: 'video/mp4'),
      );
      final url = await uploadTask.ref.getDownloadURL();

      ChatTransportManager.instance.active.sendMessage(
        conversationId: _chatId,
        videoUrl: url,
      );

      _animateToBottom();

      // ✨ UX: Success feedback
      await HapticUtils.success();
    } on PlatformException catch (_) {
      // Permission denied; no-op
    } catch (e) {
      // ✨ UX: Error feedback
      await HapticUtils.error();
      if (mounted) {
        CustomSnackbar.showError(
          context,
          message: 'Failed to send video',
          actionLabel: 'Retry',
          onAction: _sendVideo,
        );
      }
    }
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    _reactionInputCtl.dispose();
    _reactionFocus.dispose();
    _floatingCtl.close();
    _confetti.dispose();
    SocketService.instance.leaveConversation(_chatId);
    _msgSub?.cancel();
    _typingSub?.cancel();
    _ackSub?.cancel();
    _gcStartedSub?.cancel();
    _gcStoppedSub?.cancel();
    _gcParticipantsSub?.cancel();
    _gcParticipantJoinedSub?.cancel();
    _gcParticipantLeftSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => _focus.unfocus(),
      child: Scaffold(
        backgroundColor: theme.primaryBackground,
        body: _buildBody(theme, isDark),
      ),
    );
  }

  Widget _buildBody(FlutterFlowTheme theme, bool isDark) {
    // ✨ UX: Loading state with skeleton
    if (_isLoading) {
      return Column(
        children: [
          _topBar(theme, isDark),
          Expanded(
            child: SkeletonListView(
              itemCount: 8,
              itemBuilder: (context, index) => Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: index % 2 == 0
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.end,
                  children: [
                    if (index % 2 == 0) ...[
                      const SkeletonLoader(
                        width: 32,
                        height: 32,
                        borderRadius: BorderRadius.all(Radius.circular(16)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: SkeletonLoader(
                        width: MediaQuery.of(context).size.width * 0.6,
                        height: 60,
                        borderRadius:
                            const BorderRadius.all(Radius.circular(18)),
                      ),
                    ),
                    if (index % 2 != 0) ...[
                      const SizedBox(width: 8),
                      const SkeletonLoader(
                        width: 32,
                        height: 32,
                        borderRadius: BorderRadius.all(Radius.circular(16)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    // ✨ UX: Error state with retry
    if (_hasError) {
      return Column(
        children: [
          _topBar(theme, isDark),
          Expanded(
            child: ErrorStateWidget(
              title: 'Connection Failed',
              message: 'Unable to load chat messages',
              icon: Icons.chat_bubble_outline_rounded,
              onRetry: _initializeChat,
            ),
          ),
        ],
      );
    }

    // Main chat UI
    return Stack(
      children: [
        Column(
          children: [
            _topBar(theme, isDark),
            // Discord-style active call status bar
            if (_isCallActive) _callStatusBar(theme),
            Expanded(child: _chatFeed(theme)),
            if (_someoneTyping) _typingBubble(theme),
            // Quick reactions removed
            _composer(theme),
          ],
        ),
        _floatingReactionsLayer(),
        _confettiWidget(theme),
        // Emoji reaction overlay removed
      ],
    );
  }

  Widget _topBar(FlutterFlowTheme t, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 42, 12, 12),
      decoration: BoxDecoration(
        color: t.secondaryBackground,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? .3 : .06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        children: [
          // ✨ UX: Haptic back button
          HapticIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            color: t.primaryText,
            onPressed: () => Navigator.of(context).maybePop(),
            feedbackType: HapticsType.light,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      flex: 1,
                      child: Text(
                        widget.groupName,
                        style: t.titleMedium.override(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    // ✨ Pulse status badge (LIVE, SOON, or ENDED)
                    Builder(
                      builder: (context) {
                        final badgeInfo = _getPulseBadgeInfo();
                        final isLive = badgeInfo['isLive'] as bool;
                        final text = badgeInfo['text'] as String;
                        final icon = badgeInfo['icon'] as IconData;
                        final colorType = badgeInfo['color'] as String;

                        Color getBadgeColor() {
                          switch (colorType) {
                            case 'primary':
                              return t.primary;
                            case 'warning':
                              return t.warning;
                            case 'secondary':
                            default:
                              return t.secondaryText;
                          }
                        }

                        return PulseAnimation(
                          enabled: isLive,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              gradient: isLive
                                  ? LinearGradient(
                                      colors: [t.primary, t.tertiary],
                                    )
                                  : null,
                              color: isLive ? null : getBadgeColor(),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: isLive
                                  ? [
                                      BoxShadow(
                                        color: t.primary.withOpacity(.35),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      )
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  icon,
                                  color: Colors.white,
                                  size: icon == Icons.circle ? 8 : 12,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  text,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _buildStatusText(),
                  style: t.bodySmall.override(
                    color: t.secondaryText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // Action buttons with haptic feedback - minimized to prevent overflow
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HapticIconButton(
                icon: Icons.videocam_rounded,
                color: t.primaryText,
                onPressed: _startVideoCall,
                feedbackType: HapticsType.selection,
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: t.primaryText),
                onSelected: (value) {
                  if (value == 'transport') {
                    _toggleTransportMode();
                  } else if (value == 'voice_call') {
                    _startVoiceCall();
                  } else if (value == 'add_members') {
                    _openAddMembers();
                  } else if (value == 'info') {
                    _openChatInfo();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'voice_call',
                    child: Row(
                      children: [
                        Icon(Icons.call_rounded, color: t.primaryText),
                        const SizedBox(width: 12),
                        const Text('Voice Call'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'transport',
                    child: Row(
                      children: [
                        Icon(
                          _transportMode == ChatTransportMode.bluetooth
                              ? Icons.bluetooth_rounded
                              : Icons.wifi_rounded,
                          color: _transportMode == ChatTransportMode.bluetooth
                              ? Colors.blueAccent
                              : t.primaryText,
                        ),
                        const SizedBox(width: 12),
                        Text(_transportMode == ChatTransportMode.bluetooth
                            ? 'Switch to Network'
                            : 'Switch to Bluetooth'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'add_members',
                    child: Row(
                      children: [
                        Icon(Icons.person_add_alt_1_rounded,
                            color: t.primaryText),
                        const SizedBox(width: 12),
                        const Text('Add Members'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'info',
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, color: t.primaryText),
                        const SizedBox(width: 12),
                        const Text('Chat Info'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Discord-style active call status bar
  Widget _callStatusBar(FlutterFlowTheme t) {
    return GestureDetector(
      onTap: () async {
        // Join the active call
        await HapticUtils.medium();

        if (_isCallVideo) {
          final res =
              await [Permission.microphone, Permission.camera].request();
          if (res[Permission.microphone]?.isGranted != true ||
              res[Permission.camera]?.isGranted != true) {
            if (mounted) {
              CustomSnackbar.showWarning(
                context,
                message: 'Camera and microphone permissions required',
              );
            }
            return;
          }
        } else {
          final p = await Permission.microphone.request();
          if (!p.isGranted) {
            if (mounted) {
              CustomSnackbar.showWarning(
                context,
                message: 'Microphone permission required',
              );
            }
            return;
          }
        }

        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => GroupCallScreen(
              conversationId: _chatId,
              isVideo: _isCallVideo,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              (_isCallVideo ? Colors.purple : Colors.green).withOpacity(0.85),
              (_isCallVideo ? Colors.deepPurple : Colors.teal)
                  .withOpacity(0.85),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: (_isCallVideo ? Colors.purple : Colors.green)
                  .withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Row(
          children: [
            // Animated pulsing indicator
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.8, end: 1.2),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeInOut,
              builder: (context, scale, child) {
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isCallVideo
                          ? Icons.videocam_rounded
                          : Icons.call_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                );
              },
              onEnd: () {
                // Restart animation
                if (mounted) setState(() {});
              },
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isCallVideo ? 'Video Call Active' : 'Voice Call Active',
                    style: t.titleSmall.override(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _callParticipantCount > 0
                        ? '$_callParticipantCount ${_callParticipantCount == 1 ? "person" : "people"} in call'
                        : 'Tap to join',
                    style: t.bodySmall.override(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // Join button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: _isCallVideo ? Colors.purple : Colors.green,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Join',
                    style: t.bodyMedium.override(
                      color: _isCallVideo ? Colors.purple : Colors.green,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().slideY(begin: -1, duration: 300.ms, curve: Curves.easeOut);
  }

  Future<void> _startVoiceCall() async {
    final p = await Permission.microphone.request();
    if (!p.isGranted) {
      if (mounted) {
        CustomSnackbar.showWarning(
          context,
          message: 'Microphone permission required',
        );
      }
      return;
    }
    if (!mounted) return;

    await HapticUtils.medium();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupCallScreen(
          conversationId: _chatId,
          isVideo: false,
        ),
      ),
    );
  }

  Future<void> _startVideoCall() async {
    final res = await [Permission.microphone, Permission.camera].request();
    final micOk = res[Permission.microphone]?.isGranted == true;
    final camOk = res[Permission.camera]?.isGranted == true;

    if (!micOk || !camOk) {
      if (mounted) {
        CustomSnackbar.showWarning(
          context,
          message: 'Camera and microphone permissions required',
        );
      }
      return;
    }
    if (!mounted) return;

    await HapticUtils.medium();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupCallScreen(
          conversationId: _chatId,
          isVideo: true,
        ),
      ),
    );
  }

  Widget _chatFeed(FlutterFlowTheme t) {
    // ✨ UX: Empty state
    if (_messages.isEmpty) {
      return EmptyStateWidget(
        title: 'Start the Conversation!',
        message: 'Be the first to send a message in this group',
        icon: Icons.chat_bubble_outline_rounded,
      );
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final m = _messages[i];
        final prev = i > 0 ? _messages[i - 1] : null;
        final showHeader = prev == null || prev.senderId != m.senderId;

        // ✨ UX: Slide-in animation for messages
        return SlideInAnimation(
          index: i,
          delay: const Duration(milliseconds: 30),
          child: _messageBubble(m, showHeader, t),
        );
      },
    );
  }

  Widget _messageBubble(_LiveMsg m, bool header, FlutterFlowTheme t) {
    final mine = m.senderId == currentUserUid;
    final name = _resolveName(m.senderId) ?? 'User';

    return GestureDetector(
      onDoubleTap: () => _quickReaction('❤️'),
      // Long press reaction removed
      child: Container(
        margin: EdgeInsets.only(
          top: header ? 10 : 3,
          bottom: 3,
          left: mine ? 60 : 0,
          right: mine ? 0 : 60,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: mine
              ? LinearGradient(
                  colors: [t.primary, t.primary.withOpacity(.85)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : LinearGradient(
                  colors: [
                    t.secondaryBackground,
                    t.secondaryBackground.withOpacity(.95),
                  ],
                ),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(mine ? 20 : 6),
            bottomRight: Radius.circular(mine ? 6 : 20),
          ),
          boxShadow: [
            BoxShadow(
              color: mine
                  ? t.primary.withOpacity(.25)
                  : Colors.black.withOpacity(.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (header)
              Row(
                children: [
                  _avatar(m.senderId),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      style: t.bodySmall.override(
                        color: mine
                            ? Colors.white.withOpacity(.95)
                            : t.primaryText,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    _formatTime(m.timestamp),
                    style: t.bodySmall.override(
                      color:
                          mine ? Colors.white.withOpacity(.7) : t.secondaryText,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            if (header) const SizedBox(height: 8),
            // Image display
            if (m.imageUrl != null && m.imageUrl!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 240,
                      maxHeight: 300,
                    ),
                    child: CachedNetworkImage(
                      imageUrl: m.imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (c, _) => Container(
                        height: 160,
                        width: 220,
                        decoration: BoxDecoration(
                          color: mine
                              ? Colors.white.withOpacity(.2)
                              : t.primaryBackground,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              mine ? Colors.white : t.primary,
                            ),
                          ),
                        ),
                      ),
                      errorWidget: (c, _, __) => Container(
                        height: 160,
                        width: 220,
                        decoration: BoxDecoration(
                          color: mine
                              ? Colors.white.withOpacity(.2)
                              : t.primaryBackground,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.broken_image,
                          color: mine ? Colors.white : t.secondaryText,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // Video display
            if (m.videoUrl != null && m.videoUrl!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  width: 240,
                  height: 160,
                  decoration: BoxDecoration(
                    color: mine
                        ? Colors.white.withOpacity(.2)
                        : t.primaryBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.play_circle_fill,
                        size: 32,
                        color: mine ? Colors.white : t.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Video',
                        style: t.bodyMedium.override(
                          color: mine ? Colors.white : t.primaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (m.text != null)
              Text(
                m.text!,
                style: t.bodyMedium.override(
                  color: mine ? Colors.white : t.primaryText,
                  fontSize: 15,
                  lineHeight: 1.35,
                ),
              ),
            if (m.reactions.isNotEmpty) const SizedBox(height: 10),
            if (m.reactions.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final entry in m.reactions.entries)
                    _reactionChip(t, m, entry.key, entry.value),
                  // Add reaction chip removed
                ],
              ),
            // Add reaction chip removed for empty reactions
          ],
        ),
      ),
    );
  }

  Widget _reactionChip(
    FlutterFlowTheme t,
    _LiveMsg m,
    String emoji,
    List<String> userIds,
  ) {
    final reacted = userIds.contains(currentUserUid);

    // ✨ UX: Animated reaction chip
    return AnimatedButton(
      onPressed: () async {
        await HapticUtils.light();
        _toggleReaction(m, emoji);
      },
      scaleAmount: 0.92,
      backgroundColor: reacted
          ? t.primary.withOpacity(.15)
          : t.secondaryBackground.withOpacity(.8),
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            emoji,
            style: const TextStyle(fontSize: 16),
          ),
          if (userIds.length > 1) ...[
            const SizedBox(width: 4),
            Text(
              '${userIds.length}',
              style: t.bodySmall.override(
                color: reacted ? t.primary : t.secondaryText,
                fontWeight: reacted ? FontWeight.w700 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _addReactionChip(FlutterFlowTheme t, _LiveMsg m) {
    return AnimatedButton(
      onPressed: () async {
        await HapticUtils.light();
        _startReactionInput(m);
      },
      scaleAmount: 0.92,
      backgroundColor: t.secondaryBackground.withOpacity(.6),
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Icon(
        Icons.add_reaction_outlined,
        size: 18,
        color: t.secondaryText.withOpacity(.7),
      ),
    );
  }

  void _startReactionInput(_LiveMsg m) {
    setState(() => _reactingToMessageId = m.id);
    _reactionInputCtl.clear();
    Future.delayed(50.ms, () {
      if (mounted) FocusScope.of(context).requestFocus(_reactionFocus);
    });
  }

  void _cancelReactionInput() {
    if (_reactingToMessageId == null) return;
    setState(() => _reactingToMessageId = null);
    _reactionInputCtl.clear();
    _reactionFocus.unfocus();
  }

  void _onReactionInputChanged(String v) {
    if (_reactingToMessageId == null) return;
    if (v.isEmpty) return;

    final last = v.characters.last;
    final msg = _messages.firstWhere(
      (e) => e.id == _reactingToMessageId,
      orElse: () => _messages.last,
    );
    _toggleReaction(msg, last);
    _cancelReactionInput();
  }

  Widget _emojiReactionOverlay(FlutterFlowTheme t) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: _cancelReactionInput,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 90,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: t.secondaryBackground,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(.2),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      )
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.touch_app_rounded, size: 20),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Choose an emoji',
                          style: t.bodyMedium.override(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_reactionInputCtl.text.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          _reactionInputCtl.text.characters.last,
                          style: const TextStyle(fontSize: 28),
                        ),
                      ],
                      SizedBox(
                        width: 0,
                        height: 0,
                        child: TextField(
                          controller: _reactionInputCtl,
                          focusNode: _reactionFocus,
                          autofocus: true,
                          onChanged: _onReactionInputChanged,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      HapticIconButton(
                        icon: Icons.close_rounded,
                        onPressed: _cancelReactionInput,
                        color: t.secondaryText,
                        size: 20,
                        feedbackType: HapticsType.light,
                      ),
                    ],
                  ),
                ).animate().scale(
                      duration: 300.ms,
                      curve: Curves.easeOutBack,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleReaction(_LiveMsg m, String emoji) {
    final idx = _messages.indexWhere((mm) => mm.id == m.id);
    if (idx == -1) return;

    final current = _messages[idx];
    final map = Map<String, List<String>>.from(current.reactions);
    final list = List<String>.from(map[emoji] ?? []);

    if (list.contains(currentUserUid)) {
      list.remove(currentUserUid);
    } else {
      list.add(currentUserUid);
    }

    if (list.isEmpty) {
      map.remove(emoji);
    } else {
      map[emoji] = list;
    }

    setState(() => _messages[idx] = current.copyWith(reactions: map));

    SocketService.instance.addReaction(
      conversationId: _chatId,
      messageId: m.id,
      emoji: emoji,
    );
  }

  Widget _typingBubble(FlutterFlowTheme t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: t.secondaryBackground,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _typingDot(t, 0),
                const SizedBox(width: 4),
                _typingDot(t, 1),
                const SizedBox(width: 4),
                _typingDot(t, 2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _typingDot(FlutterFlowTheme t, int index) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: t.secondaryText.withOpacity(.6),
        shape: BoxShape.circle,
      ),
    )
        .animate(onPlay: (controller) => controller.repeat(reverse: true))
        .fadeIn(
          duration: 600.ms,
          delay: (index * 200).ms,
        )
        .scale(
          duration: 600.ms,
          delay: (index * 200).ms,
          begin: const Offset(0.7, 0.7),
          end: const Offset(1.0, 1.0),
        );
  }

  Widget _quickReactions(FlutterFlowTheme t) {
    final reactions = ['❤️', '👍', '😂', '🔥', '🎉', '👏'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: reactions.map((emoji) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: AnimatedButton(
                onPressed: () => _quickReaction(emoji),
                scaleAmount: 0.85,
                backgroundColor: t.secondaryBackground.withOpacity(.8),
                borderRadius: BorderRadius.circular(20),
                padding: const EdgeInsets.all(10),
                elevation: 2,
                child: Text(
                  emoji,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _composer(FlutterFlowTheme t) {
    final canSend = _input.text.trim().isNotEmpty && !_sending;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: t.secondaryBackground,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.08),
              blurRadius: 16,
              offset: const Offset(0, -4),
            )
          ],
        ),
        child: Row(
          children: [
            // ✨ UX: Attachment button
            HapticIconButton(
              icon: Icons.add_circle_outline_rounded,
              onPressed: _chooseAttachment,
              color: t.primary,
              size: 28,
              feedbackType: HapticsType.light,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: t.primaryBackground,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: t.primary.withOpacity(.15),
                    width: 1.5,
                  ),
                ),
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  onChanged: (v) {
                    _typingDebounce?.cancel();
                    _typingDebounce = Timer(800.ms, () => _setTyping(false));
                    _setTyping(true);
                    setState(() {});
                  },
                  style: t.bodyMedium,
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: t.bodyMedium.override(
                      color: t.secondaryText.withOpacity(.6),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // ✨ UX: Animated send button
            AnimatedButton(
              onPressed: canSend ? _send : null,
              scaleAmount: 0.88,
              backgroundColor:
                  canSend ? t.primary : t.secondaryText.withOpacity(.3),
              borderRadius: BorderRadius.circular(24),
              padding: const EdgeInsets.all(12),
              elevation: canSend ? 4 : 0,
              child: Icon(
                _sending ? Icons.hourglass_empty_rounded : Icons.send_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(String uid) {
    final m = _memberIndex[uid];
    final url = (m?['photoUrl'] ?? m?['avatar'])?.toString();

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            FlutterFlowTheme.of(context).primary,
            FlutterFlowTheme.of(context).tertiary,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: FlutterFlowTheme.of(context).primary.withOpacity(.3),
            blurRadius: 8,
            spreadRadius: 1,
          )
        ],
      ),
      padding: const EdgeInsets.all(2),
      child: CircleAvatar(
        radius: 14,
        backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
        backgroundImage: url != null && url.isNotEmpty
            ? CachedNetworkImageProvider(url)
            : null,
        child: url == null || url.isEmpty
            ? Icon(
                Icons.person,
                color: FlutterFlowTheme.of(context).secondaryText,
                size: 16,
              )
            : null,
      ),
    );
  }

  Widget _floatingReactionsLayer() {
    return Positioned.fill(
      child: IgnorePointer(
        child: StreamBuilder<_FloatingReaction>(
          stream: _floatingCtl.stream,
          builder: (context, snapshot) {
            return Stack(
              children: [],
            );
          },
        ),
      ),
    );
  }

  Widget _confettiWidget(FlutterFlowTheme t) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConfettiWidget(
        confettiController: _confetti,
        blastDirectionality: BlastDirectionality.explosive,
        emissionFrequency: 0.05,
        numberOfParticles: 24,
        maxBlastForce: 30,
        minBlastForce: 8,
        colors: [t.primary, t.tertiary, t.secondary, t.info],
      ),
    );
  }

  String? _resolveName(String uid) {
    final m = _memberIndex[uid];
    return (m?['displayName'] ?? m?['name'] ?? m?['username'])?.toString();
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  Map<String, List<String>> _parseReactions(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      try {
        return raw.map((k, v) =>
            MapEntry(k, (v as List).map((e) => e.toString()).toList()));
      } catch (_) {}
    }
    if (raw is List) {
      final Map<String, List<String>> out = {};
      for (final item in raw) {
        if (item is Map) {
          final emoji = item['emoji']?.toString();
          final userId = item['userId']?.toString();
          if (emoji != null && userId != null) {
            out.putIfAbsent(emoji, () => []).add(userId);
          }
        }
      }
      return out;
    }
    return {};
  }
}

// ✨ Add Members Sheet - Enhanced for pulse invitations
class _AddMembersSheet extends StatefulWidget {
  final String chatId;
  final String? pulseName;

  const _AddMembersSheet({required this.chatId, this.pulseName});

  @override
  State<_AddMembersSheet> createState() => _AddMembersSheetState();
}

class _AddMembersSheetState extends State<_AddMembersSheet> {
  bool _loading = true;
  bool _sending = false;
  List<Map<String, dynamic>> _followers = [];
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadFollowers();
  }

  Future<void> _loadFollowers() async {
    setState(() => _loading = true);
    try {
      final uid = currentUserUid;
      if (uid.isNotEmpty) {
        final followers = await ApiService.instance.getUserFollowers(uid);
        if (mounted) {
          setState(() {
            _followers = followers ?? [];
            _loading = false;
          });
        }
      }
    } catch (e) {
      print('Error loading followers: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendInvitations() async {
    if (_selectedIds.isEmpty || widget.pulseName == null) return;

    setState(() => _sending = true);
    await HapticUtils.medium();

    try {
      final result = await ApiService.instance.inviteToPulse(
        pulseId: widget.pulseName!,
        userIds: _selectedIds.toList(),
      );

      if (mounted) {
        if (result != null && result['success'] == true) {
          await HapticUtils.success();
          Navigator.pop(context);
          CustomSnackbar.showSuccess(
            context,
            message: 'Invitations sent!',
          );
        } else {
          await HapticUtils.error();
          CustomSnackbar.showError(
            context,
            message: 'Failed to send invitations',
          );
        }
      }
    } catch (e) {
      print('Error sending invitations: $e');
      if (mounted) {
        await HapticUtils.error();
        CustomSnackbar.showError(
          context,
          message: 'Error sending invitations',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.secondaryText.withOpacity(.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Icon(Icons.person_add_rounded, color: theme.primary, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Invite to Pulse',
                    style:
                        theme.titleLarge.override(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: theme.secondaryText),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          if (_selectedIds.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.primary.withOpacity(.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: theme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '${_selectedIds.length} selected',
                    style: theme.bodyMedium.override(
                      color: theme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),
          Divider(height: 1, color: theme.secondaryText.withOpacity(.1)),

          // Followers list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _followers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: 64,
                              color: theme.secondaryText.withOpacity(.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No followers to invite',
                              style: theme.bodyLarge.override(
                                color: theme.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _followers.length,
                        itemBuilder: (context, index) {
                          final user = _followers[index];
                          final userId = user['id']?.toString() ?? '';
                          final isSelected = _selectedIds.contains(userId);

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 4,
                            ),
                            leading: CircleAvatar(
                              radius: 24,
                              backgroundImage: user['profileImageUrl'] != null
                                  ? CachedNetworkImageProvider(
                                      user['profileImageUrl'])
                                  : null,
                              child: user['profileImageUrl'] == null
                                  ? Icon(Icons.person,
                                      color: theme.secondaryText)
                                  : null,
                            ),
                            title: Text(
                              user['displayName'] ?? 'User',
                              style: theme.bodyLarge.override(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: user['bio'] != null
                                ? Text(
                                    user['bio'],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.bodySmall.override(
                                      color: theme.secondaryText,
                                    ),
                                  )
                                : null,
                            trailing: Checkbox(
                              value: isSelected,
                              onChanged: (value) async {
                                await HapticUtils.light();
                                setState(() {
                                  if (value == true) {
                                    _selectedIds.add(userId);
                                  } else {
                                    _selectedIds.remove(userId);
                                  }
                                });
                              },
                              activeColor: theme.primary,
                            ),
                            onTap: () async {
                              await HapticUtils.light();
                              setState(() {
                                if (isSelected) {
                                  _selectedIds.remove(userId);
                                } else {
                                  _selectedIds.add(userId);
                                }
                              });
                            },
                          );
                        },
                      ),
          ),

          // Send button
          if (_selectedIds.isNotEmpty)
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.secondaryBackground,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(.08),
                      blurRadius: 16,
                      offset: const Offset(0, -4),
                    )
                  ],
                ),
                child: ElevatedButton(
                  onPressed: _sending ? null : _sendInvitations,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size(double.infinity, 54),
                  ),
                  child: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.send_rounded, color: Colors.white),
                            const SizedBox(width: 8),
                            Text(
                              'Send Invitations',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Message model (keep existing)
class _LiveMsg {
  final String id;
  final String senderId;
  final String? text;
  final String? imageUrl;
  final String? videoUrl;
  final DateTime timestamp;
  final Map<String, List<String>> reactions;
  final String? conversationId;

  _LiveMsg({
    required this.id,
    required this.senderId,
    this.text,
    this.imageUrl,
    this.videoUrl,
    required this.timestamp,
    required this.reactions,
    this.conversationId,
  });

  factory _LiveMsg.fromJson(Map<String, dynamic> json) {
    final reactions = <String, List<String>>{};
    final raw = json['reactions'];
    if (raw is Map) {
      raw.forEach((key, value) {
        if (value is List) {
          reactions[key.toString()] = value.map((e) => e.toString()).toList();
        }
      });
    }
    return _LiveMsg(
      id: json['id']?.toString() ?? '',
      senderId: json['senderId']?.toString() ?? '',
      text: json['text']?.toString(),
      imageUrl: json['imageUrl']?.toString(),
      videoUrl: json['videoUrl']?.toString(),
      timestamp: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      reactions: reactions,
      conversationId: json['conversationId']?.toString(),
    );
  }

  _LiveMsg copyWith({
    String? id,
    String? senderId,
    String? text,
    String? imageUrl,
    String? videoUrl,
    DateTime? timestamp,
    Map<String, List<String>>? reactions,
  }) {
    return _LiveMsg(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      imageUrl: imageUrl ?? this.imageUrl,
      videoUrl: videoUrl ?? this.videoUrl,
      timestamp: timestamp ?? this.timestamp,
      reactions: reactions ?? this.reactions,
    );
  }
}

// Floating reaction model (keep existing)
class _FloatingReaction {
  final String id;
  final String emoji;
  final double startX;
  final double drift;
  final int durationMs;
  final double scale;

  _FloatingReaction({
    required this.id,
    required this.emoji,
    required this.startX,
    required this.drift,
    required this.durationMs,
    required this.scale,
  });
}
