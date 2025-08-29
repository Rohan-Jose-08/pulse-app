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
import '../../backend/socket_service.dart';

class Message {
  Message({
    required this.id,
    required this.senderId,
    required this.timestamp,
    this.text,
    this.imageUrl,
    this.videoUrl,
    this.reactions,
    this.senderName,
    this.senderPhotoUrl,
  });

  final String id;
  final String senderId;
  final DateTime timestamp;
  final String? text;
  final String? imageUrl;
  final String? videoUrl;
  final Map<String, List<String>>? reactions; // emoji -> list of user IDs
  final String? senderName;
  final String? senderPhotoUrl;

  bool get isImage => (imageUrl != null && imageUrl!.isNotEmpty);

  factory Message.fromSocket(Map<String, dynamic> data) => Message(
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
                (key, value) => MapEntry(key, List<String>.from(value)),
              ))
            : null,
        senderName: data['senderName'] as String?,
        senderPhotoUrl: data['senderPhotoUrl'] as String?,
      );
}

final _messagesStreamProvider = StreamProvider.autoDispose
    .family<List<Message>, String>((ref, conversationId) {
  final controller = StreamController<List<Message>>();
  final Map<String, Message> byId = {};

  void publish() {
    final list = byId.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    controller.add(list);
  }

  final sub = SocketService.instance.messages.listen((data) {
    if (data['conversationId'] == conversationId) {
      final msg = Message.fromSocket(Map<String, dynamic>.from(data));
      byId[msg.id] = msg;
      publish();
    }
  });

  (() async {
    final result = await ApiService.instance.listMessages(conversationId);
    final msgs = ((result?['messages'] as List<dynamic>? ?? [])
        .map((m) => Message.fromSocket(Map<String, dynamic>.from(m)))
        .toList());
    for (final m in msgs) {
      byId[m.id] = m;
    }
    publish();
  })();

  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });

  return controller.stream;
});

final _typingStreamProvider = StreamProvider.autoDispose
    .family<bool, ({String chatId, String userId})>((ref, params) {
  return SocketService.instance.typing.map((data) {
    try {
      final map = Map<String, dynamic>.from(data);
      final cid = map['conversationId']?.toString();
      final uid = map['userId']?.toString();
      final isTyping = map['isTyping'] == true;
      if (cid == params.chatId && uid == params.userId) {
        return isTyping;
      }
    } catch (_) {}
    return false;
  });
});

class MessagingPage extends ConsumerStatefulWidget {
  const MessagingPage({
    super.key,
    required this.chatId,
    required this.recipientUserId,
    required this.recipientName,
    required this.recipientPhotoUrl,
    this.isGroupChat = false,
    this.pulseId,
  });

  final String chatId;
  final String recipientUserId;
  final String recipientName;
  final String recipientPhotoUrl;
  final bool isGroupChat;
  final String? pulseId;

  @override
  ConsumerState<MessagingPage> createState() => _MessagingPageState();
}

