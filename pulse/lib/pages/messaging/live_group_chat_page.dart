import 'dart:async';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:characters/characters.dart';
import '../../auth/firebase_auth/auth_util.dart';
import '../../backend/api_service.dart';
import '../../backend/socket_service.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import 'package:permission_handler/permission_handler.dart';
import '../calling/group_call_screen.dart';

/// Live, energetic TikTok/IG-Live inspired group chat experience.
/// Focus: floating reactions, animated presence, inline media, quick hype.
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
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _focus = FocusNode();
  final List<_LiveMsg> _messages = [];
  final StreamController<_FloatingReaction> _floatingCtl =
      StreamController.broadcast();
  late ConfettiController _confetti;
  bool _sending = false;
  int _messageCount = 0;
  Timer? _typingDebounce;
  bool _someoneTyping = false;
  final _random = Random();
  // Inline reaction via system emoji keyboard
  final TextEditingController _reactionInputCtl = TextEditingController();
  final FocusNode _reactionFocus = FocusNode();
  String? _reactingToMessageId; // Message currently awaiting emoji reaction

  late final Map<String, Map<String, dynamic>> _memberIndex = {
    for (final m in (widget.members ?? []))
      (m['id'] ?? m['userId'] ?? m['uid']).toString(): m
  };

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 2));
    SocketService.instance.connect();
    SocketService.instance.joinConversation(widget.chatId);
    _bootstrap();
    SocketService.instance.messages.listen(_onSocketMessage);
    SocketService.instance.typing.listen(_onTyping);
  }

  Future<void> _bootstrap() async {
    final res = await ApiService.instance.listMessages(widget.chatId);
    final msgs = (res?['messages'] as List<dynamic>? ?? [])
        .map((m) => _LiveMsg.fromJson(m as Map<String, dynamic>))
        .toList();
    if (msgs.isNotEmpty) {
      // Debug: log first 3 messages' reactions structure
      // ignore: avoid_print
      print('[LiveChat bootstrap] loaded ' +
          msgs.length.toString() +
          ' messages');
      for (final m in msgs.take(3)) {
        // ignore: avoid_print
        print(' msg id=' + m.id + ' reactions=' + m.reactions.toString());
      }
      // Also raw sample if backend returns nested shape
      final rawList = (res?['messages'] as List<dynamic>? ?? []);
      if (rawList.isNotEmpty) {
        // ignore: avoid_print
        print(' raw sample[0]=' + rawList.first.toString());
      }
    }
    setState(() => _messages.addAll(msgs));
    _jumpBottom();
  }

  void _onSocketMessage(dynamic raw) {
    try {
      final map = Map<String, dynamic>.from(raw as Map);
      if (map['conversationId'] != widget.chatId) return;
      // ignore: avoid_print
      print('[LiveChat socket] event=' + map.toString());
      // Reaction update path
      final maybeId = map['id']?.toString() ?? map['messageId']?.toString();
      // Case 1: full reactions map delivered
      if (maybeId != null && map['reactions'] != null) {
        final idx = _messages.indexWhere((m) => m.id == maybeId);
        if (idx != -1) {
          final parsed = _parseReactions(map['reactions']);
          if (parsed.isNotEmpty) {
            final updated = _messages[idx].copyWith(reactions: parsed);
            setState(() => _messages[idx] = updated);
            return; // handled as reaction update
          }
        }
      }
      // Case 2: incremental reaction event (emoji + userId)
      if (maybeId != null && map['emoji'] != null && map['userId'] != null) {
        final idx = _messages.indexWhere((m) => m.id == maybeId);
        if (idx != -1) {
          final emoji = map['emoji'].toString();
          final userId = map['userId'].toString();
          final current =
              Map<String, List<String>>.from(_messages[idx].reactions);
          final list = List<String>.from(current[emoji] ?? []);
          if (list.contains(userId)) {
            // Toggle off if already present (assuming server broadcast toggle)
            list.remove(userId);
          } else {
            list.add(userId);
          }
          if (list.isEmpty) {
            current.remove(emoji);
          } else {
            current[emoji] = list;
          }
          setState(() =>
              _messages[idx] = _messages[idx].copyWith(reactions: current));
          return; // handled
        }
      }
      final msg = _LiveMsg.fromJson(map);
      setState(() => _messages.add(msg));
      _messageCount++;
      _maybeCelebrate();
      _animateInReactionAuto(msg);
      _autoScroll();
    } catch (_) {}
  }

  void _onTyping(dynamic raw) {
    try {
      final map = Map<String, dynamic>.from(raw as Map);
      if (map['conversationId'] != widget.chatId) return;
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
    _scroll.jumpTo(_scroll.position.maxScrollExtent + 200);
  }

  Future<void> _animateToBottom() async {
    if (!_scroll.hasClients) return;
    await _scroll.animateTo(_scroll.position.maxScrollExtent + 120,
        duration: 300.ms, curve: Curves.easeOut);
  }

  Future<void> _send() async {
    final txt = _input.text.trim();
    if (txt.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      SocketService.instance.sendMessage(
        conversationId: widget.chatId,
        text: txt,
      );
      _input.clear();
      _setTyping(false);
      _animateToBottom();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _setTyping(bool v) {
    SocketService.instance.setTyping(widget.chatId, v);
  }

  void _maybeCelebrate() {
    if (_messageCount == 100 ||
        _messageCount == 250 ||
        _messageCount % 500 == 0) {
      _confetti.play();
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

  void _quickReaction(String emoji) {
    HapticFeedback.lightImpact();
    _spawnReaction(emoji);
    SocketService.instance
        .sendMessage(conversationId: widget.chatId, text: emoji);
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
    SocketService.instance.leaveConversation(widget.chatId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        _focus.unfocus();
      },
      child: Scaffold(
        backgroundColor: theme.primaryBackground,
        body: Stack(children: [
          // Subtle animated gradient backdrop for energy while honoring theme palette
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: 800.ms,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.6),
                    radius: 1.2,
                    colors: [
                      (isDark
                          ? theme.secondaryBackground
                          : theme.primaryBackground),
                      (isDark
                          ? theme.primary.withOpacity(.12)
                          : theme.accent1.withOpacity(.15)),
                      (isDark
                          ? theme.primaryBackground
                          : theme.secondaryBackground),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Column(children: [
            _topBar(theme, isDark),
            Expanded(child: _chatFeed(theme)),
            if (_someoneTyping) _typingBubble(theme),
            _quickReactions(theme),
            _composer(theme),
          ]),
          _floatingReactionsLayer(),
          _confettiWidget(theme),
          if (_reactingToMessageId != null) _emojiReactionOverlay(theme),
        ]),
      ),
    );
  }

  Widget _topBar(FlutterFlowTheme t, bool isDark) {
    final bg = t.secondaryBackground;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 42, 12, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(isDark ? .4 : .08),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
        border: Border(
          bottom: BorderSide(color: t.primary.withOpacity(.15), width: 1),
        ),
      ),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.of(context).maybePop(),
          child: Icon(Icons.arrow_back_ios_new,
              color: t.primaryText.withOpacity(.9), size: 20),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(widget.groupName,
                      style: t.titleMedium.override(
                        color: t.primaryText,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [t.primary, t.tertiary]),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                          color: t.primary.withOpacity(.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3))
                    ],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.flash_on, color: t.info, size: 14),
                    const SizedBox(width: 4),
                    Text('LIVE',
                        style: t.bodySmall.override(
                            color: t.info,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1))
                  ]),
                )
              ]),
              const SizedBox(height: 2),
              Text(widget.pulseName ?? 'Group Pulse',
                  style: t.bodySmall.override(
                      color: t.secondaryText, fontWeight: FontWeight.w500))
            ],
          ),
        ),
        IconButton(
          onPressed: () async {
            final p = await Permission.microphone.request();
            if (!p.isGranted) return;
            if (!mounted) return;
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => GroupCallScreen(
                conversationId: widget.chatId,
                isVideo: false,
              ),
            ));
          },
          icon: Icon(Icons.call_rounded, color: t.primaryText),
          tooltip: 'Start group voice call',
        ),
        IconButton(
          onPressed: () {},
          icon: Icon(Icons.info_outline, color: t.primaryText),
        ),
        IconButton(
          onPressed: () async {
            final res =
                await [Permission.microphone, Permission.camera].request();
            final micOk = res[Permission.microphone]?.isGranted == true;
            final camOk = res[Permission.camera]?.isGranted == true;
            if (!micOk || !camOk) return;
            if (!mounted) return;
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => GroupCallScreen(
                conversationId: widget.chatId,
                isVideo: true,
              ),
            ));
          },
          icon: Icon(Icons.videocam_rounded, color: t.primaryText),
          tooltip: 'Start group video call',
        ),
        IconButton(
          onPressed: _openAddMembers,
          icon: Icon(Icons.person_add_alt_1, color: t.primaryText),
        ),
      ]),
    );
  }

  Widget _chatFeed(FlutterFlowTheme t) {
    if (_messages.isEmpty) return _emptyState(t);
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final m = _messages[i];
        final prev = i > 0 ? _messages[i - 1] : null;
        final showHeader = prev == null || prev.senderId != m.senderId;
        return _liveBubble(m, showHeader, t)
            .animate()
            .fadeIn(duration: 250.ms)
            .slideY(begin: .12, end: 0, curve: Curves.easeOut);
      },
    );
  }

  Widget _liveBubble(_LiveMsg m, bool header, FlutterFlowTheme t) {
    final mine = m.senderId == currentUserUid;
    // Theme-aligned gradients: own messages use primary hues, others subtle surface blend.
    final color = mine
        ? LinearGradient(colors: [t.primary, t.primary.withOpacity(.8)])
        : LinearGradient(colors: [
            t.secondaryBackground,
            t.secondaryBackground.withOpacity(.95)
          ]);
    final name = _resolveName(m.senderId) ?? 'User';
    return GestureDetector(
      onDoubleTap: () => _quickReaction('❤️'),
      onLongPress: () => _startReactionInput(m),
      child: Container(
        margin: EdgeInsets.only(
          top: header ? 8 : 2,
          bottom: 2,
          left: mine ? 60 : 0,
          right: mine ? 0 : 60,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: color,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
          boxShadow: [
            BoxShadow(
                color: mine
                    ? t.primary.withOpacity(.35)
                    : Colors.black.withOpacity(.08),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
          border: Border.all(
            color: mine
                ? t.primary.withOpacity(.6)
                : t.secondaryText.withOpacity(.15),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (header)
              Row(children: [
                _avatar(m.senderId),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(name,
                      style: t.bodySmall.override(
                          color: mine ? t.info : t.primaryText,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ),
                Text(_fmt(m.timestamp),
                    style: t.bodySmall.override(
                        color: mine ? t.info.withOpacity(.8) : t.secondaryText,
                        fontSize: 10,
                        fontWeight: FontWeight.w500))
              ]),
            if (header) const SizedBox(height: 6),
            if (m.text != null)
              Text(m.text!,
                  style: t.bodyMedium.override(
                      color: mine ? t.info : t.primaryText,
                      fontSize: 15,
                      lineHeight: 1.25)),
            if (m.reactions.isNotEmpty) const SizedBox(height: 8),
            if (m.reactions.isNotEmpty)
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final entry in m.reactions.entries)
                    _reactionChip(t, m, entry.key, entry.value),
                  _addReactionChip(t, m),
                ],
              ),
            if (m.reactions.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _addReactionChip(t, m),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _reactionChip(
      FlutterFlowTheme t, _LiveMsg m, String emoji, List<String> userIds) {
    final reacted = userIds.contains(currentUserUid);
    return GestureDetector(
      onTap: () => _toggleReaction(m, emoji),
      child: AnimatedContainer(
        duration: 150.ms,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: reacted ? t.primary.withOpacity(.2) : t.secondaryBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: reacted ? t.primary : t.secondaryText.withOpacity(.15)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          Text('${userIds.length}',
              style: t.bodySmall.override(
                  color: reacted ? t.primary : t.secondaryText,
                  fontWeight: reacted ? FontWeight.w700 : FontWeight.w500)),
        ]),
      ).animate().scale(duration: 120.ms, curve: Curves.easeOutBack),
    );
  }

  Widget _addReactionChip(FlutterFlowTheme t, _LiveMsg m) => GestureDetector(
        onTap: () => _startReactionInput(m),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: t.secondaryBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.secondaryText.withOpacity(.12)),
          ),
          child: Icon(Icons.add_reaction_outlined,
              size: 16, color: t.secondaryText.withOpacity(.8)),
        ),
      );

  void _startReactionInput(_LiveMsg m) {
    setState(() => _reactingToMessageId = m.id);
    _reactionInputCtl.clear();
    // Request focus slightly later to ensure overlay built
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
    if (v.isEmpty) return; // Await an emoji
    // Grab the last grapheme cluster (handles multi-codepoint emoji)
    final last = v.characters.last;
    // Apply reaction then exit mode
    final msg = _messages.firstWhere((e) => e.id == _reactingToMessageId,
        orElse: () => _messages.last);
    _toggleReaction(msg, last);
    _cancelReactionInput();
  }

  Widget _emojiReactionOverlay(FlutterFlowTheme t) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: _cancelReactionInput,
        behavior: HitTestBehavior.opaque,
        child: Stack(children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).viewInsets.bottom + 80,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: t.secondaryBackground,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: t.primary.withOpacity(.25)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(.15),
                        blurRadius: 18,
                        offset: const Offset(0, 6))
                  ],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.touch_app, size: 18),
                  const SizedBox(width: 8),
                  Text('Pick an emoji…',
                      style: t.bodyMedium.override(
                          color: t.primaryText, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 12),
                  if (_reactionInputCtl.text.isNotEmpty)
                    Text(_reactionInputCtl.text.characters.last,
                        style: const TextStyle(fontSize: 24)),
                  // Hidden text field to receive emoji input
                  SizedBox(
                    width: 0,
                    height: 0,
                    child: TextField(
                      controller: _reactionInputCtl,
                      focusNode: _reactionFocus,
                      autofocus: true,
                      onChanged: _onReactionInputChanged,
                      decoration:
                          const InputDecoration(border: InputBorder.none),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _cancelReactionInput,
                    child: Icon(Icons.close,
                        size: 18, color: t.secondaryText.withOpacity(.8)),
                  )
                ]),
              ),
            ),
          ),
        ]),
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
      // Emit toggle event as well so backend persists removal (backend expected to handle idempotent toggle)
      SocketService.instance.addReaction(
          conversationId: widget.chatId, messageId: m.id, emoji: emoji);
    } else {
      list.add(currentUserUid);
      SocketService.instance.addReaction(
          conversationId: widget.chatId, messageId: m.id, emoji: emoji);
    }
    if (list.isEmpty) {
      map.remove(emoji);
    } else {
      map[emoji] = list;
    }
    setState(() => _messages[idx] = current.copyWith(reactions: map));
  }

  Map<String, List<String>> _parseReactions(dynamic raw) {
    // Accept both map shape: {"🔥":["uid1","uid2"]} and list shape: [{emoji:"🔥", userId:"uid"}, ...]
    if (raw is Map<String, dynamic>) {
      try {
        return raw.map((k, v) =>
            MapEntry(k, (v as List).map((e) => e.toString()).toList()));
      } catch (_) {
        // fallthrough
      }
    }
    if (raw is List) {
      final Map<String, List<String>> out = {};
      for (final item in raw) {
        if (item is Map) {
          final emoji = item['emoji']?.toString();
          final userId = item['userId']?.toString();
          if (emoji != null &&
              userId != null &&
              emoji.isNotEmpty &&
              userId.isNotEmpty) {
            out.putIfAbsent(emoji, () => []).add(userId);
          }
        }
      }
      return out;
    }
    return {};
  }

  Widget _avatar(String uid) {
    final m = _memberIndex[uid];
    final url = (m?['photoUrl'] ?? m?['avatar'])?.toString();
    final glow = _random.nextBool();
    return Container(
      padding: const EdgeInsets.all(2.2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: glow
            ? LinearGradient(
                colors: [
                  FlutterFlowTheme.of(context).primary,
                  FlutterFlowTheme.of(context).tertiary
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        boxShadow: [
          if (glow)
            BoxShadow(
                color: FlutterFlowTheme.of(context).primary.withOpacity(.45),
                blurRadius: 12,
                spreadRadius: 1)
        ],
      ),
      child: CircleAvatar(
        radius: 14,
        backgroundColor: FlutterFlowTheme.of(context).primary.withOpacity(.08),
        backgroundImage: url != null && url.isNotEmpty
            ? CachedNetworkImageProvider(url)
            : null,
        child: url == null
            ? Icon(Icons.person,
                color:
                    FlutterFlowTheme.of(context).secondaryText.withOpacity(.6),
                size: 16)
            : null,
      ),
    );
  }

  Widget _composer(FlutterFlowTheme t) {
    final canSend = _input.text.trim().isNotEmpty && !_sending;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: t.secondaryBackground,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(.08),
                blurRadius: 16,
                offset: const Offset(0, -4))
          ],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: t.primary.withOpacity(.15))),
        ),
        child: Row(children: [
          GestureDetector(
            onTap: () {
              // Focus text field; user can switch to emoji keyboard manually
              FocusScope.of(context).requestFocus(_focus);
            },
            child: AnimatedContainer(
              duration: 200.ms,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [t.primary, t.tertiary]),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black54,
                      blurRadius: 8,
                      offset: Offset(0, 2))
                ],
              ),
              child: Icon(Icons.emoji_emotions, color: t.info),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: t.primaryBackground,
                borderRadius: BorderRadius.circular(40),
                border: Border.all(
                    color: t.secondaryText.withOpacity(.15), width: 1),
              ),
              child: TextField(
                controller: _input,
                focusNode: _focus,
                onChanged: (v) {
                  _typingDebounce?.cancel();
                  _setTyping(true);
                  _typingDebounce =
                      Timer(const Duration(milliseconds: 900), () {
                    _setTyping(false);
                  });
                  setState(() {});
                },
                minLines: 1,
                maxLines: 5,
                style:
                    t.bodyMedium.override(color: t.primaryText, fontSize: 15),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Chat live... ',
                  hintStyle: t.bodyMedium.override(color: t.secondaryText),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: canSend ? _send : null,
            child: AnimatedScale(
              scale: canSend ? 1 : .85,
              duration: 200.ms,
              curve: Curves.easeOutBack,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [t.primary, t.tertiary]),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black54,
                        blurRadius: 8,
                        offset: Offset(0, 2))
                  ],
                ),
                child: Icon(Icons.send_rounded, color: t.info, size: 20),
              ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(
                  begin: const Offset(1, 1),
                  end: const Offset(1.05, 1.05),
                  duration: 1200.ms,
                  curve: Curves.easeInOut),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _quickReactions(FlutterFlowTheme t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: t.secondaryBackground,
        border: Border(top: BorderSide(color: t.primary.withOpacity(.1))),
      ),
      child: Row(children: [
        for (final e in ['🔥', '❤️', '😂', '👀', '🎉'])
          GestureDetector(
            onTap: () => _quickReaction(e),
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Text(e, style: const TextStyle(fontSize: 26)),
            ).animate().scale(duration: 200.ms, curve: Curves.easeOutBack),
          ),
        const Spacer(),
      ]),
    );
  }

  Widget _typingBubble(FlutterFlowTheme t) => Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 18, bottom: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: t.secondaryBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: t.primary.withOpacity(.15)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _dot(),
            const SizedBox(width: 4),
            _dot(150),
            const SizedBox(width: 4),
            _dot(300),
            const SizedBox(width: 10),
            Text('Typing...',
                style:
                    t.bodySmall.override(color: t.secondaryText, fontSize: 12)),
          ]),
        ),
      );

  Widget _dot([int delay = 0]) => Animate(
        effects: [FadeEffect(duration: 500.ms, begin: .2, end: 1)],
        onPlay: (c) {
          if (delay > 0) {
            Future.delayed(
                Duration(milliseconds: delay), () => c.repeat(reverse: true));
          } else {
            c.repeat(reverse: true);
          }
        },
        child: Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
                color: Colors.white70, shape: BoxShape.circle)),
      );

  Widget _floatingReactionsLayer() {
    return Positioned.fill(
      child: IgnorePointer(
        child: StreamBuilder<_FloatingReaction>(
          stream: _floatingCtl.stream,
          builder: (context, snapshot) {
            return Stack(children: [
              for (final r in _floatingCtl.hasListener ? _activeReactions : [])
                r,
            ]);
          },
        ),
      ),
    );
  }

  final List<_FloatingReactionWidget> _activeReactions = [];
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _floatingCtl.stream.listen((data) {
      final widget = _FloatingReactionWidget(
        key: ValueKey(data.id),
        reaction: data,
        onRemove: (id) {
          _activeReactions.removeWhere((w) => w.reaction.id == id);
          if (mounted) setState(() {});
        },
      );
      _activeReactions.add(widget);
      setState(() {});
    });
  }

  Widget _confettiWidget(FlutterFlowTheme t) => Align(
        alignment: Alignment.topCenter,
        child: ConfettiWidget(
          confettiController: _confetti,
          shouldLoop: false,
          blastDirectionality: BlastDirectionality.explosive,
          emissionFrequency: 0.05,
          numberOfParticles: 24,
          maxBlastForce: 30,
          minBlastForce: 8,
          colors: [t.primary, t.tertiary, t.secondary, t.info],
        ),
      );

  Widget _emptyState(FlutterFlowTheme t) => Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Icon(Icons.bolt, color: t.primary.withOpacity(.25), size: 80),
              const SizedBox(height: 16),
              Text('This Pulse is heating up 🔥',
                  style: t.titleMedium.override(
                      color: t.primaryText.withOpacity(.85),
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Drop the first message!',
                  style: t.bodySmall.override(color: t.secondaryText)),
              const SizedBox(height: 24),
              Wrap(spacing: 12, children: [
                _firstBtn(t, '👋 Say Hi', () => _quickReaction('👋')),
                _firstBtn(t, '🎉 Send Hype', () => _quickReaction('🎉')),
                _firstBtn(t, '😂 Send a Meme', () => _quickReaction('😂')),
              ])
            ],
          ),
        ),
      );

  Widget _firstBtn(FlutterFlowTheme t, String label, VoidCallback cb) =>
      GestureDetector(
        onTap: cb,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [t.primary, t.tertiary]),
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black45, blurRadius: 10, offset: Offset(0, 3))
            ],
          ),
          child: Text(label,
              style: t.bodyMedium
                  .override(color: t.info, fontWeight: FontWeight.w600)),
        ).animate().scale(duration: 250.ms, curve: Curves.easeOutBack),
      );

  String? _resolveName(String id) {
    final m = _memberIndex[id];
    return (m?['displayName'] ?? m?['name'] ?? m?['username'])?.toString();
  }

  String _fmt(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final am = t.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $am';
  }

  Future<void> _openAddMembers() async {
    final theme = FlutterFlowTheme.of(context);
    // Build exclusion set: existing conversation members + (if available) pulse participants
    final exclusionIds = _memberIndex.keys.toSet();
    if (widget.pulseName != null && widget.pulseName!.isNotEmpty) {
      try {
        final pulseParticipants =
            await ApiService.instance.getPulseParticipants(widget.pulseName!);
        final dynamicList = (pulseParticipants?['participants'] ??
            pulseParticipants?['allParticipants'] ??
            pulseParticipants?['data']?['participants']) as List<dynamic>?;
        if (dynamicList != null) {
          for (final p in dynamicList) {
            if (p is Map<String, dynamic>) {
              final id = (p['id'] ?? p['userId'] ?? p['uid'])?.toString();
              if (id != null && id.isNotEmpty) {
                exclusionIds.add(id);
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Failed to load pulse participants for exclusion: $e');
      }
    }

    final selected = await showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return _AddMembersDialog(
          existingIds: exclusionIds,
          theme: theme,
        );
      },
    );
    if (selected == null || selected.isEmpty) return;
    final res = await ApiService.instance
        .addMembersToConversation(widget.chatId, selected);
    if (res != null) {
      // optimistic: add placeholder members to index
      for (final id in selected) {
        _memberIndex[id] = {'id': id, 'displayName': 'New Member'};
      }
      if (mounted) setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Invitation sent to ${selected.length} user${selected.length == 1 ? '' : 's'}')));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Failed to add members'),
            backgroundColor: Colors.redAccent));
      }
    }
  }
}

