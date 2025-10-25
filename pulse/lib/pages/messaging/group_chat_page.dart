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
import '../../flutter_flow/flutter_flow_theme.dart';
import '../../components/skeleton_loader.dart';
import '../../components/error_state_widget.dart';
import '../../components/micro_interactions.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/snackbar_utils.dart';
import 'package:permission_handler/permission_handler.dart';
import '../calling/group_call_screen.dart';

/// 💬 Group Chat Page - For normal (non-pulse) group conversations
///
/// Features:
/// - Real-time messaging with Socket.IO
/// - Image and video sharing
/// - Message reactions
/// - Typing indicators
/// - Group voice and video calls
/// - Member management
/// - Modern, polished UI with haptic feedback
class GroupChatPage extends ConsumerStatefulWidget {
  const GroupChatPage({
    super.key,
    required this.chatId,
    required this.groupName,
    this.groupDescription,
    this.groupAvatarUrl,
    this.members,
  });

  final String chatId;
  final String groupName;
  final String? groupDescription;
  final String? groupAvatarUrl;
  final List<Map<String, dynamic>>? members;

  @override
  ConsumerState<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends ConsumerState<GroupChatPage>
    with TickerProviderStateMixin {
  // Controllers
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _reactionInputCtl = TextEditingController();
  final _reactionFocus = FocusNode();
  late ConfettiController _confetti;

  // State
  final List<_GroupMsg> _messages = [];
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

  // Socket subscriptions
  StreamSubscription<Map<String, dynamic>>? _msgSub;
  StreamSubscription<Map<String, dynamic>>? _typingSub;
  StreamSubscription<Map<String, dynamic>>? _ackSub;
  late String _chatId;

  // Member index for quick lookups
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
      // Connect socket
      await SocketService.instance.connect();
      SocketService.instance.joinConversation(_chatId);

      // Load messages
      await _bootstrap();

      // Setup listeners
      _setupSocketListeners();

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
    _msgSub = SocketService.instance.messages.listen(_onSocketMessage);
    _typingSub = SocketService.instance.typing.listen(_onTyping);
    _ackSub = SocketService.instance.acks.listen((ack) {
      try {
        final cid = (ack['conversationId'] ?? ack['id'])?.toString();
        if (cid != null && cid.isNotEmpty && cid != _chatId) {
          setState(() => _chatId = cid);
          SocketService.instance.joinConversation(_chatId);
        }
      } catch (_) {}
    });
  }

  Future<void> _bootstrap() async {
    final res = await ApiService.instance.listMessages(_chatId);
    final msgs = (res?['messages'] as List<dynamic>? ?? [])
        .map((m) => _GroupMsg.fromJson(m as Map<String, dynamic>))
        .toList();
    setState(() => _messages.addAll(msgs));
    _jumpBottom();
  }