class _MessagingPageState extends ConsumerState<MessagingPage> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _showEmoji = false;
  bool _isSending = false;
  Timer? _debounceTyping;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_handleTyping);
    SocketService.instance.connect();
    SocketService.instance.joinConversation(widget.chatId);
  }

  Future<void> _chooseAttachment() async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image_rounded),
                title: const Text('Send image'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _sendImage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam_rounded),
                title: const Text('Send video'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _sendVideo();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _debounceTyping?.cancel();
    _textController.removeListener(_handleTyping);
    _textController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    _setTyping(false);
    SocketService.instance.leaveConversation(widget.chatId);
    super.dispose();
  }

  void _handleTyping() {
    _debounceTyping?.cancel();
    _setTyping(true);
    _debounceTyping =
        Timer(const Duration(milliseconds: 900), () => _setTyping(false));
  }

  Future<void> _setTyping(bool isTyping) async {
    final myId = currentUserUid;
    if (myId.isEmpty) return;
    SocketService.instance.setTyping(widget.chatId, isTyping);
  }

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    try {
      SocketService.instance
          .sendMessage(conversationId: widget.chatId, text: text);
      _textController.clear();
      await _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message')), // keep generic
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _sendImage() async {
    try {
      final picker = ImagePicker();
      final file =
          await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (file == null) return;

      final bytes = await file.readAsBytes();
      final storageRef = FirebaseStorage.instance.ref().child(
          'chat_uploads/${widget.chatId}/${DateTime.now().millisecondsSinceEpoch}_${file.name}');
      final uploadTask = await storageRef.putData(
          bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await uploadTask.ref.getDownloadURL();

      SocketService.instance
          .sendMessage(conversationId: widget.chatId, imageUrl: url);
      await _scrollToBottom();
    } on PlatformException catch (_) {
      // user may have denied permission; no-op UX
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send image')),
        );
      }
    }
  }

  Future<void> _sendVideo() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickVideo(
          source: ImageSource.gallery, maxDuration: const Duration(minutes: 3));
      if (file == null) return;

      final bytes = await file.readAsBytes();
      final storageRef = FirebaseStorage.instance.ref().child(
          'chat_uploads/${widget.chatId}/${DateTime.now().millisecondsSinceEpoch}_${file.name}');
      final uploadTask = await storageRef.putData(
          bytes, SettableMetadata(contentType: 'video/mp4'));
      final url = await uploadTask.ref.getDownloadURL();

      SocketService.instance
          .sendMessage(conversationId: widget.chatId, videoUrl: url);
      await _scrollToBottom();
    } on PlatformException catch (_) {
      // permission denied
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send video')),
        );
      }
    }
  }

  Future<void> _scrollToBottom() async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent + 80,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _addReaction(String messageId, String emoji) async {
    try {
      // Send reaction through socket service
      SocketService.instance.addReaction(
        conversationId: widget.chatId,
        messageId: messageId,
        emoji: emoji,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to add reaction')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final messagesAsync = ref.watch(_messagesStreamProvider(widget.chatId));
    final isRecipientTyping = ref
        .watch(_typingStreamProvider(
            (chatId: widget.chatId, userId: widget.recipientUserId)))
        .maybeWhen(
          data: (v) => v,
          orElse: () => false,
        );

    ref.listen(_messagesStreamProvider(widget.chatId), (_, next) {
      next.whenData((_) => _scrollToBottom());
    });

    return GestureDetector(
      onTap: () {
        if (_showEmoji) setState(() => _showEmoji = false);
        _inputFocusNode.unfocus();
      },
      child: Scaffold(
        backgroundColor: theme.primaryBackground,
        appBar: AppBar(
          elevation: 0.5,
          backgroundColor: theme.secondaryBackground,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: theme.primaryText),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          titleSpacing: 0,
          title: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor:
                    widget.isGroupChat ? theme.primary.withOpacity(0.1) : null,
                backgroundImage:
                    !widget.isGroupChat && widget.recipientPhotoUrl.isNotEmpty
                        ? CachedNetworkImageProvider(widget.recipientPhotoUrl)
                        : null,
                child: widget.isGroupChat
                    ? Icon(Icons.group_rounded, color: theme.primary, size: 20)
                    : (widget.recipientPhotoUrl.isEmpty
                        ? Icon(Icons.person, color: theme.secondaryText)
                        : null),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.recipientName,
                      style: theme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      widget.isGroupChat
                          ? 'Pulse Group Chat'
                          : (isRecipientTyping ? 'typing…' : 'online'),
                      style: theme.bodySmall.override(
                          color: widget.isGroupChat
                              ? theme.primary
                              : theme.secondaryText),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: widget.isGroupChat && widget.pulseId != null
              ? [
                  IconButton(
                    icon: Icon(Icons.info_outline, color: theme.primaryText),
                    onPressed: () {
                      // Navigate to pulse details
                      Navigator.of(context).pushNamed(
                        '/pulse-detail',
                        arguments: {'pulseId': widget.pulseId},
                      );
                    },
                  ),
                ]
              : null,
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: messagesAsync.when(
                  data: (messages) {
                    if (messages.isEmpty) {
                      return Center(
                        child: Text('Say hi 👋',
                            style: theme.bodyMedium
                                .override(color: theme.secondaryText)),
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: () async {
                        // Placeholder: hook for pagination of older messages
                        await Future.delayed(const Duration(milliseconds: 400));
                      },
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          final isMine = message.senderId == currentUserUid;
                          return _MessageBubble(
                            message: message,
                            isMine: isMine,
                            theme: theme,
                            isGroupChat: widget.isGroupChat,
                            onReact: (emoji) => _addReaction(message.id, emoji),
                          )
                              .animate()
                              .fadeIn(
                                  duration: const Duration(milliseconds: 200))
                              .slideY(
                                  begin: 0.1,
                                  end: 0,
                                  duration: const Duration(milliseconds: 200));
                        },
                      ),
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) => Center(
                    child: Text('Unable to load messages',
                        style: theme.bodyMedium
                            .override(color: theme.secondaryText)),
                  ),
                ),
              ),
              _TypingIndicator(
                  isSomeoneTyping: isRecipientTyping, theme: theme),
              _InputBar(
                controller: _textController,
                focusNode: _inputFocusNode,
                showEmoji: _showEmoji,
                onToggleEmoji: () => setState(() => _showEmoji = !_showEmoji),
                onSend: _sendText,
                onAttach: _chooseAttachment,
                sending: _isSending,
                theme: theme,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.theme,
    required this.isGroupChat,
    required this.onReact,
  });

  final Message message;
  final bool isMine;
  final FlutterFlowTheme theme;
  final bool isGroupChat;
  final Function(String emoji) onReact;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble>
    with TickerProviderStateMixin {
  late AnimationController _reactionController;
  late Animation<double> _reactionAnimation;
  bool _showReactionPicker = false;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _reactionController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _reactionAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _reactionController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _reactionController.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _showReactionPicker = false;
  }

  void _showReactionOptions(BuildContext context) {
    if (_showReactionPicker) return;

    _showReactionPicker = true;
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => _ReactionPickerOverlay(
        position: position,
        messageSize: size,
        isMine: widget.isMine,
        onReact: (emoji) {
          widget.onReact(emoji);
          _removeOverlay();
          _reactionController.forward().then((_) {
            Future.delayed(const Duration(milliseconds: 1000), () {
              if (mounted) _reactionController.reverse();
            });
          });
        },
        onDismiss: _removeOverlay,
        theme: widget.theme,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    final bubbleColor =
        widget.isMine ? widget.theme.primary : const Color(0xFFE9ECEF);
    final textColor = widget.isMine ? Colors.white : Colors.black;
    final align =
        widget.isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(widget.isMine ? 16 : 4),
      bottomRight: Radius.circular(widget.isMine ? 4 : 16),
    );

    final timeString = _formatTime(widget.message.timestamp);

    return Padding(
      padding: EdgeInsets.only(
        top: 6,
        bottom: 6,
        left: widget.isMine ? 60 : 8,
        right: widget.isMine ? 8 : 60,
      ),
      child: Column(
        crossAxisAlignment: align,
        children: [
          // Show sender info for group chats (not for own messages)
          if (widget.isGroupChat &&
              !widget.isMine &&
              widget.message.senderName != null) ...[
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.message.senderPhotoUrl != null &&
                      widget.message.senderPhotoUrl!.isNotEmpty)
                    CircleAvatar(
                      radius: 10,
                      backgroundImage: CachedNetworkImageProvider(
                          widget.message.senderPhotoUrl!),
                    ),
                  if (widget.message.senderPhotoUrl == null ||
                      widget.message.senderPhotoUrl!.isEmpty)
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: widget.theme.primary.withOpacity(0.1),
                      child: Icon(Icons.person,
                          size: 12, color: widget.theme.primary),
                    ),
                  const SizedBox(width: 6),
                  Text(
                    widget.message.senderName!,
                    style: widget.theme.bodySmall.override(
                      color: widget.theme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
          GestureDetector(
            onLongPress: () => _showReactionOptions(context),
            child: Container(
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: radius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.72),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.message.isImage)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: widget.message.imageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (c, _) => Container(
                            height: 160,
                            width: 220,
                            color: Colors.black12,
                          ),
                          errorWidget: (c, _, __) => Container(
                            height: 160,
                            width: 220,
                            color: Colors.black12,
                            alignment: Alignment.center,
                            child: const Icon(Icons.broken_image),
                          ),
                        ),
                      ),
                    if ((widget.message.videoUrl ?? '').isNotEmpty)
                      Container(
                        width: 240,
                        height: 160,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.play_circle_fill, size: 32),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Video',
                                style: widget.theme.bodyMedium
                                    .override(color: textColor),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if ((widget.message.text ?? '').isNotEmpty) ...[
                      if (widget.message.isImage) const SizedBox(height: 8),
                      Text(
                        widget.message.text!,
                        style:
                            widget.theme.bodyMedium.override(color: textColor),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Reactions
          if (widget.message.reactions != null &&
              widget.message.reactions!.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              child: Wrap(
                children: widget.message.reactions!.entries.map((entry) {
                  final emoji = entry.key;
                  final userIds = entry.value;
                  return AnimatedBuilder(
                    animation: _reactionAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: 1.0 + (_reactionAnimation.value * 0.2),
                        child: Container(
                          margin: const EdgeInsets.only(right: 4, bottom: 2),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: widget.theme.secondaryBackground,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: widget.theme.primary.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(emoji, style: const TextStyle(fontSize: 14)),
                              if (userIds.length > 1) ...[
                                const SizedBox(width: 2),
                                Text(
                                  userIds.length.toString(),
                                  style: widget.theme.bodySmall.override(
                                    color: widget.theme.primary,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  );
                }).toList(),
              ),
            ),

          const SizedBox(height: 4),
          Text(
            timeString,
            style: widget.theme.bodySmall
                .override(color: widget.theme.secondaryText),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final isToday =
        time.year == now.year && time.month == now.month && time.day == now.day;
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final ampm = time.hour >= 12 ? 'PM' : 'AM';
    if (isToday) return '$hour:$minute $ampm';
    return '${time.month}/${time.day} $hour:$minute $ampm';
  }
}

class _ReactionPickerOverlay extends StatelessWidget {
  const _ReactionPickerOverlay({
    required this.position,
    required this.messageSize,
    required this.isMine,
    required this.onReact,
    required this.onDismiss,
    required this.theme,
  });

  final Offset position;
  final Size messageSize;
  final bool isMine;
  final Function(String emoji) onReact;
  final VoidCallback onDismiss;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) {
    final reactions = ['❤️', '😂', '😮', '😢', '😡', '👍', '👎', '🔥'];

    return GestureDetector(
      onTap: onDismiss,
      child: Container(
        color: Colors.transparent,
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        child: Stack(
          children: [
            Positioned(
              left:
                  isMine ? position.dx - 200 + messageSize.width : position.dx,
              top: position.dy - 60,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.secondaryBackground,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: reactions.map((emoji) {
                      return GestureDetector(
                        onTap: () => onReact(emoji),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              )
                  .animate()
                  .scale(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                  )
                  .fadeIn(
                    duration: const Duration(milliseconds: 150),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator({required this.isSomeoneTyping, required this.theme});
  final bool isSomeoneTyping;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) {
    if (!isSomeoneTyping) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      child: Row(
        children: [
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.secondaryBackground,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Dot(color: theme.secondaryText),
                const SizedBox(width: 4),
                _Dot(color: theme.secondaryText),
                const SizedBox(width: 4),
                _Dot(color: theme.secondaryText),
              ]
                  .animate(onPlay: (c) => c.repeat())
                  .fadeIn(duration: const Duration(milliseconds: 600))
                  .slideX(
                      begin: -0.05,
                      end: 0.05,
                      duration: const Duration(milliseconds: 600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration:
          BoxDecoration(color: color.withOpacity(0.6), shape: BoxShape.circle),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.showEmoji,
    required this.onToggleEmoji,
    required this.onSend,
    required this.onAttach,
    required this.sending,
    required this.theme,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool showEmoji;
  final VoidCallback onToggleEmoji;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final bool sending;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final canSend = value.text.trim().isNotEmpty && !sending;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    _IconBtn(
                      icon: Icons.emoji_emotions_outlined,
                      tooltip: 'Emoji',
                      onTap: onToggleEmoji,
                    ),
                    _IconBtn(
                      icon: Icons.attach_file,
                      tooltip: 'Attach image',
                      onTap: onAttach,
                    ),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: theme.secondaryBackground,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                              minHeight: 44, maxHeight: 140),
                          child: TextField(
                            controller: controller,
                            focusNode: focusNode,
                            maxLines: null,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Message',
                            ),
                          ),
                        ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: canSend
                          ? IconButton(
                              key: const ValueKey('send'),
                              onPressed: onSend,
                              icon: const Icon(Icons.send_rounded),
                              color: theme.primary,
                              tooltip: 'Send',
                            )
                          : IconButton(
                              key: const ValueKey('mic'),
                              onPressed: () {},
                              icon: const Icon(Icons.mic_none_rounded),
                              color: theme.secondaryText,
                              tooltip: 'Voice (coming soon)',
                            ),
                    ),
                  ],
                ),
              ),
              if (showEmoji)
                Container(
                  height: 220,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    color: theme.secondaryBackground,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(16)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 12,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text('Emoji picker',
                      style:
                          theme.bodySmall.override(color: theme.secondaryText)),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn(
      {required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon),
      tooltip: tooltip,
    );
  }
}
