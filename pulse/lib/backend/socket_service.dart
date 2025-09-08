import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:firebase_auth/firebase_auth.dart';
import 'api_service.dart';
import 'config.dart';

class SocketService {
  SocketService._();
  static final SocketService instance = SocketService._();

  IO.Socket? _socket;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _typingController = StreamController<Map<String, dynamic>>.broadcast();
  final _conversationUpdated =
      StreamController<Map<String, dynamic>>.broadcast();
  final List<Map<String, dynamic>> _pendingEmits = [];

  // --- WebRTC signaling streams ---
  final _callIncoming = StreamController<Map<String, dynamic>>.broadcast();
  final _callOffer = StreamController<Map<String, dynamic>>.broadcast();
  final _callAnswer = StreamController<Map<String, dynamic>>.broadcast();
  final _callIce = StreamController<Map<String, dynamic>>.broadcast();
  final _callEnded = StreamController<Map<String, dynamic>>.broadcast();

  // --- Group call signaling streams ---
  final _gcStarted = StreamController<Map<String, dynamic>>.broadcast();
  final _gcStopped = StreamController<Map<String, dynamic>>.broadcast();
  final _gcParticipants = StreamController<Map<String, dynamic>>.broadcast();
  final _gcParticipantJoined =
      StreamController<Map<String, dynamic>>.broadcast();
  final _gcParticipantLeft = StreamController<Map<String, dynamic>>.broadcast();
  final _gcSignal = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  Stream<Map<String, dynamic>> get typing => _typingController.stream;
  Stream<Map<String, dynamic>> get conversationUpdates =>
      _conversationUpdated.stream;
  Stream<Map<String, dynamic>> get callIncoming => _callIncoming.stream;
  Stream<Map<String, dynamic>> get callOffer => _callOffer.stream;
  Stream<Map<String, dynamic>> get callAnswer => _callAnswer.stream;
  Stream<Map<String, dynamic>> get callIce => _callIce.stream;
  Stream<Map<String, dynamic>> get callEnded => _callEnded.stream;
  // Group call
  Stream<Map<String, dynamic>> get groupCallStarted => _gcStarted.stream;
  Stream<Map<String, dynamic>> get groupCallStopped => _gcStopped.stream;
  Stream<Map<String, dynamic>> get groupCallParticipants =>
      _gcParticipants.stream;
  Stream<Map<String, dynamic>> get groupCallParticipantJoined =>
      _gcParticipantJoined.stream;
  Stream<Map<String, dynamic>> get groupCallParticipantLeft =>
      _gcParticipantLeft.stream;
  Stream<Map<String, dynamic>> get groupCallSignal => _gcSignal.stream;

  bool get isConnected => _socket?.connected == true;

  Future<void> connect({String? baseUrl}) async {
    if (_socket != null && _socket!.connected) return;
    // Ensure the backend user exists before attempting socket auth
    await ApiService.instance.ensureUserExists();
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    final url = baseUrl ?? getBackendSocketBase();
    // ignore: avoid_print
    print('Socket: connecting to ' +
        url +
        ' (token: ' +
        (token != null ? 'present' : 'absent') +
        ')');
    _socket = IO.io(
      url,
      IO.OptionBuilder()
          // Allow default transports (polling + websocket) for better compatibility
          .setAuth({'token': token})
          .setTransports(['websocket', 'polling'])
          .setPath('/socket.io/')
          .setTimeout(10000)
          .setExtraHeaders(
              {'Authorization': token != null ? 'Bearer ' + token : ''})
          .disableAutoConnect()
          .build(),
    );
    _socket!.onConnect((_) {
      // Debug: connection established
      // ignore: avoid_print
      print('Socket connected');
      // Flush any pending emits
      if (_pendingEmits.isEmpty) return;
      final toSend = List<Map<String, dynamic>>.from(_pendingEmits);
      _pendingEmits.clear();
      for (final item in toSend) {
        _socket!.emit(item['event'] as String, item['data']);
      }
    });
    _socket!.onDisconnect((_) {
      // ignore: avoid_print
      print('Socket disconnected');
    });
    _socket!.on('message:new',
        (data) => _messageController.add(Map<String, dynamic>.from(data)));
    _socket!.on('typing',
        (data) => _typingController.add(Map<String, dynamic>.from(data)));
    _socket!.on('conversation:updated',
        (data) => _conversationUpdated.add(Map<String, dynamic>.from(data)));
    // WebRTC signaling
    _socket!.on('call:incoming',
        (data) => _callIncoming.add(Map<String, dynamic>.from(data)));
    _socket!.on('call:offer',
        (data) => _callOffer.add(Map<String, dynamic>.from(data)));
    _socket!.on('call:answer',
        (data) => _callAnswer.add(Map<String, dynamic>.from(data)));
    _socket!.on('call:ice-candidate',
        (data) => _callIce.add(Map<String, dynamic>.from(data)));
    _socket!.on('call:ended',
        (data) => _callEnded.add(Map<String, dynamic>.from(data)));
    // Group call events
    _socket!.on('groupcall:started',
        (data) => _gcStarted.add(Map<String, dynamic>.from(data)));
    _socket!.on('groupcall:stopped',
        (data) => _gcStopped.add(Map<String, dynamic>.from(data)));
    _socket!.on('groupcall:participants',
        (data) => _gcParticipants.add(Map<String, dynamic>.from(data)));
    _socket!.on('groupcall:participant-joined',
        (data) => _gcParticipantJoined.add(Map<String, dynamic>.from(data)));
    _socket!.on('groupcall:participant-left',
        (data) => _gcParticipantLeft.add(Map<String, dynamic>.from(data)));
    _socket!.on('groupcall:signal',
        (data) => _gcSignal.add(Map<String, dynamic>.from(data)));
    _socket!.onError((e) {
      // ignore: avoid_print
      print('Socket error: ' + e.toString());
    });
    _socket!.onConnectError((e) {
      // ignore: avoid_print
      print('Socket connect error: ' + e.toString());
    });
    _socket!.connect();
  }

