import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import 'dart:async';
import 'video_preview_page.dart';

class VideoCapturePage extends StatefulWidget {
  const VideoCapturePage({
    super.key,
    required this.pulseId,
    required this.pulseName,
  });

  final String pulseId;
  final String pulseName;

  @override
  State<VideoCapturePage> createState() => _VideoCapturePageState();
}

class _VideoCapturePageState extends State<VideoCapturePage>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isRecording = false;
  bool _isInitialized = false;
  bool _isFrontCamera = true;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  static const int _maxRecordingSeconds = 60; // 60 seconds max like Instagram
  String? _videoPath;
  bool _isProcessing = false;
  String? _initError; // Track initialization errors

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordingTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _cameraController;

    // App state changed before we got the camera initialized.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      // Request camera and microphone permissions
      final cameraStatus = await Permission.camera.request();
      final micStatus = await Permission.microphone.request();

      if (cameraStatus.isDenied || micStatus.isDenied) {
        setState(() {
          _initError = 'Camera and microphone permissions are required';
        });
        return;
      }

      if (cameraStatus.isPermanentlyDenied || micStatus.isPermanentlyDenied) {
        setState(() {
          _initError =
              'Please enable camera and microphone permissions in app settings';
        });
        return;
      }

      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _initError = 'No cameras available on this device';
        });
        return;
      }

      final camera = _cameras.firstWhere(
        (cam) =>
            cam.lensDirection ==
            (_isFrontCamera
                ? CameraLensDirection.front
                : CameraLensDirection.back),
        orElse: () => _cameras.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _initError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _initError = 'Failed to initialize camera: ${e.toString()}';
        });
      }
    }
  }

  Future<void> _toggleCamera() async {
    if (_isRecording) return;

    setState(() {
      _isInitialized = false;
      _isFrontCamera = !_isFrontCamera;
    });

    await _cameraController?.dispose();
    await _initializeCamera();
  }

  Future<void> _startRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (_isRecording) return;

    try {
      await _cameraController!.startVideoRecording();
      setState(() {
        _isRecording = true;
        _recordingSeconds = 0;
      });

      // Start timer
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _recordingSeconds++;
        });

        // Auto-stop at max duration
        if (_recordingSeconds >= _maxRecordingSeconds) {
          _stopRecording();
        }
      });

      // Haptic feedback
      HapticFeedback.mediumImpact();
    } catch (e) {
      _showError('Failed to start recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    _recordingTimer?.cancel();

    try {
      setState(() {
        _isProcessing = true;
      });

      final XFile videoFile = await _cameraController!.stopVideoRecording();
      _videoPath = videoFile.path;

      setState(() {
        _isRecording = false;
        _isProcessing = false;
      });

      // Haptic feedback
      HapticFeedback.mediumImpact();

      // Navigate to preview
      if (mounted && _videoPath != null) {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VideoPreviewPage(
              videoPath: _videoPath!,
              pulseId: widget.pulseId,
              pulseName: widget.pulseName,
              duration: _recordingSeconds,
            ),
          ),
        );

        // If video was uploaded successfully, pop back to pulse detail
        if (result == true && mounted) {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _isRecording = false;
      });
      _showError('Failed to stop recording: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: FlutterFlowTheme.of(context).error,
      ),
    );
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
          // Camera Preview or Error State
          if (_initError != null)
            // Error state
            Container(
              color: Colors.black,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.white.withOpacity(0.7),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _initError!,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _initError = null;
                          });
                          _initializeCamera();
                        },
                        icon: Icon(Icons.refresh),
                        label: Text('Try Again'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: FlutterFlowTheme.of(context).primary,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_isInitialized && _cameraController != null)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _cameraController!.value.previewSize?.height ?? 1,
                  height: _cameraController!.value.previewSize?.width ?? 1,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            )
          else
            Center(
              child: CircularProgressIndicator(
                color: FlutterFlowTheme.of(context).primary,
              ),
            ),

          // Top Controls
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Close button
                  FlutterFlowIconButton(
                    borderRadius: 25,
                    buttonSize: 50,
                    fillColor: Colors.black.withOpacity(0.5),
                    icon: Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: _isRecording
                        ? null
                        : () {
                            Navigator.pop(context);
                          },
                  ),

                  // Recording indicator and timer
                  if (_isRecording)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatDuration(_recordingSeconds),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Flip camera button
                  FlutterFlowIconButton(
                    borderRadius: 25,
                    buttonSize: 50,
                    fillColor: Colors.black.withOpacity(0.5),
                    icon: Icon(
                      Icons.flip_camera_ios,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: _isRecording ? null : _toggleCamera,
                  ),
                ],
              ),
            ),
          ),

          // Bottom Controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Pulse name
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
                        'Create highlight for ${widget.pulseName}',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Record button
                    GestureDetector(
                      onTap: _isProcessing
                          ? null
                          : (_isRecording ? _stopRecording : _startRecording),
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white,
                            width: 4,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(6.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _isRecording ? Colors.red : Colors.white,
                              shape: _isRecording
                                  ? BoxShape.rectangle
                                  : BoxShape.circle,
                              borderRadius: _isRecording
                                  ? BorderRadius.circular(8)
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),

                    if (_isProcessing) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Processing video...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Progress bar
          if (_isRecording)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: LinearProgressIndicator(
                  value: _recordingSeconds / _maxRecordingSeconds,
                  backgroundColor: Colors.grey.withOpacity(0.3),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    FlutterFlowTheme.of(context).primary,
                  ),
                  minHeight: 4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