class _AddMembersDialog extends StatefulWidget {
  const _AddMembersDialog({
    required this.existingIds,
    required this.theme,
  });
  final Set<String> existingIds;
  final FlutterFlowTheme theme;

  @override
  State<_AddMembersDialog> createState() => _AddMembersDialogState();
}

class _AddMembersDialogState extends State<_AddMembersDialog> {
  final _searchCtl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  List<Map<String, dynamic>> _baseUsers = [];
  final Set<String> _selected = {};
  bool _loading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchCtl.addListener(_onChanged);
    _primeSuggestions();
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _runSearch);
  }

  Future<void> _primeSuggestions() async {
    setState(() => _loading = true);
    try {
      await ApiService.instance.ensureUserExists();
      final uid = currentUserUid;
      if (uid.isEmpty) return;
      final followers = await ApiService.instance.getUserFollowers(uid) ?? [];
      final following = await ApiService.instance.getUserFollowing(uid) ?? [];
      final Set<String> seen = {};
      final List<Map<String, dynamic>> combined = [];
      // Prioritize people the user follows (outgoing) then followers
      for (final u in following) {
        final id = (u['id'] ?? u['userId'] ?? u['uid']).toString();
        if (id.isEmpty || widget.existingIds.contains(id) || seen.contains(id))
          continue;
        seen.add(id);
        combined.add(u);
      }
      for (final u in followers) {
        final id = (u['id'] ?? u['userId'] ?? u['uid']).toString();
        if (id.isEmpty || widget.existingIds.contains(id) || seen.contains(id))
          continue;
        seen.add(id);
        combined.add(u);
      }
      _baseUsers = combined;
      _applyFilter();
    } catch (e) {
      debugPrint('Prime suggestions error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    final q = _searchCtl.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _results = _baseUsers);
      return;
    }
    setState(() {
      _results = _baseUsers.where((u) {
        final name = (u['displayName'] ?? u['name'] ?? u['username'] ?? '')
            .toString()
            .toLowerCase();
        return name.contains(q);
      }).toList();
    });
  }

  Future<void> _runSearch() async {
    _applyFilter();
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    return Dialog(
      backgroundColor: t.secondaryBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Add Members',
                        style: t.titleMedium
                            .override(fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close))
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchCtl,
                decoration: InputDecoration(
                  hintText: 'Search users...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: t.primaryBackground,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide:
                          BorderSide(color: t.primary.withOpacity(.15))),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              if (!_loading)
                Expanded(
                  child: _results.isEmpty
                      ? Center(
                          child: Text('No users',
                              style: t.bodySmall.override(
                                color: t.secondaryText,
                              )),
                        )
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (_, i) {
                            final u = _results[i];
                            final id =
                                (u['id'] ?? u['uid'] ?? u['userId']).toString();
                            if (widget.existingIds.contains(id)) {
                              return const SizedBox.shrink();
                            }
                            final name = (u['displayName'] ??
                                    u['name'] ??
                                    u['username'] ??
                                    id)
                                .toString();
                            final selected = _selected.contains(id);
                            return ListTile(
                              onTap: () => _toggle(id),
                              leading: CircleAvatar(
                                  child: Text(name.isNotEmpty
                                      ? name[0].toUpperCase()
                                      : '?')),
                              title: Text(name, style: t.bodyMedium),
                              trailing: AnimatedContainer(
                                duration: 200.ms,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? t.primary
                                      : t.secondaryBackground,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: t.primary.withOpacity(.4)),
                                ),
                                child: Text(selected ? 'Selected' : 'Select',
                                    style: t.bodySmall.override(
                                      color:
                                          selected ? t.info : t.secondaryText,
                                      fontWeight: FontWeight.w600,
                                    )),
                              ),
                            );
                          },
                        ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _selected.isEmpty
                          ? null
                          : () => Navigator.pop(context, _selected.toList()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: t.primary,
                        foregroundColor: t.info,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text('Add (${_selected.length})'),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

class _FloatingReactionWidgetState extends State<_FloatingReactionWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: widget.reaction.durationMs));
    _anim = CurvedAnimation(parent: _ctl, curve: Curves.easeOut);
    _ctl.forward();
    _ctl.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onRemove(widget.reaction.id);
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reaction;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final y = (1 - _anim.value) * 1.1; // start below
        final x = r.startX + (r.drift * _anim.value);
        final opacity = (1 - (_anim.value * .2)).clamp(0.0, 1.0);
        return Positioned(
          left: x * MediaQuery.of(context).size.width,
          bottom: y * MediaQuery.of(context).size.height * .2,
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: r.scale * (1 + _anim.value * .2),
              child: Text(r.emoji, style: const TextStyle(fontSize: 32)),
            ),
          ),
        );
      },
    );
  }
}

