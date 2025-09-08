import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'socket_service.dart';

/// Group WebRTC call service using mesh topology.
/// Each remote participant has its own RTCPeerConnection and remote renderer.
class GroupCallService {
  GroupCallService._();
  static final GroupCallService instance = GroupCallService._();

  final _stateCtl = StreamController<GroupCallState>.broadcast();
  GroupCallState _state = GroupCallState.idle;
  Stream<GroupCallState> get onState => _stateCtl.stream;
  GroupCallState get state => _state;

  final _participantsCtl = StreamController<List<String>>.broadcast();
  Stream<List<String>> get participantsStream => _participantsCtl.stream;

  String? _conversationId;
  bool _isVideo = true;

  MediaStream? _localStream;
  final _localRenderer = RTCVideoRenderer();
  bool _renderersInit = false;

  // per user maps
  final Map<String, RTCPeerConnection> _pcs = {};
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};

  Future<void> initRenderers() async {
    if (_renderersInit) return;
    await _localRenderer.initialize();
    _renderersInit = true;
  }

  RTCVideoRenderer get localRenderer => _localRenderer;
  RTCVideoRenderer? remoteRendererFor(String userId) =>
      _remoteRenderers[userId];

  Future<void> _setState(GroupCallState s) async {
    _state = s;
    _stateCtl.add(s);
  }

  Future<void> _openLocal({required bool video}) async {
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
    await initRenderers();
    _localRenderer.srcObject = stream;
    _localStream = stream;
  }

  Future<RTCPeerConnection> _createPcFor(String remoteUserId) async {
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };
    final pc = await createPeerConnection(config);
    // Add local tracks
    if (_localStream != null) {
      for (final t in _localStream!.getTracks()) {
        await pc.addTrack(t, _localStream!);
      }
    }
    // Prepare remote renderer
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    _remoteRenderers[remoteUserId] = renderer;
    pc.onTrack = (e) {
      if (e.streams.isNotEmpty) renderer.srcObject = e.streams[0];
    };
    pc.onAddStream = (s) {
      renderer.srcObject = s;
    };
    pc.onIceCandidate = (cand) {
      final cid = _conversationId;
      if (cid != null) {
        SocketService.instance.sendGroupSignal(
          conversationId: cid,
          toUserId: remoteUserId,
          kind: 'ice',
          data: cand.toMap(),
        );
      }
    };
    _pcs[remoteUserId] = pc;
    return pc;
  }

  Future<void> start(
      {required String conversationId, bool isVideo = true}) async {
    _conversationId = conversationId;
    _isVideo = isVideo;
    await SocketService.instance.connect();
    await initRenderers();
    await _openLocal(video: isVideo);
    // Announce call start (banner for others); does not auto-join them
    SocketService.instance
        .startGroupCall(conversationId: conversationId, isVideo: isVideo);
    await _setState(GroupCallState.lobby);
  }

  Future<void> join() async {
    final cid = _conversationId;
    if (cid == null) return;
    SocketService.instance.joinGroupCall(conversationId: cid);
    await _setState(GroupCallState.joining);
  }

  Future<void> leave({bool endForAll = false}) async {
    final cid = _conversationId;
    if (cid != null) {
      if (endForAll) {
        SocketService.instance
            .stopGroupCall(conversationId: cid, reason: 'host-ended');
      } else {
        SocketService.instance.leaveGroupCall(conversationId: cid);
      }
    }
    await _teardown();
    await _setState(GroupCallState.ended);
  }

  Future<void> _teardown() async {
    final pcs = Map<String, RTCPeerConnection>.from(_pcs);
    _pcs.clear();
    for (final pc in pcs.values) {
      try {
        await pc.close();
      } catch (_) {}
    }
    final renders = Map<String, RTCVideoRenderer>.from(_remoteRenderers);
    _remoteRenderers.clear();
    for (final r in renders.values) {
      try {
        await r.dispose();
      } catch (_) {}
    }
    try {
      final ls = _localStream;
      _localStream = null;
      if (ls != null) {
        for (final t in ls.getTracks()) {
          try {
            t.stop();
          } catch (_) {}
        }
        await ls.dispose();
      }
      _localRenderer.srcObject = null;
    } catch (_) {}
  }

  // Handle participants list sent upon join
  void handleParticipants(List<dynamic> userIds) async {
    _participantsCtl.add(userIds.cast<String>());
    // Create offers to each participant
    final cid = _conversationId;
    if (cid == null) return;
    for (final uid in userIds) {
      final pc = await _createPcFor(uid);
      final offer = await pc.createOffer(
          {'offerToReceiveAudio': 1, 'offerToReceiveVideo': _isVideo ? 1 : 0});
      await pc.setLocalDescription(offer);
      SocketService.instance.sendGroupSignal(
        conversationId: cid,
        toUserId: uid,
        kind: 'offer',
        data: offer.toMap(),
      );
    }
    _setState(GroupCallState.inCall);
  }

  Future<void> handleSignal(Map<String, dynamic> map) async {
    final cid = map['conversationId']?.toString();
    if (cid == null || cid != _conversationId) return;
    final from = map['fromUserId']?.toString();
    final kind = map['kind']?.toString();
    final data = map['data'];
    if (from == null || kind == null || data == null) return;

    if (kind == 'offer') {
      final pc = await _createPcFor(from);
      final desc =
          RTCSessionDescription(data['sdp'] as String, data['type'] as String);
      await pc.setRemoteDescription(desc);
      final answer = await pc.createAnswer(
          {'offerToReceiveAudio': 1, 'offerToReceiveVideo': _isVideo ? 1 : 0});
      await pc.setLocalDescription(answer);
      SocketService.instance.sendGroupSignal(
        conversationId: _conversationId!,
        toUserId: from,
        kind: 'answer',
        data: answer.toMap(),
      );
      await _setState(GroupCallState.inCall);
    } else if (kind == 'answer') {
      final pc = _pcs[from];
      if (pc == null) return;
      final answer =
          RTCSessionDescription(data['sdp'] as String, data['type'] as String);
      await pc.setRemoteDescription(answer);
    } else if (kind == 'ice') {
      final pc = _pcs[from] ?? await _createPcFor(from);
      final cand = RTCIceCandidate(data['candidate'] as String?,
          data['sdpMid'] as String?, data['sdpMLineIndex'] as int?);
      await pc.addCandidate(cand);
    }
  }

  void attachSocketListeners() {
    // Idempotent; multiple attaches are fine with broadcast streams in UI
    final sock = SocketService.instance;
    sock.groupCallParticipants.listen((m) {
      final list = (m['participants'] as List?) ?? const [];
      handleParticipants(List<dynamic>.from(list));
    });
    sock.groupCallSignal.listen((m) async {
      await handleSignal(m);
    });
    sock.groupCallStopped.listen((m) async {
      // Clean up on remote end or empty room
      await _teardown();
      await _setState(GroupCallState.ended);
    });
  }
}

enum GroupCallState { idle, lobby, joining, inCall, ended }