  void _onSocketMessage(dynamic raw) {
    try {
      final map = Map<String, dynamic>.from(raw as Map);
      if (map['conversationId'] != _chatId) return;

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

      // New message
      final msg = _GroupMsg.fromJson(map);
      setState(() => _messages.add(msg));
      _messageCount++;
      _maybeCelebrate();
      _animateInReactionAuto(msg);
      _autoScroll();

      // ✨ UX: Haptic feedback for new messages
      HapticUtils.light();
    } catch (_) {}
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

  Map<String, List<String>> _parseReactions(dynamic raw) {
    final result = <String, List<String>>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        if (value is List) {
          result[key.toString()] = value.map((e) => e.toString()).toList();
        }
      });
    }
    return result;
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

    setState(() => _sending = true);

    // ✨ UX: Haptic feedback on send
    await HapticUtils.medium();

    try {
      SocketService.instance.sendMessage(
        conversationId: _chatId,
        text: txt,
      );
      _input.clear();
      _setTyping(false);
      _animateToBottom();

      // ✨ UX: Success feedback
      await HapticUtils.light();
    } catch (e) {
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
    SocketService.instance.setTyping(_chatId, v);
  }

  void _maybeCelebrate() {
    if (_messageCount == 100 ||
        _messageCount == 250 ||
        _messageCount % 500 == 0) {
      _confetti.play();
      HapticUtils.success();
    }
  }

  void _animateInReactionAuto(_GroupMsg msg) {
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
    SocketService.instance.sendMessage(conversationId: _chatId, text: emoji);
  }

  void _openGroupInfo() async {
    // ✨ UX: Haptic feedback
    await HapticUtils.selection();

    // Show group info bottom sheet
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _GroupInfoSheet(
        chatId: _chatId,
        groupName: widget.groupName,
        groupDescription: widget.groupDescription,
        groupAvatarUrl: widget.groupAvatarUrl,
        members: widget.members ?? [],
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

      SocketService.instance.sendMessage(
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

      SocketService.instance.sendMessage(
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

  Future<void> _startVoiceCall() async {
    final res = await Permission.microphone.request();
    if (!res.isGranted) {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return GestureDetector(
      onTap: () => _focus.unfocus(),
      child: Scaffold(
        backgroundColor: theme.primaryBackground,
        appBar: _buildAppBar(theme),
        body: _isLoading
            ? _buildLoadingState(theme)
            : _hasError
                ? _buildErrorState(theme)
                : _buildChatBody(theme),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(FlutterFlowTheme theme) {
    final memberCount = widget.members?.length ?? 0;

    return AppBar(
      backgroundColor: theme.secondaryBackground,
      elevation: 2,
      shadowColor: Colors.black.withOpacity(.1),
      leading: HapticIconButton(
        icon: Icons.arrow_back_rounded,
        onPressed: () => Navigator.of(context).pop(),
        color: theme.primaryText,
        feedbackType: HapticsType.light,
      ),
      title: GestureDetector(
        onTap: _openGroupInfo,
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            // Group avatar
            CircleAvatar(
              backgroundColor: theme.accent2.withOpacity(0.1),
              backgroundImage: widget.groupAvatarUrl != null &&
                      widget.groupAvatarUrl!.isNotEmpty
                  ? CachedNetworkImageProvider(widget.groupAvatarUrl!)
                  : null,
              child: widget.groupAvatarUrl == null ||
                      widget.groupAvatarUrl!.isEmpty
                  ? Icon(Icons.people, color: theme.accent2, size: 24)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.groupName,
                    style: theme.titleMedium.override(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '$memberCount ${memberCount == 1 ? 'member' : 'members'}',
                    style: theme.bodySmall.override(
                      color: theme.secondaryText,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        // Voice call button
        HapticIconButton(
          icon: Icons.call_rounded,
          onPressed: _startVoiceCall,
          color: theme.primary,
          feedbackType: HapticsType.medium,
        ),
        // Video call button
        HapticIconButton(
          icon: Icons.videocam_rounded,
          onPressed: _startVideoCall,
          color: theme.primary,
          feedbackType: HapticsType.medium,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildLoadingState(FlutterFlowTheme theme) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 8,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment:
              i % 2 == 0 ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (i % 2 == 1)
              const SkeletonLoader(
                  width: 32,
                  height: 32,
                  borderRadius: BorderRadius.all(Radius.circular(16))),
            if (i % 2 == 1) const SizedBox(width: 8),
            SkeletonLoader(
              width: MediaQuery.of(context).size.width * 0.6,
              height: 60,
              borderRadius: BorderRadius.circular(16),
            ),
            if (i % 2 == 0) const SizedBox(width: 8),
            if (i % 2 == 0)
              const SkeletonLoader(
                  width: 32,
                  height: 32,
                  borderRadius: BorderRadius.all(Radius.circular(16))),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(FlutterFlowTheme theme) {
    return ErrorStateWidget(
      title: 'Failed to Load Chat',
      message: 'Unable to connect to the chat. Please try again.',
      icon: Icons.chat_bubble_outline_rounded,
      retryButtonText: 'Retry',
      onRetry: _initializeChat,
    );
  }

  Widget _buildChatBody(FlutterFlowTheme theme) {
    return Stack(
      children: [
        // Background gradient
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                theme.primaryBackground,
                theme.primaryBackground.withOpacity(.95),
              ],
            ),
          ),
        ),

        // Main content
        Column(
          children: [
            // Quick reactions bar
            _quickReactions(theme),

            // Messages list
            Expanded(child: _chatFeed(theme)),

            // Typing indicator
            if (_someoneTyping) _typingBubble(theme),

            // Message composer
            _composer(theme),
          ],
        ),

        // Floating reactions
        StreamBuilder<_FloatingReaction>(
          stream: _floatingCtl.stream,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            final r = snapshot.data!;
            return _FloatingReactionWidget(reaction: r);
          },
        ),

        // Confetti
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            emissionFrequency: 0.05,
            numberOfParticles: 30,
            gravity: 0.3,
          ),
        ),

        // Reaction input overlay
        if (_reactingToMessageId != null) _emojiReactionOverlay(theme),
      ],
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

  Widget _messageBubble(_GroupMsg m, bool header, FlutterFlowTheme t) {
    final mine = m.senderId == currentUserUid;
    final name = _resolveName(m.senderId) ?? 'User';

    return GestureDetector(
      onDoubleTap: () => _quickReaction('❤️'),
      onLongPress: () {
        HapticUtils.medium();
        _startReactionInput(m);
      },
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
                  _addReactionChip(t, m),
                ],
              ),
            if (m.reactions.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _addReactionChip(t, m),
              ),
          ],
        ),
      ),
    );
  }

  Widget _reactionChip(
    FlutterFlowTheme t,
    _GroupMsg m,
    String emoji,
    List<String> userIds,
  ) {
    final reacted = userIds.contains(currentUserUid);

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
      elevation: 2,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          if (userIds.length > 1) ...[
            const SizedBox(width: 4),
            Text(
              userIds.length.toString(),
              style: t.bodySmall.override(
                color: reacted ? t.primary : t.primaryText,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _addReactionChip(FlutterFlowTheme t, _GroupMsg m) {
    return AnimatedButton(
      onPressed: () async {
        await HapticUtils.light();
        _startReactionInput(m);
      },
      scaleAmount: 0.92,
      backgroundColor: t.secondaryBackground.withOpacity(.6),
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      elevation: 1,
      child: Icon(
        Icons.add_reaction_outlined,
        size: 16,
        color: t.secondaryText,
      ),
    );
  }

  void _startReactionInput(_GroupMsg m) {
    setState(() {
      _reactingToMessageId = m.id;
      _reactionInputCtl.clear();
    });
    Future.delayed(100.ms, () {
      if (mounted) _reactionFocus.requestFocus();
    });
  }

  void _cancelReactionInput() {
    setState(() {
      _reactingToMessageId = null;
      _reactionInputCtl.clear();
    });
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
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).viewInsets.bottom + 90,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
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
                      const SizedBox(width: 10),
                      Text(
                        'Choose an emoji',
                        style: t.bodyMedium.override(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_reactionInputCtl.text.isNotEmpty) ...[
                        const SizedBox(width: 12),
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
                      const SizedBox(width: 12),
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

  void _toggleReaction(_GroupMsg m, String emoji) {
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: reactions.map((emoji) {
          return AnimatedButton(
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
          );
        }).toList(),
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
      child: CircleAvatar(
        radius: 16,
        backgroundColor: Colors.transparent,
        backgroundImage: url != null && url.isNotEmpty
            ? CachedNetworkImageProvider(url)
            : null,
        child: url == null || url.isEmpty
            ? Icon(Icons.person, size: 18, color: Colors.white)
            : null,
      ),
    );
  }

  String? _resolveName(String uid) {
    final m = _memberIndex[uid];
    if (m == null) return null;
    final first = (m['firstName'] ?? m['first_name'])?.toString();
    final last = (m['lastName'] ?? m['last_name'])?.toString();
    final combined =
        [first, last].where((e) => e != null && e.isNotEmpty).join(' ');
    return (m['displayName'] ??
            m['fullName'] ??
            m['username'] ??
            m['name'] ??
            combined)
        .toString();
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inDays > 0) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}

// Message model for group chats
class _GroupMsg {
  final String id;
  final String senderId;
  final String? text;
  final String? imageUrl;
  final String? videoUrl;
  final DateTime timestamp;
  final Map<String, List<String>> reactions;

  _GroupMsg({
    required this.id,
    required this.senderId,
    this.text,
    this.imageUrl,
    this.videoUrl,
    required this.timestamp,
    required this.reactions,
  });

  factory _GroupMsg.fromJson(Map<String, dynamic> json) {
    final reactions = <String, List<String>>{};
    final raw = json['reactions'];
    if (raw is Map) {
      raw.forEach((key, value) {
        if (value is List) {
          reactions[key.toString()] = value.map((e) => e.toString()).toList();
        }
      });
    }
    return _GroupMsg(
      id: json['id']?.toString() ?? '',
      senderId: json['senderId']?.toString() ?? '',
      text: json['text']?.toString(),
      imageUrl: json['imageUrl']?.toString(),
      videoUrl: json['videoUrl']?.toString(),
      timestamp: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      reactions: reactions,
    );
  }

  _GroupMsg copyWith({
    String? id,
    String? senderId,
    String? text,
    String? imageUrl,
    String? videoUrl,
    DateTime? timestamp,
    Map<String, List<String>>? reactions,
  }) {
    return _GroupMsg(
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

// Floating reaction model
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

// Floating reaction widget
class _FloatingReactionWidget extends StatelessWidget {
  final _FloatingReaction reaction;

  const _FloatingReactionWidget({required this.reaction});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: MediaQuery.of(context).size.width * reaction.startX,
      bottom: 80,
      child: IgnorePointer(
        child: Text(
          reaction.emoji,
          style: TextStyle(fontSize: 32 * reaction.scale),
        )
            .animate()
            .moveY(
              begin: 0,
              end: -MediaQuery.of(context).size.height * 0.7,
              duration: Duration(milliseconds: reaction.durationMs),
              curve: Curves.easeOut,
            )
            .moveX(
              begin: 0,
              end: reaction.drift * 100,
              duration: Duration(milliseconds: reaction.durationMs),
            )
            .fadeOut(
              begin: 0.8,
              duration: Duration(milliseconds: reaction.durationMs ~/ 3),
            ),
      ),
    );
  }
}

// Group info sheet
class _GroupInfoSheet extends StatelessWidget {
  final String chatId;
  final String groupName;
  final String? groupDescription;
  final String? groupAvatarUrl;
  final List<Map<String, dynamic>> members;

  const _GroupInfoSheet({
    required this.chatId,
    required this.groupName,
    this.groupDescription,
    this.groupAvatarUrl,
    required this.members,
  });

  @override
  Widget build(BuildContext context) {
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

            // Group avatar
            CircleAvatar(
              radius: 40,
              backgroundColor: theme.accent2.withOpacity(0.1),
              backgroundImage:
                  groupAvatarUrl != null && groupAvatarUrl!.isNotEmpty
                      ? CachedNetworkImageProvider(groupAvatarUrl!)
                      : null,
              child: groupAvatarUrl == null || groupAvatarUrl!.isEmpty
                  ? Icon(Icons.people, color: theme.accent2, size: 40)
                  : null,
            ),
            const SizedBox(height: 16),

            // Group name
            Text(
              groupName,
              style: theme.headlineSmall.override(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            // Group description
            if (groupDescription != null && groupDescription!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  groupDescription!,
                  style: theme.bodyMedium.override(
                    color: theme.secondaryText,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(height: 8),

            // Member count
            Text(
              '${members.length} ${members.length == 1 ? 'member' : 'members'}',
              style: theme.bodySmall.override(
                color: theme.secondaryText,
              ),
            ),
            const SizedBox(height: 24),

            // Options
            ListTile(
              leading: Icon(Icons.notifications_outlined, color: theme.primary),
              title: const Text('Notifications'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement notifications settings
              },
            ),
            ListTile(
              leading: Icon(Icons.exit_to_app, color: theme.error),
              title: Text(
                'Leave Group',
                style: TextStyle(color: theme.error),
              ),
              onTap: () async {
                Navigator.pop(context);
                // Show confirmation dialog
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Leave Group'),
                    content: Text(
                      'Are you sure you want to leave "$groupName"?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: TextButton.styleFrom(
                          foregroundColor: theme.error,
                        ),
                        child: const Text('Leave'),
                      ),
                    ],
                  ),
                );

                if (confirmed == true) {
                  // Leave the group
                  await ApiService.instance.leaveGroupConversation(chatId);
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                }
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
