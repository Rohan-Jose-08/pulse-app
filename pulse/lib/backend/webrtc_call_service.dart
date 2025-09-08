import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'socket_service.dart';

/// Lightweight 1:1 call controller using Socket.IO signaling.
/// Contract:
/// - callPeer(toUserId, {video}) initiates a call and emits call:initiate then offer
/// - onIncomingCall stream notifies UI to accept/reject
/// - acceptIncoming(fromUserId) answers by setting remote offer and sending answer
/// - endCall() tears down and notifies peer
class WebRTCCallService {
  WebRTCCallService._();
  static final WebRTCCallService instance = WebRTCCallService._();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final _incomingController = StreamController<IncomingCall>.broadcast();
  final _stateController = StreamController<CallState>.broadcast();
  final _remoteVideo = RTCVideoRenderer();
  final _localVideo = RTCVideoRenderer();
  bool _renderersInitialized = false;

  String? _currentPeerId;
  bool _speakerOn = false;
  CallState _state = CallState.idle;
  bool _listenersAttached = false;

  Stream<IncomingCall> get onIncomingCall => _incomingController.stream;
  Stream<CallState> get onState => _stateController.stream;
  RTCVideoRenderer get localRenderer => _localVideo;
  RTCVideoRenderer get remoteRenderer => _remoteVideo;
  bool get speakerOn => _speakerOn;
  CallState get state => _state;

  void _setState(CallState s) {
    _state = s;
    _stateController.add(s);
  }

  Future<void> _teardownInternal({bool notify = false, String? reason}) async {
    try {
      if (notify && _currentPeerId != null) {
        SocketService.instance
            .sendCallEnd(toUserId: _currentPeerId!, reason: reason);
      }
    } catch (_) {}
    try {
      final pc = _pc;
      _pc = null;
      await pc?.close();
    } catch (_) {}
    try {
      final local = _localStream;
      _localStream = null;
      if (local != null) {
        for (final t in local.getTracks()) {
          try {
            t.stop();
          } catch (_) {}
        }
        await local.dispose();
      }
    } catch (_) {}
    try {
      final remote = _remoteStream;
      _remoteStream = null;
      if (remote != null) {
        for (final t in remote.getTracks()) {
          try {
            t.stop();
          } catch (_) {}
        }
        await remote.dispose();
      }
    } catch (_) {}
    try {
      // Clear renderers' sources so next call starts fresh
      _localVideo.srcObject = null;
      _remoteVideo.srcObject = null;
    } catch (_) {}
    _currentPeerId = null;
    _setState(CallState.idle);
  }

  Future<void> _configureAudio({required bool isVideo}) async {
    // Route audio: speaker for video, earpiece for voice.
    try {
      await Helper.setSpeakerphoneOn(isVideo);
      _speakerOn = isVideo;
    } catch (_) {}
  }

  Future<void> setSpeakerphone(bool on) async {
    try {
      await Helper.setSpeakerphoneOn(on);
      _speakerOn = on;
    } catch (_) {
      // no-op
    }
  }

  Future<void> initRenderers() async {
    if (_renderersInitialized) return;
    await _localVideo.initialize();
    await _remoteVideo.initialize();
    _renderersInitialized = true;
  }

  Future<void> disposeRenderers() async {
    if (!_renderersInitialized) return;
    try {
      await _localVideo.dispose();
    } catch (_) {}
    try {
      await _remoteVideo.dispose();
    } catch (_) {}
    _renderersInitialized = false;
  }

