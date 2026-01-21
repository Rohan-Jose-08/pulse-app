import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Service for recording voice messages
class VoiceRecordingService {
  VoiceRecordingService._();
  static final VoiceRecordingService instance = VoiceRecordingService._();

  final AudioRecorder _recorder = AudioRecorder();

  bool _isRecording = false;
  DateTime? _recordingStartTime;
  String? _currentFilePath;
  Timer? _durationTimer;

  // Stream for recording state updates
  final _stateController = StreamController<VoiceRecordingState>.broadcast();
  Stream<VoiceRecordingState> get stateStream => _stateController.stream;

  // Stream for amplitude updates (for waveform visualization)
  final _amplitudeController = StreamController<double>.broadcast();
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  bool get isRecording => _isRecording;

  Duration get currentDuration {
    if (_recordingStartTime == null) return Duration.zero;
    return DateTime.now().difference(_recordingStartTime!);
  }

  /// Check if microphone permission is granted
  Future<bool> hasPermission() async {
    final status = await Permission.microphone.status;
    return status.isGranted;
  }

  /// Request microphone permission
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Start recording a voice message
  Future<bool> startRecording() async {
    try {
      // Check permission
      if (!await hasPermission()) {
        final granted = await requestPermission();
        if (!granted) {
          _stateController.add(VoiceRecordingState.permissionDenied);
          return false;
        }
      }

      // Check if recorder is available
      if (!await _recorder.hasPermission()) {
        _stateController.add(VoiceRecordingState.permissionDenied);
        return false;
      }

      // Generate unique file path
      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentFilePath = '${dir.path}/voice_message_$timestamp.m4a';

      // Configure and start recording
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: _currentFilePath!,
      );

      _isRecording = true;
      _recordingStartTime = DateTime.now();
      _stateController.add(VoiceRecordingState.recording);

      // Start amplitude monitoring for waveform
      _startAmplitudeMonitoring();

      // Start duration timer
      _durationTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (_isRecording) {
          _stateController.add(VoiceRecordingState.recording);
        }
      });

      return true;
    } catch (e) {
      debugPrint('VoiceRecordingService: Start error: $e');
      _stateController.add(VoiceRecordingState.error);
      return false;
    }
  }

  void _startAmplitudeMonitoring() {
    Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (!_isRecording) {
        timer.cancel();
        return;
      }
      try {
        final amplitude = await _recorder.getAmplitude();
        // Normalize amplitude to 0-1 range (dBFS typically ranges from -160 to 0)
        final normalized = ((amplitude.current + 60) / 60).clamp(0.0, 1.0);
        _amplitudeController.add(normalized);
      } catch (_) {
        // Ignore amplitude errors
      }
    });
  }

  /// Stop recording and return the file path and duration
  Future<VoiceRecordingResult?> stopRecording() async {
    if (!_isRecording) return null;

    try {
      _durationTimer?.cancel();
      _durationTimer = null;

      final path = await _recorder.stop();
      final duration = currentDuration;

      _isRecording = false;
      _recordingStartTime = null;
      _stateController.add(VoiceRecordingState.stopped);

      if (path == null || path.isEmpty) {
        return null;
      }

      // Verify file exists
      final file = File(path);
      if (!await file.exists()) {
        return null;
      }

      return VoiceRecordingResult(
        filePath: path,
        duration: duration,
        file: file,
      );
    } catch (e) {
      debugPrint('VoiceRecordingService: Stop error: $e');
      _isRecording = false;
      _recordingStartTime = null;
      _stateController.add(VoiceRecordingState.error);
      return null;
    }
  }

  /// Cancel recording and delete the file
  Future<void> cancelRecording() async {
    if (!_isRecording) return;

    try {
      _durationTimer?.cancel();
      _durationTimer = null;

      await _recorder.stop();

      // Delete the file
      if (_currentFilePath != null) {
        final file = File(_currentFilePath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      debugPrint('VoiceRecordingService: Cancel error: $e');
    } finally {
      _isRecording = false;
      _recordingStartTime = null;
      _currentFilePath = null;
      _stateController.add(VoiceRecordingState.cancelled);
    }
  }

  /// Dispose resources
  void dispose() {
    _durationTimer?.cancel();
    _recorder.dispose();
    _stateController.close();
    _amplitudeController.close();
  }
}

/// Recording state enum
enum VoiceRecordingState {
  idle,
  recording,
  stopped,
  cancelled,
  error,
  permissionDenied,
}

/// Result of a voice recording
class VoiceRecordingResult {
  final String filePath;
  final Duration duration;
  final File file;

  VoiceRecordingResult({
    required this.filePath,
    required this.duration,
    required this.file,
  });

  int get durationMs => duration.inMilliseconds;
}