  void _emitOrQueue(String event, dynamic data) {
    if (isConnected) {
      _socket?.emit(event, data);
      return;
    }
    // ignore: avoid_print
    print('Socket not connected. Queueing event: ' + event);
    _pendingEmits.add({'event': event, 'data': data});
    // Best-effort: attempt connect if socket exists but not connected
    if (_socket == null || _socket!.disconnected) {
      // Fire and forget; caller should also ensure connect(), but this helps
      // in cases where join/send are called early.
      connect();
    }
  }

  // --- WebRTC signaling emit helpers ---
  void sendCallInitiate({
    required String toUserId,
    String? conversationId,
    bool isVideo = true,
  }) {
    _emitOrQueue('call:initiate', {
      'toUserId': toUserId,
      'conversationId': conversationId,
      'isVideo': isVideo,
    });
  }

  void sendCallOffer({
    required String toUserId,
    required Map<String, dynamic> sdp,
    String? conversationId,
    bool isVideo = true,
  }) {
    _emitOrQueue('call:offer', {
      'toUserId': toUserId,
      'sdp': sdp,
      'conversationId': conversationId,
      'isVideo': isVideo,
    });
  }

  void sendCallAnswer({
    required String toUserId,
    required Map<String, dynamic> sdp,
    String? conversationId,
  }) {
    _emitOrQueue('call:answer', {
      'toUserId': toUserId,
      'sdp': sdp,
      'conversationId': conversationId,
    });
  }

  void sendCallIceCandidate({
    required String toUserId,
    required Map<String, dynamic> candidate,
  }) {
    _emitOrQueue('call:ice-candidate', {
      'toUserId': toUserId,
      'candidate': candidate,
    });
  }

  void sendCallEnd({
    required String toUserId,
    String? reason,
  }) {
    _emitOrQueue('call:end', {
      'toUserId': toUserId,
      'reason': reason,
    });
  }

  void joinConversation(String conversationId) {
    _emitOrQueue('join:conversation', conversationId);
  }

  void leaveConversation(String conversationId) {
    _emitOrQueue('leave:conversation', conversationId);
  }

  void sendMessage(
      {required String conversationId,
      String? text,
      String? imageUrl,
      String? videoUrl}) {
    _emitOrQueue('message:send', {
      'conversationId': conversationId,
      'text': text,
      'imageUrl': imageUrl,
      'videoUrl': videoUrl,
    });
  }

  void setTyping(String conversationId, bool isTyping) {
    _emitOrQueue('typing', {
      'conversationId': conversationId,
      'isTyping': isTyping,
    });
  }

  // --- Group call emit helpers ---
  void startGroupCall({
    required String conversationId,
    bool isVideo = true,
  }) {
    _emitOrQueue('groupcall:start', {
      'conversationId': conversationId,
      'isVideo': isVideo,
    });
  }

  void stopGroupCall({
    required String conversationId,
    String? reason,
  }) {
    _emitOrQueue('groupcall:stop', {
      'conversationId': conversationId,
      'reason': reason,
    });
  }

  void joinGroupCall({required String conversationId}) {
    _emitOrQueue('groupcall:join', {'conversationId': conversationId});
  }

  void leaveGroupCall({required String conversationId}) {
    _emitOrQueue('groupcall:leave', {'conversationId': conversationId});
  }

  void sendGroupSignal({
    required String conversationId,
    required String toUserId,
    required String kind, // 'offer' | 'answer' | 'ice'
    required Map<String, dynamic> data,
  }) {
    _emitOrQueue('groupcall:signal', {
      'conversationId': conversationId,
      'toUserId': toUserId,
      'kind': kind,
      'data': data,
    });
  }

  void addReaction({
    required String conversationId,
    required String messageId,
    required String emoji,
  }) {
    _emitOrQueue('message:react', {
      'conversationId': conversationId,
      'messageId': messageId,
      'emoji': emoji,
    });
  }

  Future<void> disconnect() async {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}