  Future<RTCPeerConnection> _ensurePc() async {
    if (_pc != null) return _pc!;
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };
    final constraints = {
      'mandatory': {},
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
      ],
    };
    final pc = await createPeerConnection(config, constraints);
    _pc = pc;
    _remoteStream = await createLocalMediaStream('remote');
    pc.onAddStream = (stream) {
      _remoteVideo.srcObject = stream;
      _setState(CallState.remoteStream);
    };
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteVideo.srcObject = event.streams[0];
        _setState(CallState.remoteStream);
      }
    };
    pc.onIceCandidate = (candidate) {
      if (_currentPeerId != null) {
        SocketService.instance.sendCallIceCandidate(
          toUserId: _currentPeerId!,
          candidate: candidate.toMap(),
        );
      }
    };
    return pc;
  }

  Future<MediaStream> _openUserMedia({required bool video}) async {
    final mediaConstraints = {
      'audio': true,
      'video': video
          ? {
              'facingMode': 'user',
              'width': {'ideal': 640},
              'height': {'ideal': 480},
              'frameRate': {'ideal': 24},
            }
          : false,
    };
    final stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    // Ensure renderers are initialized before assignment
    await initRenderers();
    try {
      _localVideo.srcObject = stream;
    } catch (_) {
      // If a dispose happened elsewhere, re-init once and retry
      await initRenderers();
      _localVideo.srcObject = stream;
    }
    _localStream = stream;
    return stream;
  }

  // Public API
  Future<void> callPeer({
    required String toUserId,
    bool isVideo = true,
    String? conversationId,
  }) async {
    try {
      // Ensure a clean slate if a previous call didn't cleanly teardown yet
      await _teardownInternal();
      _currentPeerId = toUserId;
      await SocketService.instance.connect();
      await initRenderers();
      await _configureAudio(isVideo: isVideo);
      final pc = await _ensurePc();
      final local = await _openUserMedia(video: isVideo);
      for (var track in local.getTracks()) {
        await pc.addTrack(track, local);
      }
      // notify incoming
      SocketService.instance.sendCallInitiate(
        toUserId: toUserId,
        conversationId: conversationId,
        isVideo: isVideo,
      );

      final offer = await pc.createOffer(
          {'offerToReceiveAudio': 1, 'offerToReceiveVideo': isVideo ? 1 : 0});
      await pc.setLocalDescription(offer);
      SocketService.instance.sendCallOffer(
        toUserId: toUserId,
        sdp: offer.toMap(),
        conversationId: conversationId,
        isVideo: isVideo,
      );
      _setState(CallState.ringing);
    } catch (e, st) {
      // ignore: avoid_print
      print('callPeer error: ' + e.toString() + '\n' + st.toString());
      // Best effort cleanup
      await _teardownInternal();
      rethrow;
    }
  }

  Future<void> acceptIncoming({
    required String fromUserId,
    required RTCSessionDescription remoteOffer,
    bool isVideo = true,
  }) async {
    try {
      await _teardownInternal();
      _currentPeerId = fromUserId;
      await SocketService.instance.connect();
      await initRenderers();
      await _configureAudio(isVideo: isVideo);
      final pc = await _ensurePc();
      final local = await _openUserMedia(video: isVideo);
      for (var track in local.getTracks()) {
        await pc.addTrack(track, local);
      }
      await pc.setRemoteDescription(remoteOffer);
      final answer = await pc.createAnswer(
          {'offerToReceiveAudio': 1, 'offerToReceiveVideo': isVideo ? 1 : 0});
      await pc.setLocalDescription(answer);
      SocketService.instance.sendCallAnswer(
        toUserId: fromUserId,
        sdp: answer.toMap(),
      );
      _setState(CallState.inCall);
    } catch (e, st) {
      // ignore: avoid_print
      print('acceptIncoming error: ' + e.toString() + '\n' + st.toString());
      await _teardownInternal();
      rethrow;
    }
  }

  Future<void> addRemoteIce(Map<String, dynamic> cand,
      {required String fromUserId}) async {
    final pc = await _ensurePc();
    final candidate = RTCIceCandidate(
      cand['candidate'] as String?,
      cand['sdpMid'] as String?,
      cand['sdpMLineIndex'] as int?,
    );
    await pc.addCandidate(candidate);
  }

  Future<void> setRemoteAnswer(Map<String, dynamic> sdpMap) async {
    final pc = await _ensurePc();
    final answer = RTCSessionDescription(
      sdpMap['sdp'] as String,
      sdpMap['type'] as String,
    );
    await pc.setRemoteDescription(answer);
    _setState(CallState.inCall);
  }

  Future<void> endCall({String? reason, bool notifyPeer = true}) async {
    // If already ended, ignore further requests
    if (_state == CallState.ended) return;
    await _teardownInternal(notify: notifyPeer, reason: reason);
    _setState(CallState.ended);
  }

  // Wire up signaling listeners. Should be called once on app start.
  void attachSocketListeners() {
    if (_listenersAttached) return;
    _listenersAttached = true;
    SocketService.instance.connect();
    final sock = SocketService.instance;
    sock.callIncoming.listen((map) {
      _incomingController.add(IncomingCall(
        fromUserId: map['fromUserId']?.toString() ?? '',
        conversationId: map['conversationId']?.toString(),
        isVideo: map['isVideo'] == true,
      ));
    });
    sock.callOffer.listen((map) async {
      _incomingController.add(IncomingCall(
        fromUserId: map['fromUserId']?.toString() ?? '',
        conversationId: map['conversationId']?.toString(),
        isVideo: map['isVideo'] == true,
        remoteOffer: RTCSessionDescription(
          map['sdp']['sdp'] as String,
          map['sdp']['type'] as String,
        ),
      ));
    });
    sock.callAnswer.listen((map) async {
      final sdp = Map<String, dynamic>.from(map['sdp'] as Map);
      await setRemoteAnswer(sdp);
    });
    sock.callIce.listen((map) async {
      await addRemoteIce(Map<String, dynamic>.from(map['candidate'] as Map),
          fromUserId: map['fromUserId']?.toString() ?? '');
    });
    sock.callEnded.listen((_) async {
      // Remote hung up; end locally without echoing another end event
      await endCall(reason: 'remote-ended', notifyPeer: false);
    });
  }
}

class IncomingCall {
  IncomingCall({
    required this.fromUserId,
    this.conversationId,
    this.isVideo = true,
    this.remoteOffer,
  });

  final String fromUserId;
  final String? conversationId;
  final bool isVideo;
  final RTCSessionDescription? remoteOffer;
}

enum CallState { idle, ringing, inCall, remoteStream, ended }
