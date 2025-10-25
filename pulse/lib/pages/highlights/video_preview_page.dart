import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/backend/api_service.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';

class VideoPreviewPage extends StatefulWidget {
  const VideoPreviewPage({
    super.key,
    required this.videoPath,
    required this.pulseId,
    required this.pulseName,
    required this.duration,
  });

  final String videoPath;
  final String pulseId;
  final String pulseName;
  final int duration;

  @override
  State<VideoPreviewPage> createState() => _VideoPreviewPageState();
}

class _VideoPreviewPageState extends State<VideoPreviewPage> {
  late VideoPlayerController _videoController;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  final TextEditingController _captionController = TextEditingController();
  bool _isPublic = true;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  @override
  void dispose() {
    _videoController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _initializeVideo() async {
    _videoController = VideoPlayerController.file(File(widget.videoPath));
    await _videoController.initialize();
    setState(() {
      _isInitialized = true;
    });

    // Auto-play
    _videoController.play();
    _videoController.setLooping(true);
    setState(() {
      _isPlaying = true;
    });

    _videoController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _togglePlayPause() {
    if (_videoController.value.isPlaying) {
      _videoController.pause();
      setState(() {
        _isPlaying = false;
      });
    } else {
      _videoController.play();
      setState(() {
        _isPlaying = true;
      });
    }
  }

  Future<String?> _generateThumbnail() async {
    try {
      final thumbnailPath = await VideoThumbnail.thumbnailFile(
        video: widget.videoPath,
        thumbnailPath: (await getTemporaryDirectory()).path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 720,
        quality: 85,
      );
      return thumbnailPath;
    } catch (e) {
      print('Error generating thumbnail: $e');
      return null;
    }
  }

  Future<String?> _uploadToFirebase(String filePath, String folder) async {
    try {
      final fileName = path.basename(filePath);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('highlights/$folder/$timestamp-$fileName');

      final uploadTask = storageRef.putFile(File(filePath));

      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        setState(() {
          _uploadProgress = progress;
        });
      });

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      print('Error uploading to Firebase: $e');
      return null;
    }
  }

  Future<void> _saveHighlight() async {
    if (_isUploading) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    try {
      // 1. Upload video to Firebase Storage
      final videoUrl = await _uploadToFirebase(widget.videoPath, 'videos');
      if (videoUrl == null) {
        throw Exception('Failed to upload video');
      }

      // 2. Generate and upload thumbnail
      String? thumbnailUrl;
      final thumbnailPath = await _generateThumbnail();
      if (thumbnailPath != null) {
        thumbnailUrl = await _uploadToFirebase(thumbnailPath, 'thumbnails');
      }

      // 3. Create highlight via API
      final apiService = ApiService.instance;
      final result = await apiService.createHighlight(
        videoUrl: videoUrl,
        duration: widget.duration,
        pulseId: widget.pulseId,
        thumbnailUrl: thumbnailUrl,
        caption: _captionController.text.trim().isEmpty
            ? null
            : _captionController.text.trim(),
        isPublic: _isPublic,
      );

      if (result != null) {
        // Success - show message and return
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Highlight created successfully!'),
              backgroundColor: FlutterFlowTheme.of(context).success,
            ),
          );

          // Return to pulse detail with success
          Navigator.pop(context, true);
        }
      } else {
        throw Exception('Failed to create highlight');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: FlutterFlowTheme.of(context).error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Video Player
          if (_isInitialized)
            GestureDetector(
              onTap: _togglePlayPause,
              child: SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _videoController.value.size.width,
                    height: _videoController.value.size.height,
                    child: VideoPlayer(_videoController),
                  ),
                ),
              ),
            )
          else
            Center(
              child: CircularProgressIndicator(
                color: FlutterFlowTheme.of(context).primary,
              ),
            ),

          // Play/Pause overlay
          if (_isInitialized && !_isPlaying && !_isUploading)
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 50,
                ),
              ),
            ),

          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  FlutterFlowIconButton(
                    borderRadius: 25,
                    buttonSize: 50,
                    fillColor: Colors.black.withOpacity(0.5),
                    icon: Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: _isUploading
                        ? null
                        : () {
                            Navigator.pop(context);
                          },
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _formatDuration(widget.duration),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.8),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Caption input
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: TextField(
                          controller: _captionController,
                          enabled: !_isUploading,
                          maxLength: 150,
                          maxLines: 2,
                          style: TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Add a caption...',
                            hintStyle: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(16),
                            counterStyle: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Public/Private toggle
                      GestureDetector(
                        onTap: _isUploading
                            ? null
                            : () {
                                setState(() {
                                  _isPublic = !_isPublic;
                                });
                              },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _isPublic ? Icons.public : Icons.lock,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _isPublic ? 'Public' : 'Private',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Spacer(),
                              Switch(
                                value: _isPublic,
                                onChanged: _isUploading
                                    ? null
                                    : (value) {
                                        setState(() {
                                          _isPublic = value;
                                        });
                                      },
                                activeColor:
                                    FlutterFlowTheme.of(context).primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Upload button
                      FFButtonWidget(
                        onPressed: _isUploading ? null : _saveHighlight,
                        text: _isUploading
                            ? 'Uploading... ${(_uploadProgress * 100).toInt()}%'
                            : 'Share Highlight',
                        options: FFButtonOptions(
                          width: double.infinity,
                          height: 56,
                          color: FlutterFlowTheme.of(context).primary,
                          textStyle:
                              FlutterFlowTheme.of(context).titleMedium.override(
                                    fontFamily: 'Inter',
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                          elevation: 0,
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),

                      if (_isUploading) ...[
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: _uploadProgress,
                          backgroundColor: Colors.white.withOpacity(0.3),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            FlutterFlowTheme.of(context).primary,
                          ),
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
