import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'socket_service.dart';
import '../auth/firebase_auth/auth_util.dart';

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
  List<String> _participants = []; // Track participants locally

  final _remoteStreamCtl = StreamController<String>.broadcast();
  Stream<String> get remoteStreamUpdates => _remoteStreamCtl.stream;

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

  Future<bool> _waitForSocket({required Duration timeout}) async {
    final sock = SocketService.instance;
    if (sock.isConnected) return true;

    final endTime = DateTime.now().add(timeout);

    // Poll every 100ms to check if socket is connected
    while (DateTime.now().isBefore(endTime)) {
      await Future.delayed(Duration(milliseconds: 100));
      if (sock.isConnected) {
        return true;
      }
    }

    return false;
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
    print('[GroupCallService] Requesting local media stream (video: $video)');
    final stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    print(
        '[GroupCallService] Got local stream with ${stream.getTracks().length} tracks');

    for (final track in stream.getTracks()) {
      print(
          '[GroupCallService] Local track: ${track.kind} (enabled: ${track.enabled}, id: ${track.id})');
    }

    await initRenderers();
    _localRenderer.srcObject = stream;
    _localStream = stream;
    print('[GroupCallService] Local stream assigned to renderer');
  }

  Future<RTCPeerConnection> _createPcFor(String remoteUserId) async {
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };
    final pc = await createPeerConnection(config);
    // Add local tracks to send our video/audio to remote peer
    if (_localStream != null) {
      final tracks = _localStream!.getTracks();
      print(
          '[GroupCallService] Adding ${tracks.length} local tracks to peer connection for $remoteUserId');
      for (final t in tracks) {
        print(
            '[GroupCallService] Adding track: ${t.kind} (enabled: ${t.enabled}, muted: ${t.muted}, id: ${t.id})');
        // Use addTrack - simpler and more reliable for sending tracks
        final sender = await pc.addTrack(t, _localStream!);
        print('[GroupCallService] Added ${t.kind} track to peer connection');

        // Verify the sender was created successfully
        print(
            '[GroupCallService] Sender created for ${t.kind}, track in sender: ${sender.track != null}');
      }

      // Verify all senders after adding tracks
      final senders = await pc.getSenders();
      print(
          '[GroupCallService] Total senders after adding tracks: ${senders.length}');
      for (final sender in senders) {
        final track = sender.track;
        if (track != null) {
          print(
              '[GroupCallService] Sender has ${track.kind} track (enabled: ${track.enabled}, muted: ${track.muted})');
        }
      }
    } else {
      print(
          '[GroupCallService] WARNING: No local stream when creating PC for $remoteUserId');
    }
    // Prepare remote renderer
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    _remoteRenderers[remoteUserId] = renderer;
    print('[GroupCallService] Initialized remote renderer for $remoteUserId');

    pc.onTrack = (e) {
      print(
          '[GroupCallService] onTrack event for $remoteUserId: ${e.track.kind}, streams: ${e.streams.length}');
      if (e.streams.isNotEmpty) {
        print(
            '[GroupCallService] Setting stream to renderer for $remoteUserId');
        renderer.srcObject = e.streams[0];
        _remoteStreamCtl.add(remoteUserId);
      }
    };
    pc.onAddStream = (s) {
      print(
          '[GroupCallService] onAddStream event for $remoteUserId with ${s.getTracks().length} tracks');
      for (final track in s.getTracks()) {
        print(
            '[GroupCallService] Remote stream track: ${track.kind} (enabled: ${track.enabled})');
      }
      renderer.srcObject = s;
      _remoteStreamCtl.add(remoteUserId);
    };
    pc.onIceConnectionState = (state) {
      print(
          '[GroupCallService] ICE connection state for $remoteUserId: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        print(
            '[GroupCallService] ✓ ICE connection established for $remoteUserId');
      }
    };
    pc.onConnectionState = (state) {
      print('[GroupCallService] Connection state for $remoteUserId: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        print(
            '[GroupCallService] ✓ Peer connection established for $remoteUserId');
      }
    };
    pc.onIceCandidate = (cand) {
      print(
          '[GroupCallService] ICE candidate generated for $remoteUserId: ${cand.candidate != null ? "yes" : "end-of-candidates"}');
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

    print('[GroupCallService] Starting call setup...');

    // Try to connect with retry
    int attempts = 0;
    bool socketConnected = false;
    while (attempts < 3 && !socketConnected) {
      attempts++;
      print('[GroupCallService] Connection attempt $attempts/3...');

      await SocketService.instance.connect();

      // Wait for socket to actually connect with timeout
      print('[GroupCallService] Waiting for socket connection...');
      socketConnected = await _waitForSocket(timeout: Duration(seconds: 5));

      if (!socketConnected && attempts < 3) {
        print('[GroupCallService] Connection failed, retrying in 1 second...');
        await Future.delayed(Duration(seconds: 1));
      }
    }

    if (!socketConnected) {
      print(
          '[GroupCallService] ERROR: Socket failed to connect after $attempts attempts');
      print('[GroupCallService] Please check:');
      print('  1. Backend server is running');
      print('  2. Network connectivity');
      print('  3. Firewall settings');
      await _setState(GroupCallState.ended);
      throw Exception(
          'Unable to connect to server. Please check your connection and try again.');
    }
    print('[GroupCallService] Socket connected successfully');

    await initRenderers();
    await _openLocal(video: isVideo);
    // Announce call start (banner for others); does not auto-join them
    SocketService.instance
        .startGroupCall(conversationId: conversationId, isVideo: isVideo);
    await _setState(GroupCallState.lobby);
  }

  Future<void> join() async {
    print('[GroupCallService] ========== JOIN CALLED ==========');
    final cid = _conversationId;
    if (cid == null) {
      print('[GroupCallService] ERROR: No conversation ID when trying to join');
      return;
    }
    print('[GroupCallService] Joining call for conversation: $cid');
    SocketService.instance.joinGroupCall(conversationId: cid);
    await _setState(GroupCallState.joining);
    print('[GroupCallService] Join request sent, state: joining');
  }

  Future<void> leave({bool endForAll = false}) async {
    final cid = _conversationId;
    if (cid != null) {
      try {
        // Attempt to reconnect if socket is disconnected
        if (!SocketService.instance.isConnected) {
          print(
              '[GroupCallService] Socket disconnected during leave, attempting reconnect...');
          await SocketService.instance.connect();
          final connected = await _waitForSocket(timeout: Duration(seconds: 2));
          if (!connected) {
            print(
                '[GroupCallService] WARNING: Could not reconnect socket for leave event');
          }
        }

        if (endForAll) {
          SocketService.instance
              .stopGroupCall(conversationId: cid, reason: 'host-ended');
        } else {
          SocketService.instance.leaveGroupCall(conversationId: cid);
        }
      } catch (e) {
        print('[GroupCallService] Error sending leave event: $e');
        // Continue with cleanup even if socket event fails
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
    // Clear participants list
    _participants.clear();
    _participantsCtl.add([]);
  }

  // Handle participants list sent upon join
  void handleParticipants(List<dynamic> userIds) async {
    print('[GroupCallService] ========== HANDLE PARTICIPANTS ==========');
    print(
        '[GroupCallService] handleParticipants called with ${userIds.length} users: $userIds');
    print(
        '[GroupCallService] Local stream is ${_localStream != null ? "available" : "NULL"}');
    _participants = userIds.cast<String>();
    _participantsCtl.add(_participants);
    // Create offers to each participant
    final cid = _conversationId;
    if (cid == null) return;
    for (final uid in userIds) {
      print('[GroupCallService] Creating offer for user: $uid');
      final pc = await _createPcFor(uid);

      // Verify senders before creating offer
      final senders = await pc.getSenders();
      print(
          '[GroupCallService] Peer connection has ${senders.length} senders before offer');
      for (final sender in senders) {
        final track = sender.track;
        if (track != null) {
          print(
              '[GroupCallService] Sender track: ${track.kind} (enabled: ${track.enabled})');
        }
      }

      // Create offer without old deprecated constraints since we're using transceivers
      final offer = await pc.createOffer({});
      await pc.setLocalDescription(offer);
      print('[GroupCallService] Created and set offer for $uid');
      print(
          '[GroupCallService] Offer SDP contains video: ${offer.sdp?.contains('m=video')}');
      print(
          '[GroupCallService] Offer SDP contains audio: ${offer.sdp?.contains('m=audio')}');

      // Check if video is being sent (not just received)
      if (offer.sdp != null) {
        final sdpLines = offer.sdp!.split('\n');
        bool inVideoSection = false;
        for (final line in sdpLines) {
          if (line.startsWith('m=video')) {
            inVideoSection = true;
            print('[GroupCallService] Video m-line: $line');
          } else if (line.startsWith('m=')) {
            inVideoSection = false;
          } else if (inVideoSection && line.startsWith('a=sendrecv')) {
            print('[GroupCallService] ✓ Video is set to sendrecv');
          } else if (inVideoSection && line.startsWith('a=sendonly')) {
            print('[GroupCallService] ✓ Video is set to sendonly');
          } else if (inVideoSection && line.startsWith('a=recvonly')) {
            print(
                '[GroupCallService] ⚠ WARNING: Video is set to recvonly (not sending!)');
          } else if (inVideoSection && line.startsWith('a=inactive')) {
            print('[GroupCallService] ⚠ WARNING: Video is set to inactive!');
          }
        }
      }

      // Verify transceivers are properly configured
      final transceivers = await pc.getTransceivers();
      print(
          '[GroupCallService] Peer connection has ${transceivers.length} transceivers after offer');
      for (final transceiver in transceivers) {
        final track = transceiver.sender.track;
        final receiverTrack = transceiver.receiver.track;
        print(
            '[GroupCallService] Transceiver sender: ${track?.kind ?? "no-track"} (enabled: ${track?.enabled ?? false}, muted: ${track?.muted ?? false})');
        print(
            '[GroupCallService] Transceiver receiver: ${receiverTrack?.kind ?? "no-track"}');
      }

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

    print('[GroupCallService] Received $kind signal from $from');

    if (kind == 'offer') {
      final pc = await _createPcFor(from);
      final desc =
          RTCSessionDescription(data['sdp'] as String, data['type'] as String);
      await pc.setRemoteDescription(desc);
      print('[GroupCallService] Set remote description (offer) from $from');

      // Verify senders before creating answer
      final senders = await pc.getSenders();
      print(
          '[GroupCallService] Peer connection has ${senders.length} senders before answer');

      // Create answer without old deprecated constraints since we're using transceivers
      final answer = await pc.createAnswer({});
      await pc.setLocalDescription(answer);
      print('[GroupCallService] Created and set answer for $from');
      print(
          '[GroupCallService] Answer SDP contains video: ${answer.sdp?.contains('m=video')}');
      print(
          '[GroupCallService] Answer SDP contains audio: ${answer.sdp?.contains('m=audio')}');

      // Check if video is being sent in answer
      if (answer.sdp != null) {
        final sdpLines = answer.sdp!.split('\n');
        bool inVideoSection = false;
        for (final line in sdpLines) {
          if (line.startsWith('m=video')) {
            inVideoSection = true;
            print('[GroupCallService] Answer video m-line: $line');
          } else if (line.startsWith('m=')) {
            inVideoSection = false;
          } else if (inVideoSection &&
              (line.startsWith('a=sendrecv') ||
                  line.startsWith('a=sendonly') ||
                  line.startsWith('a=recvonly') ||
                  line.startsWith('a=inactive'))) {
            print('[GroupCallService] Answer video direction: $line');
          }
        }
      }

      SocketService.instance.sendGroupSignal(
        conversationId: _conversationId!,
        toUserId: from,
        kind: 'answer',
        data: answer.toMap(),
      );
      await _setState(GroupCallState.inCall);
    } else if (kind == 'answer') {
      final pc = _pcs[from];
      if (pc == null) {
        print(
            '[GroupCallService] WARNING: No peer connection for $from when receiving answer');
        return;
      }
      final answer =
          RTCSessionDescription(data['sdp'] as String, data['type'] as String);
      await pc.setRemoteDescription(answer);
      print('[GroupCallService] Set remote description (answer) from $from');
    } else if (kind == 'ice') {
      final pc = _pcs[from] ?? await _createPcFor(from);
      final cand = RTCIceCandidate(data['candidate'] as String?,
          data['sdpMid'] as String?, data['sdpMLineIndex'] as int?);
      await pc.addCandidate(cand);
      print('[GroupCallService] Added ICE candidate from $from');
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
    // Handle new participant joining the call
    sock.groupCallParticipantJoined.listen((m) async {
      final cid = m['conversationId']?.toString();
      if (cid == null || cid != _conversationId) return;
      final userId = m['userId']?.toString();
      if (userId == null) return;

      // Ignore if it's ourselves joining (backend may broadcast this to everyone)
      final myUserId = currentUserUid;
      if (userId == myUserId) {
        print(
            '[GroupCallService] Ignoring participant joined event for self: $userId');
        return;
      }

      print('[GroupCallService] Participant joined: $userId');

      // Update participants list
      if (!_participants.contains(userId)) {
        _participants.add(userId);
        _participantsCtl.add(List<String>.from(_participants));
      }

      // Polite peer pattern: Only create offer if our user ID is greater
      // This prevents both peers from creating offers (which causes signaling state errors)
      final shouldCreateOffer = myUserId.compareTo(userId) > 0;

      print(
          '[GroupCallService] Should create offer to $userId? $shouldCreateOffer (my ID: $myUserId)');

      // Create a peer connection and send an offer to the new participant
      if (!_pcs.containsKey(userId) && shouldCreateOffer) {
        print(
            '[GroupCallService] Creating peer connection for new participant: $userId');
        final pc = await _createPcFor(userId);

        // Verify senders before creating offer
        final senders = await pc.getSenders();
        print(
            '[GroupCallService] Peer connection has ${senders.length} senders for new participant');

        // Create offer without old deprecated constraints
        final offer = await pc.createOffer({});
        await pc.setLocalDescription(offer);
        print('[GroupCallService] Sending offer to new participant: $userId');
        SocketService.instance.sendGroupSignal(
          conversationId: _conversationId!,
          toUserId: userId,
          kind: 'offer',
          data: offer.toMap(),
        );
      } else if (!shouldCreateOffer) {
        print(
            '[GroupCallService] Waiting for offer from $userId (polite peer)');
      }
    });
    // Handle participant leaving the call
    sock.groupCallParticipantLeft.listen((m) async {
      final cid = m['conversationId']?.toString();
      if (cid == null || cid != _conversationId) return;
      final userId = m['userId']?.toString();
      if (userId == null) return;
      // Remove from participants list
      _participants.remove(userId);
      _participantsCtl.add(List<String>.from(_participants));
      // Clean up peer connection for this user
      final pc = _pcs.remove(userId);
      if (pc != null) {
        try {
          await pc.close();
        } catch (_) {}
      }
      // Clean up remote renderer
      final renderer = _remoteRenderers.remove(userId);
      if (renderer != null) {
        try {
          await renderer.dispose();
        } catch (_) {}
      }
    });
  }
}

enum GroupCallState { idle, lobby, joining, inCall, ended }