// Re-introduced model classes (were trimmed earlier during edits)
class _FloatingReactionWidget extends StatefulWidget {
  const _FloatingReactionWidget({
    super.key,
    required this.reaction,
    required this.onRemove,
  });
  final _FloatingReaction reaction;
  final void Function(String id) onRemove;
  @override
  State<_FloatingReactionWidget> createState() =>
      _FloatingReactionWidgetState();
}

class _FloatingReaction {
  _FloatingReaction({
    required this.id,
    required this.emoji,
    required this.startX,
    required this.drift,
    required this.scale,
    required this.durationMs,
  });
  final String id;
  final String emoji;
  final double startX;
  final double drift;
  final double scale;
  final int durationMs;
}

// _LiveMsg model already exists earlier in file; ensure not duplicated.
class _LiveMsg {
  _LiveMsg({
    required this.id,
    required this.senderId,
    required this.timestamp,
    this.text,
    Map<String, List<String>>? reactions,
  }) : reactions = reactions ?? {};
  final String id;
  final String senderId;
  final DateTime timestamp;
  final String? text;
  final Map<String, List<String>> reactions;
  factory _LiveMsg.fromJson(Map<String, dynamic> json) => _LiveMsg(
        id: json['id']?.toString() ??
            json['messageId']?.toString() ??
            UniqueKey().toString(),
        senderId: json['senderId']?.toString() ??
            json['userId']?.toString() ??
            'unknown',
        timestamp: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        text: json['text'] as String?,
        reactions: (json['reactions'] is Map<String, dynamic>)
            ? (json['reactions'] as Map<String, dynamic>).map((k, v) =>
                MapEntry(k, (v as List).map((e) => e.toString()).toList()))
            : {},
      );

  _LiveMsg copyWith({
    String? text,
    Map<String, List<String>>? reactions,
  }) =>
      _LiveMsg(
        id: id,
        senderId: senderId,
        timestamp: timestamp,
        text: text ?? this.text,
        // Create a defensive copy to avoid accidental external mutation.
        reactions: reactions != null
            ? {
                for (final e in reactions.entries)
                  e.key: List<String>.from(e.value)
              }
            : {
                for (final e in this.reactions.entries)
                  e.key: List<String>.from(e.value)
              },
      );
}
