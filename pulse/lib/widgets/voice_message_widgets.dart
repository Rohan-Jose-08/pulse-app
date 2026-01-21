import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:just_audio/just_audio.dart';
import '../services/voice_recording_service.dart';

/// Voice message recorder widget with waveform visualization
class VoiceRecorderWidget extends StatefulWidget {
  const VoiceRecorderWidget({
    super.key,
    required this.onRecordingComplete,
    required this.onCancel,
    this.maxDuration = const Duration(minutes: 5),
    this.primaryColor,
    this.backgroundColor,
  });

  final void Function(VoiceRecordingResult result) onRecordingComplete;
  final VoidCallback onCancel;
  final Duration maxDuration;
  final Color? primaryColor;
  final Color? backgroundColor;

  @override
  State<VoiceRecorderWidget> createState() => _VoiceRecorderWidgetState();
}

class _VoiceRecorderWidgetState extends State<VoiceRecorderWidget>
    with SingleTickerProviderStateMixin {
  final _service = VoiceRecordingService.instance;
  final List<double> _amplitudes = [];
  Timer? _durationTimer;
  Duration _currentDuration = Duration.zero;
  bool _isRecording = false;
  StreamSubscription<double>? _amplitudeSub;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _startRecording();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _amplitudeSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final started = await _service.startRecording();
    if (!started && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Could not start recording. Check microphone permission.')),
      );
      widget.onCancel();
      return;
    }

    setState(() => _isRecording = true);

    // Listen to amplitude changes
    _amplitudeSub = _service.amplitudeStream.listen((amp) {
      if (mounted) {
        setState(() {
          _amplitudes.add(amp);
          // Keep last 50 amplitudes for waveform
          if (_amplitudes.length > 50) {
            _amplitudes.removeAt(0);
          }
        });
      }
    });

    // Update duration
    _durationTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted && _isRecording) {
        setState(() {
          _currentDuration = _service.currentDuration;
        });

        // Auto-stop at max duration
        if (_currentDuration >= widget.maxDuration) {
          _stopRecording();
        }
      }
    });
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    setState(() => _isRecording = false);
    _durationTimer?.cancel();
    _amplitudeSub?.cancel();

    final result = await _service.stopRecording();
    if (result != null) {
      widget.onRecordingComplete(result);
    } else {
      widget.onCancel();
    }
  }

  Future<void> _cancelRecording() async {
    setState(() => _isRecording = false);
    _durationTimer?.cancel();
    _amplitudeSub?.cancel();
    await _service.cancelRecording();
    widget.onCancel();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = widget.primaryColor ?? Theme.of(context).primaryColor;
    final backgroundColor =
        widget.backgroundColor ?? Theme.of(context).cardColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Cancel button
          GestureDetector(
            onTap: _cancelRecording,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.red, size: 24),
            ),
          ),
          const SizedBox(width: 12),

          // Waveform visualization
          Expanded(
            child: SizedBox(
              height: 40,
              child: CustomPaint(
                painter: _WaveformPainter(
                  amplitudes: _amplitudes,
                  color: primaryColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Duration
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(
                      0.5 + (_pulseController.value * 0.5),
                    ),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _formatDuration(_currentDuration),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Send button
          GestureDetector(
            onTap: _stopRecording,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: primaryColor,
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.send_rounded, color: Colors.white, size: 22),
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(
              begin: const Offset(1, 1),
              end: const Offset(1.05, 1.05),
              duration: 800.ms),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.2, end: 0);
  }
}

/// Waveform painter for recording visualization
class _WaveformPainter extends CustomPainter {
  final List<double> amplitudes;
  final Color color;

  _WaveformPainter({required this.amplitudes, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final barWidth = size.width / 50;
    final maxHeight = size.height * 0.8;
    final centerY = size.height / 2;

    for (int i = 0; i < amplitudes.length; i++) {
      final x = i * barWidth + barWidth / 2;
      final barHeight = math.max(4.0, amplitudes[i] * maxHeight);

      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        paint,
      );
    }

    // Draw placeholder bars for remaining space
    final placeholderPaint = Paint()
      ..color = color.withOpacity(0.2)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    for (int i = amplitudes.length; i < 50; i++) {
      final x = i * barWidth + barWidth / 2;
      canvas.drawLine(
        Offset(x, centerY - 2),
        Offset(x, centerY + 2),
        placeholderPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return amplitudes.length != oldDelegate.amplitudes.length ||
        (amplitudes.isNotEmpty &&
            oldDelegate.amplitudes.isNotEmpty &&
            amplitudes.last != oldDelegate.amplitudes.last);
  }
}

/// Voice message player widget with waveform and playback controls
class VoiceMessagePlayer extends StatefulWidget {
  const VoiceMessagePlayer({
    super.key,
    required this.audioUrl,
    required this.duration,
    this.isMe = false,
    this.primaryColor,
    this.backgroundColor,
  });

  final String audioUrl;
  final int duration; // in milliseconds
  final bool isMe;
  final Color? primaryColor;
  final Color? backgroundColor;

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  late AudioPlayer _player;
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Duration _totalDuration = Duration.zero;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _totalDuration = Duration(milliseconds: widget.duration);
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      _playerStateSub = _player.playerStateStream.listen((state) {
        if (mounted) {
          setState(() {
            _isPlaying = state.playing;
            _isLoading = state.processingState == ProcessingState.loading ||
                state.processingState == ProcessingState.buffering;
          });

          // Reset position when completed
          if (state.processingState == ProcessingState.completed) {
            _player.seek(Duration.zero);
            _player.pause();
          }
        }
      });

      _positionSub = _player.positionStream.listen((pos) {
        if (mounted) {
          setState(() => _position = pos);
        }
      });

      _durationSub = _player.durationStream.listen((dur) {
        if (dur != null && mounted) {
          setState(() => _totalDuration = dur);
        }
      });

      await _player.setUrl(widget.audioUrl);
    } catch (e) {
      debugPrint('VoiceMessagePlayer: Init error: $e');
    }
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> _seek(double value) async {
    final position =
        Duration(milliseconds: (value * _totalDuration.inMilliseconds).round());
    await _player.seek(position);
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = widget.primaryColor ??
        (widget.isMe ? Colors.white : Theme.of(context).primaryColor);
    final backgroundColor = widget.backgroundColor ??
        (widget.isMe ? Theme.of(context).primaryColor : Colors.grey.shade200);
    final progress = _totalDuration.inMilliseconds > 0
        ? _position.inMilliseconds / _totalDuration.inMilliseconds
        : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: const BoxConstraints(maxWidth: 280, minWidth: 200),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play/Pause button
          GestureDetector(
            onTap: _isLoading ? null : _togglePlayback,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.isMe
                    ? Colors.white.withOpacity(0.2)
                    : primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: _isLoading
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(primaryColor),
                      ),
                    )
                  : Icon(
                      _isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: primaryColor,
                      size: 26,
                    ),
            ),
          ),
          const SizedBox(width: 8),

          // Waveform / Progress
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Waveform slider
                SizedBox(
                  height: 30,
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 4,
                      activeTrackColor: primaryColor,
                      inactiveTrackColor: widget.isMe
                          ? Colors.white.withOpacity(0.3)
                          : Colors.grey.shade400,
                      thumbColor: primaryColor,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
                      value: progress.clamp(0.0, 1.0),
                      onChanged: _seek,
                    ),
                  ),
                ),

                // Duration
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(_position),
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.isMe
                            ? Colors.white.withOpacity(0.7)
                            : Colors.grey.shade600,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.mic,
                          size: 12,
                          color: widget.isMe
                              ? Colors.white.withOpacity(0.7)
                              : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDuration(_totalDuration),
                          style: TextStyle(
                            fontSize: 11,
                            color: widget.isMe
                                ? Colors.white.withOpacity(0.7)
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Mini voice message indicator for replies and previews
class VoiceMessageIndicator extends StatelessWidget {
  const VoiceMessageIndicator({
    super.key,
    required this.duration,
    this.color,
  });

  final int duration;
  final Color? color;

  String _formatDuration(int ms) {
    final d = Duration(milliseconds: ms);
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.grey.shade600;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.mic, size: 16, color: c),
        const SizedBox(width: 4),
        Text(
          'Voice message · ${_formatDuration(duration)}',
          style: TextStyle(
            fontSize: 13,
            color: c,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}
