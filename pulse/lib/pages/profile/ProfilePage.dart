import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import '../pulse_detail/pulse_detail_page.dart';
import '../messaging/enhanced_messaging_page.dart';
import '../../backend/api_service.dart';

// Simple profile model for viewing other users
class PublicProfile {
  final String id;
  final String username;
  final String displayName;
  final String photoUrl;
  final String bio;
  final int followers;
  final int following;
  final int pulsesHosted;

  const PublicProfile({
    required this.id,
    required this.username,
    required this.displayName,
    required this.photoUrl,
    required this.bio,
    required this.followers,
    required this.following,
    required this.pulsesHosted,
  });

  PublicProfile copyWith({
    int? followers,
    int? following,
  }) =>
      PublicProfile(
        id: id,
        username: username,
        displayName: displayName,
        photoUrl: photoUrl,
        bio: bio,
        followers: followers ?? this.followers,
        following: following ?? this.following,
        pulsesHosted: pulsesHosted,
      );
}

// Simple pulse model for profile lists
class ProfilePulse {
  final String id;
  final String title;
  final DateTime? time;
  final String location;
  final String imageUrl;
  final String hostUsername;

  const ProfilePulse({
    required this.id,
    required this.title,
    required this.time,
    required this.location,
    required this.imageUrl,
    required this.hostUsername,
  });
}

// Providers (Riverpod)
final _profileProvider =
    FutureProvider.family<PublicProfile, String>((ref, userId) async {
  final profileMap = await ApiService.instance.getUserProfileById(userId);
  final statsMap = await ApiService.instance.getUserStats(userId);
  final username =
      (profileMap?['username'] ?? profileMap?['displayName'] ?? '').toString();
  final displayName =
      (profileMap?['displayName'] ?? profileMap?['name'] ?? username)
          .toString();
  final photoUrl =
      (profileMap?['profileImageUrl'] ?? profileMap?['photoUrl'] ?? '')
          .toString();
  final bio = (profileMap?['bio'] ?? '').toString();
  int followers = 0;
  int following = 0;
  int hosted = 0;
  if (profileMap != null && profileMap['_count'] is Map) {
    final c = profileMap['_count'] as Map;
    followers = (c['followers'] as int?) ?? followers;
    following = (c['following'] as int?) ?? following;
  }
  if (statsMap != null) {
    followers = statsMap['followersCount'] as int? ?? followers;
    following = statsMap['followingCount'] as int? ?? following;
    hosted = statsMap['totalEventsCount'] as int? ?? hosted;
  }
  return PublicProfile(
    id: userId,
    username: username,
    displayName: displayName,
    photoUrl: photoUrl,
    bio: bio,
    followers: followers,
    following: following,
    pulsesHosted: hosted,
  );
});

class _FollowState extends StateNotifier<bool> {
  _FollowState(this.ref, this.userId) : super(false) {
    _init();
  }
  final Ref ref;
  final String userId;

  Future<void> toggle() async {
    final next = !state;
    state = next; // optimistic update
    final followersNotifier =
        ref.read(_followersCountProvider(userId).notifier);
    if (next) {
      followersNotifier.inc();
    } else {
      followersNotifier.dec();
    }
    final ok = next
        ? await ApiService.instance.followUser(userId)
        : await ApiService.instance.unfollowUser(userId);
    if (!ok) {
      state = !next; // revert
      if (next) {
        followersNotifier.dec();
      } else {
        followersNotifier.inc();
      }
    }
  }

  Future<void> _init() async {
    final isFollowing = await ApiService.instance.isFollowingUser(userId);
    state = isFollowing;
  }
}

final _isFollowingProvider =
    StateNotifierProvider.family<_FollowState, bool, String>((ref, userId) {
  return _FollowState(ref, userId);
});

class _PagedPulses extends StateNotifier<List<ProfilePulse>> {
  _PagedPulses(this.loader) : super(const []);
  final Future<List<ProfilePulse>> Function(int page, int size) loader;
  static const int _pageSize = 12;
  int _page = 0;
  bool _isLoading = false;
  bool _hasMore = true;

  bool get hasMore => _hasMore;
  bool get isLoading => _isLoading;

  Future<void> refresh() async {
    _page = 0;
    _hasMore = true;
    state = const [];
    await loadMore();
  }

  Future<void> loadMore() async {
    if (_isLoading || !_hasMore) return;
    _isLoading = true;
    final next = await loader(_page, _pageSize);
    if (next.isEmpty) {
      _hasMore = false;
    } else {
      state = [...state, ...next];
      _page += 1;
    }
    _isLoading = false;
  }
}

final _hostedProvider =
    StateNotifierProvider.family<_PagedPulses, List<ProfilePulse>, String>(
        (ref, userId) {
  return _PagedPulses((page, size) async {
    final list = await ApiService.instance
            .getHostedPulsesForUser(userId, page: page, size: size) ??
        const [];
    return list.map(_mapPulse).toList();
  })
    ..loadMore();
});

