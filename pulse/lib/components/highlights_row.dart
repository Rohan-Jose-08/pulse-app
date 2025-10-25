import 'package:flutter/material.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import '../../backend/api_service.dart';

/// A horizontal scrollable list of highlights (like Instagram stories/highlights)
/// Shows circular thumbnails with titles below
class HighlightsRow extends StatefulWidget {
  const HighlightsRow({
    super.key,
    required this.userId,
    this.isOwnProfile = false,
    this.onHighlightTap,
    this.onCreateTap,
  });

  final String userId;
  final bool isOwnProfile;
  final Function(Map<String, dynamic> highlight)? onHighlightTap;
  final VoidCallback? onCreateTap;

  @override
  State<HighlightsRow> createState() => _HighlightsRowState();
}

class _HighlightsRowState extends State<HighlightsRow> {
  List<Map<String, dynamic>> _highlights = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHighlights();
  }

  Future<void> _loadHighlights() async {
    try {
      setState(() => _loading = true);
      final highlights =
          await ApiService.instance.getUserHighlights(widget.userId);
      if (mounted) {
        setState(() {
          _highlights = highlights ?? [];
          _loading = false;
        });
      }
    } catch (e) {
      print('Error loading highlights: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    // Don't show the row if there are no highlights and it's not the user's own profile
    if (!_loading && _highlights.isEmpty && !widget.isOwnProfile) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 130,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _highlights.length + (widget.isOwnProfile ? 1 : 0),
              itemBuilder: (context, index) {
                // Show "Create New" button as first item for own profile
                if (widget.isOwnProfile && index == 0) {
                  return _CreateHighlightButton(
                    onTap: widget.onCreateTap,
                    theme: theme,
                  );
                }

                final highlightIndex = widget.isOwnProfile ? index - 1 : index;
                final highlight = _highlights[highlightIndex];

                return _HighlightCircle(
                  highlight: highlight,
                  onTap: () => widget.onHighlightTap?.call(highlight),
                  theme: theme,
                );
              },
            ),
    );
  }
}

class _CreateHighlightButton extends StatelessWidget {
  const _CreateHighlightButton({
    required this.onTap,
    required this.theme,
  });

  final VoidCallback? onTap;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        children: [
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.primaryText.withOpacity(0.2),
                  width: 2,
                ),
                color: theme.secondaryBackground,
              ),
              child: Icon(
                Icons.add,
                size: 32,
                color: theme.primaryText,
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 68,
            child: Text(
              'New',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.labelSmall.copyWith(
                fontSize: 12,
                color: theme.secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HighlightCircle extends StatelessWidget {
  const _HighlightCircle({
    required this.highlight,
    required this.onTap,
    required this.theme,
  });

  final Map<String, dynamic> highlight;
  final VoidCallback onTap;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) {
    // For video highlights: show thumbnail and pulse title
    final thumbnailUrl = highlight['thumbnailUrl']?.toString();
    final pulseTitle = highlight['pulse']?['title']?.toString() ??
        highlight['caption']?.toString() ??
        'Highlight';
    final duration = highlight['duration'] as int? ?? 0;

    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.primary,
                  width: 2.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.alternate,
                        image: thumbnailUrl != null && thumbnailUrl.isNotEmpty
                            ? DecorationImage(
                                image: NetworkImage(thumbnailUrl),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: thumbnailUrl == null || thumbnailUrl.isEmpty
                          ? Icon(
                              Icons.videocam,
                              size: 28,
                              color: theme.secondaryText,
                            )
                          : null,
                    ),
                    // Play icon overlay
                    if (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
                      Center(
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 68,
            child: Text(
              pulseTitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.labelSmall.copyWith(
                fontSize: 11,
                color: theme.primaryText,
                height: 1.2,
              ),
            ),
          ),
          if (duration > 0) ...[
            const SizedBox(height: 2),
            Text(
              '${duration}s',
              style: theme.labelSmall.copyWith(
                fontSize: 10,
                color: theme.secondaryText,
                height: 1.0,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
