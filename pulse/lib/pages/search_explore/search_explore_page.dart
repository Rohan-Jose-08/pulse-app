import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import 'search_explore_providers.dart';
import '../../flutter_flow/nav/nav.dart';
import '../pulse_detail/pulse_detail_page.dart';
import '../../components/navbar_widget.dart';
import '../search/search_widget.dart';
import '../profile/ProfilePage.dart';
import '../../backend/api_service.dart';
import '../../auth/firebase_auth/auth_util.dart';
import 'recommendations_tab.dart';

class SearchExplorePage extends ConsumerStatefulWidget {
  const SearchExplorePage({super.key});

  static String routeName = 'ExploreSearch';
  static String routePath = '/explore-search';

  @override
  ConsumerState<SearchExplorePage> createState() => _SearchExplorePageState();
}

class _SearchExplorePageState extends ConsumerState<SearchExplorePage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _tabController = TabController(length: 2, vsync: this);
  }

  void _onScroll() {
    final notifier = ref.read(explorePaginationProvider.notifier);
    final position = _scrollController.position;
    if (position.pixels > position.maxScrollExtent - 400) {
      notifier.loadMore();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final query = ref.watch(searchQueryProvider);
    final hasQuery = query.trim().isNotEmpty;
    final suggestionsUsers = ref.watch(userSuggestionsProvider);
    final suggestionsPulses = ref.watch(pulseSuggestionsProvider);
    final userResults = ref.watch(userResultsProvider);
    final pulseResults = ref.watch(pulseResultsProvider);
    final exploreItems = ref.watch(explorePaginationProvider);
    final pagination = ref.read(explorePaginationProvider.notifier);

    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        elevation: 0,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        centerTitle: true,
        bottom: hasQuery
            ? null
            : TabBar(
                controller: _tabController,
                labelColor: theme.primary,
                unselectedLabelColor: theme.secondaryText,
                indicatorColor: theme.primary,
                indicatorWeight: 3,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.auto_awesome),
                    text: 'For You',
                  ),
                  Tab(
                    icon: Icon(Icons.explore),
                    text: 'Explore',
                  ),
                ],
              ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: hasQuery
            ? userResults.when(
                data: (users) => pulseResults.when(
                  data: (pulses) => _SearchResultsList(
                    userResults: users,
                    pulseResults: pulses,
                  ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) =>
                      const Center(child: Text('Error loading results')),
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) =>
                    const Center(child: Text('Error loading results')),
              )
            : TabBarView(
                controller: _tabController,
                children: [
                  const RecommendationsTab(),
                  RefreshIndicator(
                    onRefresh: () async => pagination.refresh(),
                    color: theme.primary,
                    backgroundColor: theme.secondaryBackground,
                    child: CustomScrollView(
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics()),
                      slivers: [
                        SliverToBoxAdapter(
                          child: suggestionsUsers.when(
                            data: (users) => suggestionsPulses.when(
                              data: (pulses) => _LiveSuggestions(
                                users: users,
                                pulses: pulses,
                                onSelect: (text) {
                                  _controller.text = text;
                                  ref.read(searchQueryProvider.notifier).state =
                                      text;
                                  _focusNode.unfocus();
                                },
                              ),
                              loading: () => const SizedBox(height: 0),
                              error: (_, __) => const SizedBox(height: 0),
                            ),
                            loading: () => const SizedBox(height: 0),
                            error: (_, __) => const SizedBox(height: 0),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          sliver: SliverMasonryGrid.count(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childCount: exploreItems.length,
                            itemBuilder: (context, index) {
                              final pulse = exploreItems[index];
                              return _PulseGridCard(pulse: pulse);
                            },
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: _LoadMoreFooter(),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 100)),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      bottomNavigationBar: const NavbarWidget(),
    );
  }

  Widget _buildSearchBar(BuildContext context, FlutterFlowTheme theme) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            offset: const Offset(0, 2),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.search, size: 22),
            onPressed: () {
              context.pushNamed(SearchWidget.routeName);
            },
            tooltip: 'Search',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              decoration: const InputDecoration(
                hintText: 'Search users or pulses…',
                border: InputBorder.none,
              ),
              onChanged: (value) {
                ref.read(debouncedQueryProvider.notifier).set(value);
                ref.read(searchQueryProvider.notifier).state = value;
              },
              textInputAction: TextInputAction.search,
            ),
          ),
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                _controller.clear();
                ref.read(debouncedQueryProvider.notifier).set('');
                ref.read(searchQueryProvider.notifier).state = '';
              },
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _LiveSuggestions extends StatelessWidget {
  const _LiveSuggestions({
    required this.users,
    required this.pulses,
    required this.onSelect,
  });

  final List<ExploreUser> users;
  final List<ExplorePulse> pulses;
  final void Function(String text) onSelect;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty && pulses.isEmpty) return const SizedBox.shrink();
    final theme = FlutterFlowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: theme.secondaryBackground,
        elevation: 1,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (users.isNotEmpty)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text('Users', style: theme.labelMedium),
                ),
              ...users.map((u) => _SuggestionTile(
                    leading: CircleAvatar(
                        backgroundImage: NetworkImage(u.avatarUrl)),
                    title: u.username,
                    subtitle: u.fullName,
                    onTap: () => onSelect(u.username),
                  )),
              if (pulses.isNotEmpty)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text('Pulses', style: theme.labelMedium),
                ),
              ...pulses.map((p) => _SuggestionTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(p.imageUrl,
                          width: 36, height: 36, fit: BoxFit.cover),
                    ),
                    title: p.title,
                    subtitle: '${p.hostUsername} • ${p.location}',
                    onTap: () => onSelect(p.title),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(subtitle, style: theme.labelSmall),
                ],
              ),
            ),
            const Icon(Icons.north_west, size: 16),
          ],
        ),
      ),
    );
  }
}