final _joinedProvider =
    StateNotifierProvider.family<_PagedPulses, List<ProfilePulse>, String>(
        (ref, userId) {
  return _PagedPulses((page, size) async {
    final list = await ApiService.instance
            .getJoinedPulsesForUser(userId, page: page, size: size) ??
        const [];
    return list.map(_mapPulse).toList();
  })
    ..loadMore();
});

ProfilePulse _mapPulse(Map<String, dynamic> map) {
  DateTime? parsedTime;
  final rawTime = map['eventTime'] ?? map['time'];
  if (rawTime is String) parsedTime = DateTime.tryParse(rawTime);
  String host = '';
  if (map['hostUsername'] != null) host = map['hostUsername'].toString();
  if (host.isEmpty && map['author'] is Map) {
    final a = map['author'] as Map;
    host = (a['username'] ?? a['displayName'] ?? '').toString();
  }
  return ProfilePulse(
    id: (map['id'] ?? '').toString(),
    title: (map['title'] ?? 'Untitled').toString(),
    time: parsedTime,
    location: (map['location'] ?? '').toString(),
    imageUrl: (map['imageUrl'] ?? '').toString(),
    hostUsername: host,
  );
}

// Followers count state that stays in sync with follow/unfollow
class _FollowersCount extends StateNotifier<int> {
  _FollowersCount(this.userId) : super(0) {
    _init();
  }
  final String userId;

  Future<void> _init() async {
    final stats = await ApiService.instance.getUserStats(userId);
    final count = stats != null ? (stats['followersCount'] as int? ?? 0) : 0;
    state = count;
  }

  void inc() => state = state + 1;
  void dec() => state = state > 0 ? state - 1 : 0;
  Future<void> refresh() async => _init();
}

final _followersCountProvider =
    StateNotifierProvider.family<_FollowersCount, int, String>((ref, userId) {
  return _FollowersCount(userId);
});

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key, required this.userId});

  static String routeName = 'ProfileView';
  static String routePath = '/u/:id';

  final String userId;

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  final ScrollController _hostedScroll = ScrollController();
  final ScrollController _joinedScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _hostedScroll
        .addListener(() => _onScrollEnd(_hostedScroll, isHosted: true));
    _joinedScroll
        .addListener(() => _onScrollEnd(_joinedScroll, isHosted: false));
  }

  void _onScrollEnd(ScrollController controller, {required bool isHosted}) {
    final position = controller.position;
    if (position.pixels > position.maxScrollExtent - 300) {
      final notifier = ref.read(
          (isHosted ? _hostedProvider : _joinedProvider)(widget.userId)
              .notifier);
      notifier.loadMore();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _hostedScroll.dispose();
    _joinedScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final profileAsync = ref.watch(_profileProvider(widget.userId));

    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        centerTitle: true,
        title: profileAsync.maybeWhen(
          data: (p) => Text('@${p.username}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          orElse: () => const Text('Profile'),
        ),
        actions: [
          PopupMenuButton<String>(
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'report', child: Text('Report')),
              PopupMenuItem(value: 'block', child: Text('Block')),
            ],
            onSelected: (value) {
              final snack = SnackBar(
                  content: Text(value == 'report' ? 'Reported' : 'Blocked'));
              ScaffoldMessenger.of(context).showSnackBar(snack);
            },
          ),
        ],
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Failed to load profile')),
        data: (profile) {
          return Column(
            children: [
              _ProfileHeader(
                profile: profile,
                onMessage: () => _openMessage(profile),
                onToggleFollow: () => ref
                    .read(_isFollowingProvider(profile.id).notifier)
                    .toggle(),
                isFollowing: ref.watch(_isFollowingProvider(profile.id)),
              ),
              _StatsRow(profile: profile),
              _Tabs(theme: theme, controller: _tabController),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _PulsesList(
                      pulsesProvider: _hostedProvider(profile.id),
                      controller: _hostedScroll,
                      theme: theme,
                      showHost: false,
                    ),
                    _PulsesList(
                      pulsesProvider: _joinedProvider(profile.id),
                      controller: _joinedScroll,
                      theme: theme,
                      showHost: true,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openMessage(PublicProfile profile) {
    final chatId = 'chat_${profile.id}';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EnhancedMessagingPage(
          chatId: chatId,
          recipientUserId: profile.id,
          recipientName: profile.displayName,
          recipientPhotoUrl: profile.photoUrl,
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.onMessage,
    required this.onToggleFollow,
    required this.isFollowing,
  });

  final PublicProfile profile;
  final VoidCallback onMessage;
  final VoidCallback onToggleFollow;
  final bool isFollowing;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final height = MediaQuery.of(context).size.height * 0.30;

    return Container(
      height: height,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundImage: profile.photoUrl.isNotEmpty
                        ? NetworkImage(profile.photoUrl)
                        : null,
                    child: profile.photoUrl.isEmpty
                        ? Icon(Icons.person,
                            color: theme.secondaryText, size: 36)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.displayName,
                          style: theme.titleLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text('@${profile.username}', style: theme.labelMedium),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (profile.bio.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    profile.bio.length > 150
                        ? profile.bio.substring(0, 150) + '…'
                        : profile.bio,
                    style: theme.bodyMedium,
                  ),
                ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onToggleFollow,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isFollowing
                            ? theme.secondaryBackground
                            : theme.primary,
                        foregroundColor:
                            isFollowing ? theme.primaryText : Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text(isFollowing ? 'Unfollow' : 'Follow'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onMessage,
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Message'),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatsRow extends ConsumerWidget {
  const _StatsRow({required this.profile});
  final PublicProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = FlutterFlowTheme.of(context);
    final followers = ref.watch(_followersCountProvider(profile.id));
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _StatItem(label: 'Followers', value: followers.toString()),
          _DotSeparator(theme: theme),
          _StatItem(label: 'Following', value: profile.following.toString()),
          _DotSeparator(theme: theme),
          _StatItem(
              label: 'Pulses Hosted', value: profile.pulsesHosted.toString()),
        ],
      ),
    );
  }
}

class _DotSeparator extends StatelessWidget {
  const _DotSeparator({required this.theme});
  final FlutterFlowTheme theme;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
          color: theme.secondaryText.withOpacity(0.4), shape: BoxShape.circle),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: theme.titleMedium),
        const SizedBox(height: 2),
        Text(label, style: theme.labelSmall),
      ],
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.theme, required this.controller});
  final FlutterFlowTheme theme;
  final TabController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: controller,
        labelColor: Colors.white,
        unselectedLabelColor: theme.secondaryText,
        indicator: BoxDecoration(
          color: theme.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        tabs: const [
          Tab(text: 'Pulses'),
          Tab(text: 'Joined'),
        ],
      ),
    );
  }
}

