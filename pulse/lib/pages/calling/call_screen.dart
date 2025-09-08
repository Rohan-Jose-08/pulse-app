import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import '../../backend/webrtc_call_service.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.peerUserId, this.isVideo = true});
  final String peerUserId;
  final bool isVideo;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _micOn = true;
  bool _camOn = true;
  bool _speakerOn = false;
  CallState _callState = CallState.idle;
  StreamSubscription<CallState>? _stateSub;

  @override
  void initState() {
    super.initState();
    // Ensure renderers are initialized before use.
    WebRTCCallService.instance.initRenderers();
    _callState = WebRTCCallService.instance.state;
    _stateSub = WebRTCCallService.instance.onState.listen((s) {
      if (!mounted) return;
      setState(() => _callState = s);
      if (s == CallState.ended) {
        // Auto-close when the call ends remotely or locally
        if (mounted) Navigator.of(context).maybePop();
      }
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final svc = WebRTCCallService.instance;
    return Scaffold(
      backgroundColor: theme.primaryBackground.withOpacity(0.98),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: _buildBackdrop(theme, svc),
            ),
            Positioned(
              right: 16,
              top: 16,
              width: 120,
              height: 180,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColoredBox(
                  color: Colors.black54,
                  child: RTCVideoView(
                    svc.localRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    mirror: true,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _roundBtn(
                      icon: _speakerOn
                          ? Icons.volume_up_rounded
                          : Icons.hearing_rounded,
                      color: _speakerOn ? Colors.white : Colors.blueGrey,
                      onTap: () async {
                        final next = !_speakerOn;
                        await svc.setSpeakerphone(next);
                        if (mounted) setState(() => _speakerOn = next);
                      },
                    ),
                    _roundBtn(
                      icon: _micOn ? Icons.mic : Icons.mic_off,
                      color: _micOn ? Colors.white : Colors.redAccent,
                      onTap: () async {
                        final stream = svc.localRenderer.srcObject;
                        if (stream != null) {
                          for (final t in stream.getAudioTracks()) {
                            t.enabled = !_micOn;
                          }
                        }
                        setState(() => _micOn = !_micOn);
                      },
                    ),
                    _roundBtn(
                      icon: Icons.call_end,
                      color: Colors.red,
                      onTap: () async {
                        await svc.endCall(reason: 'hangup');
                        if (mounted) Navigator.of(context).pop();
                      },
                    ),
                    if (widget.isVideo)
                      _roundBtn(
                        icon: _camOn ? Icons.videocam : Icons.videocam_off,
                        color: _camOn ? Colors.white : Colors.redAccent,
                        onTap: () async {
                          final stream = svc.localRenderer.srcObject;
                          if (stream != null) {
                            for (final t in stream.getVideoTracks()) {
                              t.enabled = !_camOn;
                            }
                          }
                          setState(() => _camOn = !_camOn);
                        },
                      ),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildBackdrop(FlutterFlowTheme theme, WebRTCCallService svc) {
    if (_callState == CallState.ringing) {
      return Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 24),
                Icon(Icons.ring_volume_rounded,
                    size: 72, color: theme.secondaryText),
                const SizedBox(height: 12),
                Text(
                  'Ringing…',
                  style: theme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Waiting for them to accept',
                  style: theme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      );
    }
    // Default: show remote video (or blank if voice-only and no track yet)
    return RTCVideoView(
      svc.remoteRenderer,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
      mirror: false,
    );
  }

  Widget _roundBtn(
      {required IconData icon,
      required Color color,
      required VoidCallback onTap}) {
    return InkResponse(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
        ),
        child: Icon(icon, color: color, size: 28),
      ),
    );
  }
}