class _PulseGridCard extends StatelessWidget {
  const _PulseGridCard({required this.pulse});

  final ExplorePulse pulse;

  String _getPulseStatus() {
    try {
      final now = DateTime.now();

      if (pulse.activeUntil != null && now.isAfter(pulse.activeUntil!)) {
        return 'ENDED';
      }

      if (pulse.activeFrom != null) {
        if (now.isBefore(pulse.activeFrom!)) {
          return 'SOON';
        }
        if (pulse.activeUntil != null &&
            now.isAfter(pulse.activeFrom!) &&
            now.isBefore(pulse.activeUntil!)) {
          return 'LIVE';
        } else if (pulse.activeUntil == null &&
            now.isAfter(pulse.activeFrom!)) {
          return 'LIVE';
        }
      }
    } catch (_) {
      // Error parsing dates, return LIVE as default
    }
    return 'LIVE';
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final pulseStatus = _getPulseStatus();
    final isExpired = pulseStatus == 'ENDED';

    bool isValidNetworkUrl(String url) {
      if (url.isEmpty) return false;
      final uri = Uri.tryParse(url);
      if (uri == null) return false;
      return (uri.scheme == 'http' || uri.scheme == 'https') &&
          (uri.host.isNotEmpty);
    }

    return Opacity(
      opacity: isExpired ? 0.5 : 1.0,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ColorFiltered(
                colorFilter: isExpired
                    ? ColorFilter.mode(
                        Colors.grey,
                        BlendMode.saturation,
                      )
                    : ColorFilter.mode(
                        Colors.transparent,
                        BlendMode.multiply,
                      ),
                child: isValidNetworkUrl(pulse.imageUrl)
                    ? Image.network(
                        pulse.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Container(color: theme.alternate),
                      )
                    : Container(
                        color: isExpired ? Colors.grey : theme.alternate),
              ),
            ),
            // Expired badge
            if (isExpired)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade700,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.event_busy_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'ENDED',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      pulse.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pulse.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    context.pushNamed(
                      PulseDetailPage.routeName,
                      pathParameters: {'id': pulse.id},
                      extra: {
                        'pulse': {
                          'id': pulse.id,
                          'title': pulse.title,
                          'imageUrl': pulse.imageUrl,
                          'location': pulse.location,
                          'hostUsername': pulse.hostUsername,
                          'eventTime': pulse.time?.toIso8601String(),
                          'latitude': pulse.latitude,
                          'longitude': pulse.longitude,
                        }
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResultsList extends StatelessWidget {
  const _SearchResultsList({
    required this.userResults,
    required this.pulseResults,
  });

  final List<ExploreUser> userResults;
  final List<ExplorePulse> pulseResults;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return ListView(
      physics: const BouncingScrollPhysics(),
      children: [
        const SizedBox(height: 8),
        if (userResults.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Users', style: theme.labelLarge),
          ),
        ...userResults.map((u) => ListTile(
              leading: CircleAvatar(backgroundImage: NetworkImage(u.avatarUrl)),
              title: Text(u.fullName),
              subtitle: Text('@${u.username}'),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProfilePage(userId: u.id),
                  ),
                );
              },
            )),
        if (pulseResults.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Pulses', style: theme.labelLarge),
          ),
        ...pulseResults.map((p) => Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  context.pushNamed(
                    PulseDetailPage.routeName,
                    pathParameters: {'id': p.id},
                    extra: {
                      'pulse': {
                        'id': p.id,
                        'title': p.title,
                        'imageUrl': p.imageUrl,
                        'location': p.location,
                        'hostUsername': p.hostUsername,
                        'eventTime': p.time?.toIso8601String(),
                        'latitude': p.latitude,
                        'longitude': p.longitude,
                      }
                    },
                  );
                },
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      height: 72,
                      child: Image.network(
                        p.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Container(color: theme.alternate),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Text('${p.hostUsername} • ${p.location}',
                              style: theme.labelSmall),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.schedule, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                p.time != null
                                    ? TimeOfDay.fromDateTime(p.time!)
                                        .format(context)
                                    : 'TBD',
                                style: theme.labelSmall,
                              ),
                              const Spacer(),
                              Builder(builder: (context) {
                                final bool isOwner =
                                    (p.authorId.toString().isNotEmpty &&
                                        p.authorId == currentUserUid);
                                return TextButton(
                                  onPressed: isOwner
                                      ? null
                                      : () async {
                                          final result = await ApiService
                                              .instance
                                              .joinPulse(p.id);
                                          if (result != null &&
                                              result['success'] == true) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'Successfully joined pulse'),
                                              ),
                                            );
                                          } else {
                                            final errorMessage = (result !=
                                                        null &&
                                                    result['error'] is String)
                                                ? result['error'] as String
                                                : 'Failed to join pulse';
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(errorMessage),
                                              ),
                                            );
                                          }
                                        },
                                  child: Text(isOwner ? 'Yours' : 'Join'),
                                );
                              }),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),
            )),
        const SizedBox(height: 100),
      ],
    );
  }
}

class _LoadMoreFooter extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(explorePaginationProvider.notifier);
    final hasMore = notifier.hasMore;
    final isLoading = notifier.isLoading;

    if (!hasMore && !isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('You\'re all caught up')),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                onPressed: () => notifier.loadMore(),
                child: const Text('Load more'),
              ),
      ),
    );
  }
}