class _PulsesList extends ConsumerWidget {
  const _PulsesList({
    required this.pulsesProvider,
    required this.controller,
    required this.theme,
    required this.showHost,
  });

  final StateNotifierProvider<_PagedPulses, List<ProfilePulse>> pulsesProvider;
  final ScrollController controller;
  final FlutterFlowTheme theme;
  final bool showHost;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pulses = ref.watch(pulsesProvider);
    final notifier = ref.read(pulsesProvider.notifier);

    if (pulses.isEmpty && notifier.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final isWide = MediaQuery.of(context).size.width >= 700;
    final grid = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: isWide ? 2 : 1,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: isWide ? 1.9 : 2.8,
    );

    return RefreshIndicator(
      onRefresh: () async => notifier.refresh(),
      color: theme.primary,
      backgroundColor: theme.secondaryBackground,
      child: GridView.builder(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        gridDelegate: grid,
        itemCount: pulses.length + (notifier.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= pulses.length) {
            return const Center(
                child: SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2)));
          }
          final p = pulses[index];
          return ProfilePulseCard(
            pulse: p,
            showHost: showHost,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PulseDetailPage(pulseId: p.id, initialPulse: {
                    'id': p.id,
                    'title': p.title,
                    'imageUrl': p.imageUrl,
                    'location': p.location,
                    'hostUsername': p.hostUsername,
                    'eventTime': p.time?.toIso8601String(),
                  }),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ProfilePulseCard extends StatelessWidget {
  const ProfilePulseCard(
      {super.key,
      required this.pulse,
      required this.showHost,
      required this.onTap});
  final ProfilePulse pulse;
  final bool showHost;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final whenStr = () {
      final t = pulse.time;
      if (t == null) return 'TBD';
      final tod = TimeOfDay.fromDateTime(t).format(context);
      return tod;
    }();

    bool isValidNetworkUrl(String url) {
      if (url.isEmpty) return false;
      final uri = Uri.tryParse(url);
      if (uri == null) return false;
      return (uri.scheme == 'http' || uri.scheme == 'https') &&
          (uri.host.isNotEmpty);
    }

    return Material(
      color: theme.secondaryBackground,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1.2,
              child: isValidNetworkUrl(pulse.imageUrl)
                  ? Image.network(pulse.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Container(color: theme.alternate))
                  : Container(color: theme.alternate),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(pulse.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.titleSmall),
                    const SizedBox(height: 6),
                    Row(children: [
                      const Icon(Icons.schedule, size: 14),
                      const SizedBox(width: 4),
                      Text(whenStr, style: theme.labelSmall),
                    ]),
                    const SizedBox(height: 6),
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_on_outlined, size: 14),
                          const SizedBox(width: 4),
                          Expanded(
                              child: Text(pulse.location,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.labelSmall)),
                        ]),
                    if (showHost) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        const Icon(Icons.person_outline, size: 14),
                        const SizedBox(width: 4),
                        Expanded(
                            child: Text(pulse.hostUsername,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.labelSmall)),
                      ]),
                    ],
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
