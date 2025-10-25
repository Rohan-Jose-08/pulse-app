import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import '../../flutter_flow/flutter_flow_widgets.dart';
import '../../backend/api_service.dart';

/// Page for viewing and managing user's video highlights
class ManageHighlightPage extends StatefulWidget {
  const ManageHighlightPage({
    super.key,
    this.userId,
  });

  final String? userId;

  static String routeName = 'ManageHighlight';
  static String routePath = '/manage-highlight';

  @override
  State<ManageHighlightPage> createState() => _ManageHighlightPageState();
}

class _ManageHighlightPageState extends State<ManageHighlightPage> {
  List<Map<String, dynamic>> _highlights = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHighlights();
  }

  Future<void> _loadHighlights() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      final userId = widget.userId ?? await _getCurrentUserId();
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final highlights = await ApiService.instance.getUserHighlights(userId);

      if (mounted) {
        setState(() {
          _highlights = highlights ?? [];
          _loading = false;
        });
      }
    } catch (e) {
      print('Error loading highlights: $e');
      if (mounted) {
        setState(() {
          _error = 'Failed to load highlights';
          _loading = false;
        });
      }
    }
  }

  Future<String?> _getCurrentUserId() async {
    final profile = await ApiService.instance.getUserProfile();
    return profile?['id'] as String?;
  }

  Future<void> _deleteHighlight(String highlightId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Highlight'),
        content: Text('Are you sure you want to delete this highlight?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: FlutterFlowTheme.of(context).error,
            ),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ApiService.instance.deleteHighlight(highlightId);
      if (success) {
        _showSnackBar('Highlight deleted');
        _loadHighlights(); // Refresh list
      } else {
        _showSnackBar('Failed to delete highlight');
      }
    }
  }

  Future<void> _togglePrivacy(Map<String, dynamic> highlight) async {
    final highlightId = highlight['id'] as String;
    final isPublic = highlight['isPublic'] as bool? ?? true;

    final result = await ApiService.instance.updateHighlight(
      highlightId: highlightId,
      isPublic: !isPublic,
    );

    if (result != null) {
      _showSnackBar(
          isPublic ? 'Highlight is now private' : 'Highlight is now public');
      _loadHighlights(); // Refresh list
    } else {
      _showSnackBar('Failed to update privacy');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _formatDuration(int? seconds) {
    if (seconds == null) return '0:00';
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('MMM d, y').format(date);
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('My Highlights'),
        backgroundColor: FlutterFlowTheme.of(context).primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: Colors.grey)),
                      SizedBox(height: 16),
                      FFButtonWidget(
                        onPressed: _loadHighlights,
                        text: 'Retry',
                        options: FFButtonOptions(
                          width: 120,
                          height: 40,
                          color: FlutterFlowTheme.of(context).primary,
                          textStyle: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                )
              : _highlights.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.video_library_outlined,
                              size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No highlights yet',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Record videos during pulses to create highlights',
                            style: TextStyle(color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadHighlights,
                      child: ListView.builder(
                        padding: EdgeInsets.all(16),
                        itemCount: _highlights.length,
                        itemBuilder: (context, index) {
                          final highlight = _highlights[index];
                          final thumbnailUrl =
                              highlight['thumbnailUrl'] as String?;
                          final caption = highlight['caption'] as String?;
                          final duration = highlight['duration'] as int?;
                          final isPublic =
                              highlight['isPublic'] as bool? ?? true;
                          final viewCount = highlight['viewCount'] as int? ?? 0;
                          final createdAt = highlight['createdAt'] as String?;

                          return Card(
                            margin: EdgeInsets.only(bottom: 16),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Thumbnail
                                AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      thumbnailUrl != null
                                          ? Image.network(
                                              thumbnailUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (context, error, stack) =>
                                                      Container(
                                                color: Colors.grey[300],
                                                child: Icon(Icons.videocam,
                                                    size: 48,
                                                    color: Colors.grey),
                                              ),
                                            )
                                          : Container(
                                              color: Colors.grey[300],
                                              child: Icon(Icons.videocam,
                                                  size: 48, color: Colors.grey),
                                            ),
                                      // Duration badge
                                      Positioned(
                                        bottom: 8,
                                        right: 8,
                                        child: Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                Colors.black.withOpacity(0.7),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            _formatDuration(duration),
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Play icon
                                      Center(
                                        child: Icon(
                                          Icons.play_circle_outline,
                                          size: 64,
                                          color: Colors.white.withOpacity(0.9),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Info
                                Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (caption != null && caption.isNotEmpty)
                                        Text(
                                          caption,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Icon(
                                            isPublic
                                                ? Icons.public
                                                : Icons.lock,
                                            size: 16,
                                            color: Colors.grey,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            isPublic ? 'Public' : 'Private',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                          SizedBox(width: 16),
                                          Icon(
                                            Icons.visibility_outlined,
                                            size: 16,
                                            color: Colors.grey,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            '$viewCount views',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                          Spacer(),
                                          Text(
                                            _formatDate(createdAt),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 12),
                                      // Actions
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () =>
                                                  _togglePrivacy(highlight),
                                              icon: Icon(
                                                isPublic
                                                    ? Icons.lock
                                                    : Icons.public,
                                                size: 18,
                                              ),
                                              label: Text(
                                                isPublic
                                                    ? 'Make Private'
                                                    : 'Make Public',
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor:
                                                    FlutterFlowTheme.of(context)
                                                        .primary,
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          IconButton(
                                            onPressed: () => _deleteHighlight(
                                                highlight['id'] as String),
                                            icon: Icon(Icons.delete_outline),
                                            color: FlutterFlowTheme.of(context)
                                                .error,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
