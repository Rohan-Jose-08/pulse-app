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

  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  Stream<Map<String, dynamic>> get typing => _typingController.stream;
  Stream<Map<String, dynamic>> get conversationUpdates =>
      _conversationUpdated.stream;

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
