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

// Enhanced Message Model with additional properties for better UX
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
    this.readBy,
    this.editedAt,
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
  final bool isSystemMessage;
  final List<String>? readBy; // list of user IDs who have read this message
  final DateTime? editedAt;

  bool get isImage => (imageUrl != null && imageUrl!.isNotEmpty);
  bool get isVideo => (videoUrl != null && videoUrl!.isNotEmpty);
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
                (key, value) => MapEntry(key, List<String>.from(value)),
              ))
            : null,
        senderName: data['senderName'] as String?,
        senderPhotoUrl: data['senderPhotoUrl'] as String?,
        isSystemMessage: data['isSystemMessage'] == true,
        readBy:
            data['readBy'] != null ? List<String>.from(data['readBy']) : null,
        editedAt: data['editedAt'] != null
            ? DateTime.tryParse(data['editedAt'].toString())
            : null,
      );
}

// Enhanced Messages Stream Provider
final _enhancedMessagesStreamProvider = StreamProvider.autoDispose
    .family<List<EnhancedMessage>, String>((ref, conversationId) {
  final controller = StreamController<List<EnhancedMessage>>();
  final Map<String, EnhancedMessage> byId = {};

  void publish() {
    final list = byId.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    controller.add(list);
  }

  final sub = SocketService.instance.messages.listen((data) {
    if (data['conversationId'] == conversationId) {
      final msg = EnhancedMessage.fromSocket(Map<String, dynamic>.from(data));
      byId[msg.id] = msg;
      publish();
    }
  });

  (() async {
    final result = await ApiService.instance.listMessages(conversationId);
    final msgs = ((result?['messages'] as List<dynamic>? ?? [])
        .map((m) => EnhancedMessage.fromSocket(Map<String, dynamic>.from(m)))
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

// Typing Indicator Provider
final _typingStreamProvider = StreamProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, chatId) {
  return SocketService.instance.typing.map((data) {
    try {
      final map = Map<String, dynamic>.from(data);
      final cid = map['conversationId']?.toString();
      final uid = map['userId']?.toString();
      final isTyping = map['isTyping'] == true;
      final userName = map['userName']?.toString() ?? 'Someone';

      if (cid == chatId && uid != currentUserUid) {
        return {
          'userId': uid,
          'isTyping': isTyping,
          'userName': userName,
        };
      }
    } catch (_) {}
    return <String, dynamic>{};
  });
});

class EnhancedMessagingPage extends ConsumerStatefulWidget {
  const EnhancedMessagingPage({
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
  ConsumerState<EnhancedMessagingPage> createState() =>
      _EnhancedMessagingPageState();
}

class _EnhancedMessagingPageState extends ConsumerState<EnhancedMessagingPage>
    with TickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  late AnimationController _newMessageAnimationController;
  late Animation<double> _newMessageAnimation;

  bool _showEmoji = false;
  bool _isSending = false;
  bool _isAtBottom = true;
  bool _showNewMessageBadge = false;
  int _unreadCount = 0;
  Timer? _debounceTyping;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_handleTyping);
    _scrollController.addListener(_handleScroll);

    _newMessageAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _newMessageAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _newMessageAnimationController,
      curve: Curves.easeOut,
    ));

    SocketService.instance.connect();
    SocketService.instance.joinConversation(widget.chatId);
  }

  @override
  void dispose() {
    _debounceTyping?.cancel();
    _textController.removeListener(_handleTyping);
    _textController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    _newMessageAnimationController.dispose();
    _setTyping(false);
    SocketService.instance.leaveConversation(widget.chatId);
    super.dispose();
  }

  void _handleScroll() {
    final isAtBottom = _scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 100;

    if (isAtBottom != _isAtBottom) {
      setState(() {
        _isAtBottom = isAtBottom;
        if (isAtBottom) {
          _showNewMessageBadge = false;
          _unreadCount = 0;
        }
      });
    }
  }

  void _handleTyping() {
    _debounceTyping?.cancel();
    _setTyping(true);
    _debounceTyping = Timer(
      const Duration(milliseconds: 900),
      () => _setTyping(false),
    );
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
      // Haptic feedback for better UX
      HapticFeedback.lightImpact();

      SocketService.instance.sendMessage(
        conversationId: widget.chatId,
        text: text,
      );

      _textController.clear();
      await _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send message')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _scrollToBottom({bool animated = true}) async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (!_scrollController.hasClients) return;

    if (animated) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent + 80);
    }
  }

  Future<void> _addReaction(String messageId, String emoji) async {
    try {
      HapticFeedback.selectionClick();
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
    final messagesAsync =
        ref.watch(_enhancedMessagesStreamProvider(widget.chatId));
    final typingData =
        ref.watch(_typingStreamProvider(widget.chatId)).maybeWhen(
              data: (data) => data,
              orElse: () => <String, dynamic>{},
            );

    // Listen for new messages and show badge if not at bottom
    ref.listen(_enhancedMessagesStreamProvider(widget.chatId),
        (previous, next) {
      next.whenData((messages) {
        if (!_isAtBottom && previous != null) {
          previous.whenData((prevMessages) {
            if (messages.length > prevMessages.length) {
              setState(() {
                _showNewMessageBadge = true;
                _unreadCount = messages.length - prevMessages.length;
              });
              _newMessageAnimationController.forward().then((_) {
                _newMessageAnimationController.reverse();
              });
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
        _inputFocusNode.unfocus();
      },
      child: Scaffold(
        backgroundColor: theme.primaryBackground,
        appBar: _buildEnhancedAppBar(theme, typingData),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    _buildMessagesList(messagesAsync, theme),
                    _buildNewMessageBadge(theme),
                  ],
                ),
              ),
              _buildTypingIndicator(typingData, theme),
              _buildEnhancedInputBar(theme),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildEnhancedAppBar(
      FlutterFlowTheme theme, Map<String, dynamic> typingData) {
    final isTyping = typingData['isTyping'] == true;
    final userName = typingData['userName']?.toString();

    return AppBar(
      elevation: 0.5,
      backgroundColor: theme.secondaryBackground,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: theme.primaryText),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: widget.isGroupChat
                    ? theme.primary.withOpacity(0.1)
                    : theme.accent2,
                backgroundImage:
                    !widget.isGroupChat && widget.recipientPhotoUrl.isNotEmpty
                        ? CachedNetworkImageProvider(widget.recipientPhotoUrl)
                        : null,
                child: widget.isGroupChat
                    ? Icon(Icons.group_rounded, color: theme.primary, size: 22)
                    : (widget.recipientPhotoUrl.isEmpty
                        ? Icon(Icons.person,
                            color: theme.secondaryText, size: 22)
                        : null),
              ),
              // Online indicator (simplified for now)
              if (!widget.isGroupChat)
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: theme.secondaryBackground, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.recipientName,
                  style:
                      theme.titleMedium.override(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  isTyping && userName != null
                      ? '$userName is typing...'
                      : widget.isGroupChat
                          ? 'Pulse Group Chat'
                          : 'Online',
                  style: theme.bodySmall.override(
                    color: isTyping ? theme.primary : theme.secondaryText,
                    fontStyle: isTyping ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (widget.isGroupChat && widget.pulseId != null)
          IconButton(
            icon: Icon(Icons.info_outline, color: theme.primaryText),
            onPressed: () {
              Navigator.of(context).pushNamed(
                '/pulse-detail',
                arguments: {'pulseId': widget.pulseId},
              );
            },
          )
        else ...[
          IconButton(
            icon: Icon(Icons.videocam_outlined, color: theme.primaryText),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Video calls coming soon!')),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.call_outlined, color: theme.primaryText),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Voice calls coming soon!')),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildMessagesList(
      AsyncValue<List<EnhancedMessage>> messagesAsync, FlutterFlowTheme theme) {
    return messagesAsync.when(
      data: (messages) {
        if (messages.isEmpty) {
          return _buildEmptyState(theme);
        }

        return RefreshIndicator(
          onRefresh: () async {
            // TODO: Load more messages
            await Future.delayed(const Duration(milliseconds: 400));
          },
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[index];
              final prevMessage = index > 0 ? messages[index - 1] : null;
              final nextMessage =
                  index < messages.length - 1 ? messages[index + 1] : null;

              final showAvatar = _shouldShowAvatar(message, nextMessage);
              final showSenderName =
                  _shouldShowSenderName(message, prevMessage);
              final showDateDivider =
                  _shouldShowDateDivider(message, prevMessage);

              return Column(
                children: [
                  if (showDateDivider)
                    _buildDateDivider(message.timestamp, theme),
                  if (message.isSystemMessage)
                    _buildSystemMessage(message, theme)
                  else
                    EnhancedMessageBubble(
                      message: message,
                      isMine: message.senderId == currentUserUid,
                      theme: theme,
                      isGroupChat: widget.isGroupChat,
                      showAvatar: showAvatar,
                      showSenderName: showSenderName,
                      onReact: (emoji) => _addReaction(message.id, emoji),
                    ),
                ],
              )
                  .animate()
                  .fadeIn(
                    duration: const Duration(milliseconds: 200),
                  )
                  .slideY(
                    begin: 0.1,
                    end: 0,
                    duration: const Duration(milliseconds: 200),
                  );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _buildErrorState(theme),
    );
  }

  Widget _buildEmptyState(FlutterFlowTheme theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 80,
            color: theme.secondaryText.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: theme.titleLarge.override(
              color: theme.secondaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Say hello 👋',
            style: theme.bodyLarge.override(
              color: theme.secondaryText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(FlutterFlowTheme theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 80,
            color: theme.error.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Unable to load messages',
            style: theme.titleLarge.override(
              color: theme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () {
              // Refresh the messages stream
              ref.invalidate(_enhancedMessagesStreamProvider(widget.chatId));
            },
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  bool _shouldShowAvatar(EnhancedMessage current, EnhancedMessage? next) {
    if (current.senderId == currentUserUid) return false;
    if (next == null) return true;
    if (next.senderId != current.senderId) return true;
    final timeDiff = next.timestamp.difference(current.timestamp).inMinutes;
    return timeDiff > 2;
  }

  bool _shouldShowSenderName(EnhancedMessage current, EnhancedMessage? prev) {
    if (!widget.isGroupChat) return false;
    if (current.senderId == currentUserUid) return false;
    if (prev == null) return true;
    if (prev.senderId != current.senderId) return true;
    final timeDiff = current.timestamp.difference(prev.timestamp).inMinutes;
    return timeDiff > 2;
  }

  bool _shouldShowDateDivider(EnhancedMessage current, EnhancedMessage? prev) {
    if (prev == null) return true;
    final currentDate = DateTime(
        current.timestamp.year, current.timestamp.month, current.timestamp.day);
    final prevDate =
        DateTime(prev.timestamp.year, prev.timestamp.month, prev.timestamp.day);
    return !currentDate.isAtSameMomentAs(prevDate);
  }

  Widget _buildDateDivider(DateTime date, FlutterFlowTheme theme) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);

    String dateText;
    if (messageDate.isAtSameMomentAs(today)) {
      dateText = 'Today';
    } else if (messageDate.isAtSameMomentAs(yesterday)) {
      dateText = 'Yesterday';
    } else {
      dateText = '${date.month}/${date.day}/${date.year}';
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: theme.secondaryText.withOpacity(0.3))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              dateText,
              style: theme.bodySmall.override(
                color: theme.secondaryText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: Divider(color: theme.secondaryText.withOpacity(0.3))),
        ],
      ),
    );
  }

  Widget _buildSystemMessage(EnhancedMessage message, FlutterFlowTheme theme) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.secondaryText.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            message.text ?? '',
            style: theme.bodySmall.override(
              color: theme.secondaryText,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildNewMessageBadge(FlutterFlowTheme theme) {
    if (!_showNewMessageBadge) return const SizedBox.shrink();

    return Positioned(
      bottom: 80,
      right: 16,
      child: AnimatedBuilder(
        animation: _newMessageAnimation,
        child: GestureDetector(
          onTap: () {
            setState(() {
              _showNewMessageBadge = false;
              _unreadCount = 0;
            });
            _scrollToBottom();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.primary,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.keyboard_arrow_down,
                    color: Colors.white, size: 16),
                const SizedBox(width: 4),
                Text(
                  '$_unreadCount new message${_unreadCount > 1 ? 's' : ''}',
                  style: theme.bodySmall.override(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        builder: (context, child) {
          return Transform.scale(
            scale: 1.0 + (_newMessageAnimation.value * 0.1),
            child: child,
          );
        },
      ),
    );
  }

  Widget _buildTypingIndicator(
      Map<String, dynamic> typingData, FlutterFlowTheme theme) {
    final isTyping = typingData['isTyping'] == true;
    final userName = typingData['userName']?.toString();

    if (!isTyping || userName == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                TypingDots(color: theme.primary),
                const SizedBox(width: 8),
                Text(
                  '$userName is typing...',
                  style: theme.bodySmall.override(
                    color: theme.primary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedInputBar(FlutterFlowTheme theme) {
    return SafeArea(
      top: false,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _textController,
        builder: (context, value, _) {
          final canSend = value.text.trim().isNotEmpty && !_isSending;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.secondaryBackground,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.emoji_emotions_outlined,
                        color: _showEmoji ? theme.primary : theme.secondaryText,
                      ),
                      onPressed: () => setState(() => _showEmoji = !_showEmoji),
                      tooltip: 'Emoji',
                    ),
                    IconButton(
                      icon: Icon(Icons.attach_file, color: theme.secondaryText),
                      onPressed: _showAttachmentOptions,
                      tooltip: 'Attach',
                    ),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: theme.primaryBackground,
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(
                            color: theme.secondaryText.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: 44,
                            maxHeight: 120,
                          ),
                          child: TextField(
                            controller: _textController,
                            focusNode: _inputFocusNode,
                            maxLines: null,
                            textCapitalization: TextCapitalization.sentences,
                            style: theme.bodyMedium,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Type a message...',
                              hintStyle: theme.bodyMedium.override(
                                color: theme.secondaryText,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: canSend
                          ? IconButton(
                              key: const ValueKey('send'),
                              onPressed: _sendText,
                              icon: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: theme.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.send_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              tooltip: 'Send',
                            )
                          : IconButton(
                              key: const ValueKey('mic'),
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text('Voice messages coming soon!')),
                                );
                              },
                              icon: Icon(
                                Icons.mic_none_rounded,
                                color: theme.secondaryText,
                              ),
                              tooltip: 'Voice message',
                            ),
                    ),
                  ],
                ),
              ),
              if (_showEmoji) _buildSimpleEmojiPicker(theme),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSimpleEmojiPicker(FlutterFlowTheme theme) {
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
      '😌',
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
      '❤️',
      '😂',
      '😮',
      '😢',
      '😡',
      '👍',
      '👎',
      '🔥',
      '💯',
      '✨',
    ];

    return Container(
      height: 200,
      color: theme.secondaryBackground,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            height: 4,
            width: 40,
            decoration: BoxDecoration(
              color: theme.secondaryText.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: emojis.length,
              itemBuilder: (context, index) {
                final emoji = emojis[index];
                return GestureDetector(
                  onTap: () {
                    _textController.text += emoji;
                    _inputFocusNode.requestFocus();
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        emoji,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAttachmentOptions() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => AttachmentOptionsSheet(
        onImageTap: _pickImage,
        onVideoTap: _pickVideo,
        theme: FlutterFlowTheme.of(context),
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (file == null) return;

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final bytes = await file.readAsBytes();
      final storageRef = FirebaseStorage.instance.ref().child(
            'chat_uploads/${widget.chatId}/${DateTime.now().millisecondsSinceEpoch}_${file.name}',
          );

      final uploadTask = await storageRef.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await uploadTask.ref.getDownloadURL();

      Navigator.of(context).pop(); // Close loading dialog

      SocketService.instance.sendMessage(
        conversationId: widget.chatId,
        imageUrl: url,
      );

      await _scrollToBottom();
    } on PlatformException catch (_) {
      Navigator.of(context).pop(); // Close loading dialog if open
    } catch (e) {
      Navigator.of(context).pop(); // Close loading dialog if open
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send image')),
        );
      }
    }
  }

  Future<void> _pickVideo() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 3),
      );
      if (file == null) return;

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final bytes = await file.readAsBytes();
      final storageRef = FirebaseStorage.instance.ref().child(
            'chat_uploads/${widget.chatId}/${DateTime.now().millisecondsSinceEpoch}_${file.name}',
          );

      final uploadTask = await storageRef.putData(
        bytes,
        SettableMetadata(contentType: 'video/mp4'),
      );
      final url = await uploadTask.ref.getDownloadURL();

      Navigator.of(context).pop(); // Close loading dialog

      SocketService.instance.sendMessage(
        conversationId: widget.chatId,
        videoUrl: url,
      );

      await _scrollToBottom();
    } on PlatformException catch (_) {
      Navigator.of(context).pop(); // Close loading dialog if open
    } catch (e) {
      Navigator.of(context).pop(); // Close loading dialog if open
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send video')),
        );
      }
    }
  }
}

// Enhanced Message Bubble Component
class EnhancedMessageBubble extends StatefulWidget {
  const EnhancedMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.theme,
    required this.isGroupChat,
    required this.showAvatar,
    required this.showSenderName,
    required this.onReact,
  });

  final EnhancedMessage message;
  final bool isMine;
  final FlutterFlowTheme theme;
  final bool isGroupChat;
  final bool showAvatar;
  final bool showSenderName;
  final Function(String emoji) onReact;

  @override
  State<EnhancedMessageBubble> createState() => _EnhancedMessageBubbleState();
}

class _EnhancedMessageBubbleState extends State<EnhancedMessageBubble>
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
      builder: (context) => ReactionPickerOverlay(
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

    final timeString = _formatTime(widget.message.timestamp);

    return Padding(
      padding: EdgeInsets.only(
        top: 4,
        bottom: 4,
        left: widget.isMine ? 80 : 16,
        right: widget.isMine ? 16 : 80,
      ),
      child: Column(
        crossAxisAlignment: align,
        children: [
          // Show sender info for group chats (not for own messages)
          if (widget.showSenderName) ...[
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.showAvatar) ...[
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: widget.theme.primary.withOpacity(0.1),
                      backgroundImage: widget.message.senderPhotoUrl != null &&
                              widget.message.senderPhotoUrl!.isNotEmpty
                          ? CachedNetworkImageProvider(
                              widget.message.senderPhotoUrl!)
                          : null,
                      child: widget.message.senderPhotoUrl == null ||
                              widget.message.senderPhotoUrl!.isEmpty
                          ? Icon(Icons.person,
                              size: 16, color: widget.theme.primary)
                          : null,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      widget.message.senderName ?? 'Unknown',
                      style: widget.theme.bodySmall.override(
                        color: widget.theme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Main message bubble
          GestureDetector(
            onLongPress: () => _showReactionOptions(context),
            child: Container(
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: radius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Image content
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
                                child: CircularProgressIndicator()),
                          ),
                          errorWidget: (c, _, __) => Container(
                            height: 160,
                            width: 240,
                            color: Colors.black12,
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.broken_image, size: 32),
                                const SizedBox(height: 8),
                                Text(
                                  'Failed to load image',
                                  style: widget.theme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (widget.message.text != null &&
                          widget.message.text!.isNotEmpty)
                        const SizedBox(height: 8),
                    ],

                    // Video content
                    if (widget.message.isVideo) ...[
                      Container(
                        width: 240,
                        height: 160,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              Icons.play_circle_fill,
                              size: 48,
                              color: Colors.white.withOpacity(0.9),
                            ),
                            Positioned(
                              bottom: 8,
                              left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.videocam,
                                      color: Colors.white,
                                      size: 12,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Video',
                                      style: widget.theme.bodySmall.override(
                                        color: Colors.white,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.message.text != null &&
                          widget.message.text!.isNotEmpty)
                        const SizedBox(height: 8),
                    ],

                    // Text content
                    if (widget.message.text != null &&
                        widget.message.text!.isNotEmpty) ...[
                      SelectableText(
                        widget.message.text!,
                        style: widget.theme.bodyMedium.override(
                          color: textColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Reactions
          if (widget.message.reactions != null &&
              widget.message.reactions!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              alignment:
                  widget.isMine ? Alignment.centerRight : Alignment.centerLeft,
              child: Wrap(
                alignment:
                    widget.isMine ? WrapAlignment.end : WrapAlignment.start,
                children: widget.message.reactions!.entries.map((entry) {
                  final emoji = entry.key;
                  final userIds = entry.value;
                  final hasMyReaction = userIds.contains(currentUserUid);

                  return AnimatedBuilder(
                    animation: _reactionAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: 1.0 + (_reactionAnimation.value * 0.1),
                        child: GestureDetector(
                          onTap: () => widget.onReact(emoji),
                          child: Container(
                            margin: const EdgeInsets.only(right: 4, bottom: 2),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: hasMyReaction
                                  ? widget.theme.primary.withOpacity(0.2)
                                  : widget.theme.secondaryBackground,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: hasMyReaction
                                    ? widget.theme.primary
                                    : widget.theme.secondaryText
                                        .withOpacity(0.3),
                                width: hasMyReaction ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  emoji,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                if (userIds.length > 1) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    userIds.length.toString(),
                                    style: widget.theme.bodySmall.override(
                                      color: hasMyReaction
                                          ? widget.theme.primary
                                          : widget.theme.secondaryText,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }).toList(),
              ),
            ),
          ],

          // Timestamp and read status
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                timeString,
                style: widget.theme.bodySmall.override(
                  color: widget.theme.secondaryText,
                  fontSize: 11,
                ),
              ),
              if (widget.message.isEdited) ...[
                const SizedBox(width: 4),
                Text(
                  '• edited',
                  style: widget.theme.bodySmall.override(
                    color: widget.theme.secondaryText,
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              if (widget.isMine) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.done_all,
                  size: 14,
                  color: widget.message.readBy != null &&
                          widget.message.readBy!.length > 1
                      ? widget.theme.primary
                      : widget.theme.secondaryText,
                ),
              ],
            ],
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

// Reaction Picker Overlay
class ReactionPickerOverlay extends StatelessWidget {
  const ReactionPickerOverlay({
    super.key,
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

// Typing Dots Animation
class TypingDots extends StatefulWidget {
  const TypingDots({super.key, required this.color});
  final Color color;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (index) {
      return AnimationController(
        duration: const Duration(milliseconds: 600),
        vsync: this,
      );
    });

    _animations = _controllers.map((controller) {
      return Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      );
    }).toList();

    // Start animations with delays
    for (int i = 0; i < _controllers.length; i++) {
      Future.delayed(Duration(milliseconds: i * 200), () {
        if (mounted) {
          _controllers[i].repeat(reverse: true);
        }
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _animations[index],
          builder: (context, child) {
            return Container(
              margin: EdgeInsets.only(right: index < 2 ? 4 : 0),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: widget.color.withOpacity(_animations[index].value),
                shape: BoxShape.circle,
              ),
            );
          },
        );
      }),
    );
  }
}

// Attachment Options Sheet
class AttachmentOptionsSheet extends StatelessWidget {
  const AttachmentOptionsSheet({
    super.key,
    required this.onImageTap,
    required this.onVideoTap,
    required this.theme,
  });

  final VoidCallback onImageTap;
  final VoidCallback onVideoTap;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) {
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
              height: 4,
              width: 40,
              decoration: BoxDecoration(
                color: theme.secondaryText.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
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
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
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
    final theme = FlutterFlowTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: theme.titleMedium.override(
                color: theme.primaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
