import 'package:flutter/material.dart';
import 'dart:async';
import '../flutter_flow/flutter_flow_theme.dart';
import '../utils/haptic_utils.dart';

/// Modern search bar with smooth animations and suggestions
class ModernSearchBar extends StatefulWidget {
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final TextEditingController? controller;
  final bool autofocus;
  final Widget? leading;
  final List<Widget>? trailing;

  const ModernSearchBar({
    Key? key,
    this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.controller,
    this.autofocus = false,
    this.leading,
    this.trailing,
  }) : super(key: key);

  @override
  State<ModernSearchBar> createState() => _ModernSearchBarState();
}

class _ModernSearchBarState extends State<ModernSearchBar>
    with SingleTickerProviderStateMixin {
  late TextEditingController _controller;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _isFocused
                ? theme.primary.withOpacity(0.5)
                : theme.alternate.withOpacity(0.3),
            width: _isFocused ? 2 : 1,
          ),
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: theme.primary.withOpacity(0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            widget.leading ??
                Icon(
                  Icons.search,
                  color: _isFocused ? theme.primary : theme.secondaryText,
                  size: 22,
                ),
            const SizedBox(width: 12),
            Expanded(
              child: Focus(
                onFocusChange: (focused) {
                  setState(() => _isFocused = focused);
                  if (focused) {
                    _animationController.forward();
                  } else {
                    _animationController.reverse();
                  }
                },
                child: TextField(
                  controller: _controller,
                  autofocus: widget.autofocus,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  onTap: widget.onTap,
                  style: theme.bodyMedium,
                  decoration: InputDecoration(
                    hintText: widget.hintText ?? 'Search...',
                    hintStyle: theme.bodyMedium.copyWith(
                      color: theme.secondaryText,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
            if (_controller.text.isNotEmpty)
              IconButton(
                icon: Icon(
                  Icons.clear,
                  size: 20,
                  color: theme.secondaryText,
                ),
                onPressed: () {
                  _controller.clear();
                  widget.onChanged?.call('');
                },
              ),
            if (widget.trailing != null) ...widget.trailing!,
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

/// Search page with suggestions and recent searches
class ModernSearchPage extends StatefulWidget {
  final String title;
  final Future<List<SearchResult>> Function(String query) onSearch;
  final List<String>? recentSearches;
  final ValueChanged<SearchResult>? onResultTap;
  final Widget Function(SearchResult)? resultBuilder;

  const ModernSearchPage({
    Key? key,
    this.title = 'Search',
    required this.onSearch,
    this.recentSearches,
    this.onResultTap,
    this.resultBuilder,
  }) : super(key: key);

  @override
  State<ModernSearchPage> createState() => _ModernSearchPageState();
}

class _ModernSearchPageState extends State<ModernSearchPage> {
  final TextEditingController _controller = TextEditingController();
  List<SearchResult> _results = [];
  bool _isLoading = false;
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _query = query;
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);
    await HapticUtils.light();

    try {
      final results = await widget.onSearch(query);
      if (mounted) {
        setState(() {
          _results = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _results = [];
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.secondaryBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: ModernSearchBar(
          controller: _controller,
          autofocus: true,
          hintText: 'Search ${widget.title.toLowerCase()}...',
          onChanged: _onSearchChanged,
          onSubmitted: _performSearch,
        ),
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(FlutterFlowTheme theme) {
    if (_query.isEmpty) {
      return _buildRecentSearches(theme);
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_results.isEmpty) {
      return _buildEmptyState(theme);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final result = _results[index];
        return widget.resultBuilder?.call(result) ??
            _buildDefaultResultItem(result, theme);
      },
    );
  }

  Widget _buildRecentSearches(FlutterFlowTheme theme) {
    if (widget.recentSearches == null || widget.recentSearches!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: theme.secondaryText.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Start typing to search',
              style: theme.bodyLarge.copyWith(
                color: theme.secondaryText,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Recent Searches',
            style: theme.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...widget.recentSearches!.map((search) {
          return ListTile(
            leading: const Icon(Icons.history),
            title: Text(search),
            trailing: IconButton(
              icon: const Icon(Icons.north_west),
              onPressed: () {
                _controller.text = search;
                _performSearch(search);
              },
            ),
            onTap: () {
              _controller.text = search;
              _performSearch(search);
            },
          );
        }),
      ],
    );
  }

  Widget _buildEmptyState(FlutterFlowTheme theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: theme.secondaryText.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No results found',
            style: theme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different search term',
            style: theme.bodyMedium.copyWith(
              color: theme.secondaryText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultResultItem(SearchResult result, FlutterFlowTheme theme) {
    return ListTile(
      leading: result.icon != null
          ? Icon(result.icon)
          : (result.imageUrl != null
              ? CircleAvatar(
                  backgroundImage: NetworkImage(result.imageUrl!),
                )
              : null),
      title: Text(result.title),
      subtitle: result.subtitle != null ? Text(result.subtitle!) : null,
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () async {
        await HapticUtils.light();
        widget.onResultTap?.call(result);
      },
    );
  }
}

class SearchResult {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? imageUrl;
  final dynamic data;

  const SearchResult({
    required this.title,
    this.subtitle,
    this.icon,
    this.imageUrl,
    this.data,
  });
}

/// Search filter chips
class SearchFilters extends StatelessWidget {
  final List<FilterChip> filters;
  final Set<String> selectedFilters;
  final ValueChanged<Set<String>>? onChanged;

  const SearchFilters({
    Key? key,
    required this.filters,
    required this.selectedFilters,
    this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = selectedFilters.contains(filter.id);

          return FilterChip(
            label: Text(filter.label),
            selected: isSelected,
            onSelected: (selected) async {
              await HapticUtils.light();
              final newFilters = Set<String>.from(selectedFilters);
              if (selected) {
                newFilters.add(filter.id);
              } else {
                newFilters.remove(filter.id);
              }
              onChanged?.call(newFilters);
            },
            backgroundColor: theme.secondaryBackground,
            selectedColor: theme.primary.withOpacity(0.2),
            checkmarkColor: theme.primary,
            labelStyle: TextStyle(
              color: isSelected ? theme.primary : theme.primaryText,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: isSelected ? theme.primary : theme.alternate,
              ),
            ),
          );
        },
      ),
    );
  }
}

class FilterChip {
  final String id;
  final String label;

  const FilterChip({
    required this.id,
    required this.label,
  });
}
