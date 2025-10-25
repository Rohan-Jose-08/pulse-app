import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import '../../flutter_flow/flutter_flow_icon_button.dart';
import '../../backend/api_service.dart';

/// Highlight viewer page - displays video highlight like Instagram stories
class HighlightViewerPage extends StatefulWidget {
  const HighlightViewerPage({
    super.key,
    required this.highlightId,
  });

  final String highlightId;

  static String routeName = 'HighlightViewer';
  static String routePath = '/highlight/:highlightId';

  @override
  State<HighlightViewerPage> createState() => _HighlightViewerPageState();
}

class _HighlightViewerPageState extends State<HighlightViewerPage> {
  Map<String, dynamic>? _highlight;
  bool _loading = true;
  String? _error;
  VideoPlayerController? _videoController;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _loadHighlight();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _loadHighlight() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      final highlight =
          await ApiService.instance.getHighlight(widget.highlightId);

      if (mounted) {
        if (highlight != null) {
          setState(() {
            _highlight = highlight;
            _loading = false;
          });

          // Initialize video player
          final videoUrl = highlight['videoUrl']?.toString();
          if (videoUrl != null && videoUrl.isNotEmpty) {
            _initializeVideo(videoUrl);
          }
        } else {
          setState(() {
            _error = 'Highlight not found';
            _loading = false;
          });
        }
      }
    } catch (e) {
      print('Error loading highlight: $e');
      if (mounted) {
        setState(() {
          _error = 'Failed to load highlight';
          _loading = false;
        });
      }
    }
  }

  Future<void> _initializeVideo(String videoUrl) async {
    try {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      await _videoController!.initialize();

      if (mounted) {
        setState(() {
          _isPlaying = true;
        });
        _videoController!.play();

        // Listen for video completion
        _videoController!.addListener(() {
          if (_videoController!.value.position >=
              _videoController!.value.duration) {
            // Video finished, close viewer
            if (mounted) {
              Navigator.of(context).pop();
            }
          }
        });
      }
    } catch (e) {
      print('Error initializing video: $e');
      if (mounted) {
        setState(() {
          _error = 'Failed to load video';
        });
      }
    }
  }

  void _togglePlayPause() {
    if (_videoController == null) return;

    setState(() {
      if (_isPlaying) {
        _videoController!.pause();
        _isPlaying = false;
      } else {
        _videoController!.play();
        _isPlaying = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    // Set status bar to light for dark background
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: theme.error),
                      const SizedBox(height: 16),
                      Text(_error!, style: theme.bodyLarge),
                      const SizedBox(height: 24),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Go Back'),
                      ),
                    ],
                  ),
                )
              : GestureDetector(
                  onTap: _togglePlayPause,
                  child: Stack(
                    children: [
                      // Video player
                      if (_videoController != null &&
                          _videoController!.value.isInitialized)
                        Center(
                          child: AspectRatio(
                            aspectRatio: _videoController!.value.aspectRatio,
                            child: VideoPlayer(_videoController!),
                          ),
                        ),

                      // Loading indicator while video initializes
                      if (_videoController == null ||
                          !_videoController!.value.isInitialized)
                        const Center(child: CircularProgressIndicator()),

                      // Play/pause icon overlay (shows briefly when toggled)
                      if (!_isPlaying)
                        Center(
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow,
                              size: 48,
                              color: Colors.white,
                            ),
                          ),
                        ),

                      // Top bar with user info and close button
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: SafeArea(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withOpacity(0.5),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                            child: Row(
                              children: [
                                // User avatar
                                if (_highlight?['user']?['profileImageUrl'] !=
                                    null)
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundImage: NetworkImage(
                                      _highlight!['user']['profileImageUrl'],
                                    ),
                                  )
                                else
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: theme.primary,
                                    child: const Icon(Icons.person,
                                        size: 18, color: Colors.white),
                                  ),
                                const SizedBox(width: 12),
                                // User name
                                Expanded(
                                  child: Text(
                                    _highlight?['user']?['displayName'] ??
                                        'User',
                                    style: theme.titleSmall.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                // Close button
                                FlutterFlowIconButton(
                                  icon: const Icon(Icons.close,
                                      color: Colors.white),
                                  onPressed: () => Navigator.of(context).pop(),
                                  buttonSize: 40,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Bottom info - caption and pulse title
                      if (_highlight != null)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: SafeArea(
                            child: Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    Colors.black.withOpacity(0.7),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Pulse title
                                  if (_highlight!['pulse']?['title'] != null)
                                    Text(
                                      _highlight!['pulse']['title'],
                                      style: theme.titleMedium.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  // Caption
                                  if (_highlight!['caption'] != null &&
                                      _highlight!['caption']
                                          .toString()
                                          .isNotEmpty)
                                    Text(
                                      _highlight!['caption'],
                                      style: theme.bodyMedium.copyWith(
                                        color: Colors.white,
                                      ),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // Progress bar at bottom
                      if (_videoController != null &&
                          _videoController!.value.isInitialized)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: VideoProgressIndicator(
                            _videoController!,
                            allowScrubbing: false,
                            colors: VideoProgressColors(
                              playedColor: theme.primary,
                              backgroundColor: Colors.white.withOpacity(0.3),
                            ),
                            padding: const EdgeInsets.all(0),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
