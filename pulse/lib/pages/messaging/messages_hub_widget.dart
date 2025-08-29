import '/flutter_flow/flutter_flow_theme.dart';
import 'package:flutter/material.dart';
import '/components/navbar_widget.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/firebase_auth/auth_util.dart';
import '../../backend/api_service.dart';
import '../../backend/socket_service.dart';
import 'enhanced_messaging_page.dart';
import 'live_group_chat_page.dart';
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

  (() async {
    final list = await ApiService.instance.listConversations();
    items = (list ?? []).toList();
    controller.add(items);
  })();

  final sub = SocketService.instance.conversationUpdates.listen((_) async {
    final list = await ApiService.instance.listConversations();
    items = (list ?? []).toList();
    controller.add(items);
  });

  ref.onDispose(() {
    sub.cancel();
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
    final list = await ApiService.instance.listConversations();
    items = (list ?? []).where(isPulseGroup).toList();
    // Debug: counts
    // ignore: avoid_print
    print(
        '[PulseChats] total=${list?.length ?? 0} pulseGroups=${items.length}');
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
    final list = await ApiService.instance.listConversations();
    items = (list ?? []).where(isPulseGroup).toList();
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

  Widget _buildDirectChatTile(BuildContext context, Map<String, dynamic> data,
      FlutterFlowTheme theme, String uid) {
    final List<dynamic> participants =
        (data['participants'] as List<dynamic>? ?? []);
    final other = participants
        .whereType<Map<String, dynamic>>()
        .firstWhere((p) => p['id'] != uid, orElse: () => <String, dynamic>{});
    final otherId = other['id']?.toString() ?? '';
    final otherName = other['displayName']?.toString() ?? otherId;
    final otherPhoto = other['profileImageUrl']?.toString() ?? '';
    final lastMessage = (data['lastMessageText'] as String?) ?? '';
    final updatedAt = DateTime.tryParse(data['updatedAt']?.toString() ?? '');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        backgroundImage:
            otherPhoto.isNotEmpty ? NetworkImage(otherPhoto) : null,
        child: otherPhoto.isEmpty ? const Icon(Icons.person) : null,
      ),
      title: Text(
        otherName.isEmpty ? 'Unknown' : otherName,
        style: theme.titleMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        lastMessage.isNotEmpty ? lastMessage : 'Say hi 👋',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: updatedAt != null
          ? Text(
              dateTimeFormat('relative', updatedAt),
              style: theme.bodySmall.override(color: theme.secondaryText),
            )
          : null,
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

                return asyncConvos.when(
                  data: (directChats) {
                    return asyncPulseConvos.when(
                      data: (pulseChats) {
                        // Filter direct chats to exclude pulse group chats
                        final pulseIds = pulseChats
                            .map((c) => c['id']?.toString())
                            .whereType<String>()
                            .toSet();
                        final filteredDirectChats = directChats.where((conv) {
                          final isGroup = conv['isGroup'] == true;
                          final id = conv['id']?.toString();
                          if (id != null && pulseIds.contains(id)) {
                            return false; // already classified as pulse group
                          }
                          if (!isGroup) return true; // direct 1:1
                          // For safety: treat any group lacking explicit pulse markers as direct group (future multi-person DMs?) only if <=2 participants
                          final participants =
                              (conv['participants'] as List?) ?? [];
                          final pulseKeyPresent = [
                            'pulseId',
                            'pulse_id',
                            'pulseID',
                            'pulse',
                            'pulseUuid'
                          ].any((k) => conv[k] != null);
                          if (pulseKeyPresent) return false;
                          return participants.length <=
                              2; // else assume pulse group
                        }).toList();

                        if (filteredDirectChats.isEmpty && pulseChats.isEmpty) {
                          return Center(
                            child: Text(
                              'No conversations yet',
                              style: theme.bodyMedium
                                  .override(color: theme.secondaryText),
                            ),
                          );
                        }

                        return ListView(
                          children: [
                            // Pulse Group Chats Section
                            if (pulseChats.isNotEmpty) ...[
                              Container(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                              if (filteredDirectChats.isNotEmpty)
                                Divider(height: 24, color: theme.alternate),
                            ],

                            // Direct Messages Section
                            if (filteredDirectChats.isNotEmpty) ...[
                              Container(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                              ...filteredDirectChats.map((data) =>
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
          : FloatingActionButton.extended(
              onPressed: () async {
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
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('New message'),
            ),
      bottomNavigationBar: const NavbarWidget(),
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
