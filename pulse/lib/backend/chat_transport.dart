import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import '../auth/firebase_auth/auth_util.dart';
import 'api_service.dart';
import 'socket_service.dart';
import 'ble_advertiser.dart';

/// Transport modes supported for chat.
enum ChatTransportMode { network, bluetooth }

/// Base transport contract.
abstract class IChatTransport {
  Stream<Map<String, dynamic>> get messages; // raw socket-like events
  Stream<Map<String, dynamic>> get typing;
  Stream<Map<String, dynamic>> get conversationUpdates;

  Future<void> ensureConnected();
  void joinConversation(String id);
  void leaveConversation(String id);
  void sendMessage(
      {required String conversationId,
      String? text,
      String? imageUrl,
      String? videoUrl,
      String? repliedToId});
  void setTyping(String conversationId, bool isTyping);
  void addReaction(
      {required String conversationId,
      required String messageId,
      required String emoji});
  Future<void> dispose();
}

/// Wrapper over existing SocketService (network / wifi / mobile data).
class NetworkChatTransport implements IChatTransport {
  final _socket = SocketService.instance;

  @override
  Stream<Map<String, dynamic>> get messages => _socket.messages;
  @override
  Stream<Map<String, dynamic>> get typing => _socket.typing;
  @override
  Stream<Map<String, dynamic>> get conversationUpdates =>
      _socket.conversationUpdates;

  @override
  Future<void> ensureConnected() async => _socket.connect();

  @override
  void joinConversation(String id) => _socket.joinConversation(id);

  @override
  void leaveConversation(String id) => _socket.leaveConversation(id);

  @override
  void sendMessage(
          {required String conversationId,
          String? text,
          String? imageUrl,
          String? videoUrl,
          String? repliedToId}) =>
      _socket.sendMessage(
          conversationId: conversationId,
          text: text,
          imageUrl: imageUrl,
          videoUrl: videoUrl,
          repliedToId: repliedToId);

  @override
  void setTyping(String conversationId, bool isTyping) =>
      _socket.setTyping(conversationId, isTyping);

  @override
  void addReaction(
          {required String conversationId,
          required String messageId,
          required String emoji}) =>
      _socket.addReaction(
          conversationId: conversationId, messageId: messageId, emoji: emoji);

  @override
  Future<void> dispose() async {/* no-op */}
}

/// Experimental in-memory Bluetooth mesh stub.
/// NOTE: Real Bluetooth mesh implementation would require a dedicated plugin,
/// background task handling, advertising, scanning & message relay logic.
/// This stub simulates offline messaging locally so UI integration works.
class BluetoothMeshChatTransport implements IChatTransport {
  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  final _typing = StreamController<Map<String, dynamic>>.broadcast();
  final _conversationUpdates =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Local in-memory store: conversationId -> list<message map>
  final Map<String, List<Map<String, dynamic>>> _localStore = {};

  bool _started = false;
  bool _scanning = false;

  // UUIDs for service & characteristics (randomly generated once; replace with constants if formalizing)
  // Using 128-bit custom UUIDs for a simple GATT fallback (not full mesh).
  static final Guid _serviceUuid = Guid("0000fade-0000-1000-8000-00805f9b34fb");
  static final Guid _messageCharUuid =
      Guid("0000fab0-0000-1000-8000-00805f9b34fb");
  static final Guid _typingCharUuid =
      Guid("0000fab1-0000-1000-8000-00805f9b34fb");

  StreamSubscription<List<ScanResult>>? _scanSub;
  final Set<String> _seenPeripheralIds = {};
  final Map<String, BluetoothDevice> _connectedDevices = {};
  final Map<String, StreamSubscription> _deviceSubscriptions = {};

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;
  @override
  Stream<Map<String, dynamic>> get typing => _typing.stream;
  @override
  Stream<Map<String, dynamic>> get conversationUpdates =>
      _conversationUpdates.stream;

  @override
  Future<void> ensureConnected() async {
    if (_started) return;
    _started = true;
    await _ensurePermissions();
    // Kick off scanning for nearby devices
    _startScanning();
    // Start advertising our presence
    await _startAdvertising();
  }

  @override
  void joinConversation(String id) {
    // No-op for stub.
  }

  @override
  void leaveConversation(String id) {
    // No-op
  }

  @override
  void sendMessage(
      {required String conversationId,
      String? text,
      String? imageUrl,
      String? videoUrl,
      String? repliedToId}) {
    final msgId = 'bt_${DateTime.now().microsecondsSinceEpoch}';
    final map = <String, dynamic>{
      'id': msgId,
      'conversationId': conversationId,
      'senderId': currentUserUid,
      'createdAt': DateTime.now().toIso8601String(),
      'text': text,
      'imageUrl': imageUrl,
      'videoUrl': videoUrl,
      'reactions': <String, List<String>>{},
      'senderName': null,
      'senderPhotoUrl': null,
      'isSystemMessage': false,
      'repliedTo': repliedToId,
    };
    _localStore.putIfAbsent(conversationId, () => []).add(map);
    _messages.add(map);
    _conversationUpdates.add({'id': conversationId});
    // Real implementation: broadcast over BLE advertisement or GATT.
    _broadcastPacket(0, jsonEncode(map));
  }

  @override
  void setTyping(String conversationId, bool isTyping) {
    _typing.add({
      'conversationId': conversationId,
      'userId': currentUserUid,
      'isTyping': isTyping,
      'userName': 'You'
    });
    // Real implementation: broadcast ephemeral typing state.
    _broadcastPacket(
        1,
        jsonEncode({
          'conversationId': conversationId,
          'userId': currentUserUid,
          'isTyping': isTyping,
        }));
  }

  @override
  void addReaction(
      {required String conversationId,
      required String messageId,
      required String emoji}) {
    final list = _localStore[conversationId];
    if (list == null) return;
    final idx = list.indexWhere((m) => m['id'] == messageId);
    if (idx == -1) return;
    final reactions = (list[idx]['reactions'] as Map<String, dynamic>? ?? {});
    final users = (reactions[emoji] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    if (users.contains(currentUserUid)) {
      users.remove(currentUserUid);
    } else {
      users.add(currentUserUid);
    }
    reactions[emoji] = users;
    list[idx]['reactions'] = reactions;
    _messages.add(Map<String, dynamic>.from(list[idx]));
  }

  List<Map<String, dynamic>> listLocalMessages(String conversationId) =>
      List<Map<String, dynamic>>.from(_localStore[conversationId] ?? const []);

  @override
  Future<void> dispose() async {
    await _scanSub?.cancel();

    // Stop advertising
    await BleAdvertiser.stopAdvertising();

    // Cancel all device subscriptions
    for (final sub in _deviceSubscriptions.values) {
      await sub.cancel();
    }
    _deviceSubscriptions.clear();

    // Disconnect all devices
    for (final device in _connectedDevices.values) {
      try {
        await device.disconnect();
      } catch (e) {
        if (kDebugMode) debugPrint('Error disconnecting device: $e');
      }
    }
    _connectedDevices.clear();

    // Stop scanning
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    await _messages.close();
    await _typing.close();
    await _conversationUpdates.close();
  }

  void _startScanning() {
    if (_scanning) return;
    _scanning = true;
    if (kDebugMode) debugPrint('🔍 Starting BLE scan...');

    // Ensure bluetooth on & permissions; errors ignored for prototype.
    FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 0)); // unlimited until stopped
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final device = r.device;
        if (_seenPeripheralIds.add(device.remoteId.str)) {
          // First time seeing device: attempt to connect & discover services lazily.
          if (kDebugMode) {
            debugPrint(
                '🆕 Discovered new device: ${device.remoteId} (${device.platformName})');
          }
          _handleDiscovery(device);
        }
      }
    });
  }

  Future<void> _startAdvertising() async {
    // Check if advertising is supported
    final isSupported = await BleAdvertiser.isSupported();

    if (!isSupported) {
      if (kDebugMode) {
        debugPrint('⚠️ BLE Advertising not supported on this device');
      }
      return;
    }

    // Start advertising with our service UUID and current user ID
    final success = await BleAdvertiser.startAdvertising(
      serviceUuid: _serviceUuid.toString(),
      userId: currentUserUid,
    );

    if (success) {
      if (kDebugMode) {
        debugPrint('✅ BLE Advertising started - device is now discoverable');
      }
    } else {
      if (kDebugMode) {
        debugPrint('❌ Failed to start BLE advertising');
      }
    }
  }

  Future<void> _handleDiscovery(BluetoothDevice device) async {
    try {
      // Check if already connected
      if (_connectedDevices.containsKey(device.remoteId.str)) {
        return;
      }

      if (kDebugMode) {
        debugPrint('🔵 Connecting to device: ${device.remoteId}');
      }

      await device.connect(timeout: const Duration(seconds: 8));

      // Track connection
      _connectedDevices[device.remoteId.str] = device;

      // Listen for disconnections
      final sub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          if (kDebugMode) {
            debugPrint('🔴 Device disconnected: ${device.remoteId}');
          }
          _connectedDevices.remove(device.remoteId.str);
          _seenPeripheralIds.remove(device.remoteId.str);
          _deviceSubscriptions[device.remoteId.str]?.cancel();
          _deviceSubscriptions.remove(device.remoteId.str);
        }
      });
      _deviceSubscriptions[device.remoteId.str] = sub;

      final services = await device.discoverServices();
      final matching = services.where((s) => s.uuid == _serviceUuid);
      if (matching.isEmpty) {
        if (kDebugMode) {
          debugPrint('⚠️ Device does not have our service UUID');
        }
        await device.disconnect();
        return;
      }

      if (kDebugMode) {
        debugPrint('✅ Found matching service, setting up characteristics');
      }

      for (final service in matching) {
        for (final c in service.characteristics) {
          if (c.uuid == _messageCharUuid || c.uuid == _typingCharUuid) {
            if (c.properties.notify) {
              await c.setNotifyValue(true);
              c.onValueReceived.listen((data) => _handleIncomingPacket(data));
              if (kDebugMode) {
                debugPrint('📡 Subscribed to characteristic: ${c.uuid}');
              }
            } else if (c.properties.read) {
              // opportunistic read
              final data = await c.read();
              _handleIncomingPacket(data);
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ BLE discovery error: $e');
      }
      // Clean up on error
      _connectedDevices.remove(device.remoteId.str);
      _seenPeripheralIds.remove(device.remoteId.str);
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  void _handleIncomingPacket(List<int> data) {
    // Very naive framing: first byte = type (0=message,1=typing)
    if (data.isEmpty) return;
    final type = data.first;
    try {
      final payload = String.fromCharCodes(data.skip(1));
      if (type == 0) {
        // Expect JSON like {conversationId:..., id:..., text:...}
        final map = _tryDecodeJson(payload);
        if (map != null) {
          // Insert if new
          final cid = map['conversationId'] as String?;
          if (cid != null) {
            _localStore.putIfAbsent(cid, () => []).add(map);
            _messages.add(map);
            _conversationUpdates.add({'id': cid});
          }
        }
      } else if (type == 1) {
        final map = _tryDecodeJson(payload);
        if (map != null) _typing.add(map);
      }
    } catch (_) {/* ignore */}
  }

  Map<String, dynamic>? _tryDecodeJson(String raw) {
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensurePermissions() async {
    // Request needed permissions (Android 12+). Ignore result for prototype; add proper UX later.
    final perms = <Permission>[
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse, // some stacks still require location
    ];
    await perms.request();
  }

  Future<void> _broadcastPacket(int type, String json) async {
    final data = <int>[type, ...utf8.encode(json)];

    if (_connectedDevices.isEmpty) {
      if (kDebugMode) {
        debugPrint(
            '⚠️ No connected devices to broadcast to (${data.length} bytes)');
      }
      return;
    }

    if (kDebugMode) {
      debugPrint(
          '📤 Broadcasting ${data.length} bytes to ${_connectedDevices.length} device(s)');
    }

    final devicesCopy = List<BluetoothDevice>.from(_connectedDevices.values);

    for (final device in devicesCopy) {
      try {
        // Discover services if not already done
        final services = await device.discoverServices();
        final service = services.firstWhere(
          (s) => s.uuid == _serviceUuid,
          orElse: () => throw Exception('Service not found'),
        );

        // Select characteristic based on packet type
        final targetCharUuid = type == 0 ? _messageCharUuid : _typingCharUuid;
        final char = service.characteristics.firstWhere(
          (c) => c.uuid == targetCharUuid,
          orElse: () => throw Exception('Characteristic not found'),
        );

        if (!char.properties.write && !char.properties.writeWithoutResponse) {
          if (kDebugMode) {
            debugPrint('⚠️ Characteristic not writable on ${device.remoteId}');
          }
          continue;
        }

        // BLE has MTU limitations (default 23 bytes, up to 512 with negotiation)
        // Split data into chunks if needed
        final mtu = await device.mtu.first;
        final maxChunkSize = mtu - 3; // Account for ATT overhead

        if (data.length <= maxChunkSize) {
          // Send in one go
          await char.write(data, withoutResponse: true);
          if (kDebugMode) {
            debugPrint('✅ Sent ${data.length} bytes to ${device.remoteId}');
          }
        } else {
          // Send in chunks
          if (kDebugMode) {
            debugPrint('📦 Chunking ${data.length} bytes (MTU: $mtu)');
          }
          for (int i = 0; i < data.length; i += maxChunkSize) {
            final end = (i + maxChunkSize < data.length)
                ? i + maxChunkSize
                : data.length;
            final chunk = data.sublist(i, end);
            await char.write(chunk, withoutResponse: true);
            // Small delay between chunks to avoid overwhelming receiver
            await Future.delayed(const Duration(milliseconds: 10));
          }
          if (kDebugMode) {
            debugPrint(
                '✅ Sent ${data.length} bytes in chunks to ${device.remoteId}');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ Broadcast error to ${device.remoteId}: $e');
        }
        // If device is unreachable, remove from connected list
        if (e.toString().contains('disconnected') ||
            e.toString().contains('not connected')) {
          _connectedDevices.remove(device.remoteId.str);
        }
      }
    }
  }
}

/// Manager & facade for switching transports at runtime.
class ChatTransportManager extends ChangeNotifier {
  ChatTransportManager._();
  static final ChatTransportManager instance = ChatTransportManager._();

  final _network = NetworkChatTransport();
  final _bluetooth = BluetoothMeshChatTransport();
  ChatTransportMode _mode = ChatTransportMode.network;

  ChatTransportMode get mode => _mode;
  set mode(ChatTransportMode m) {
    if (m == _mode) return;
    _mode = m;
    notifyListeners();
    ensureConnected();
  }

  IChatTransport get active =>
      _mode == ChatTransportMode.network ? _network : _bluetooth;

  IChatTransport transportFor(ChatTransportMode m) =>
      m == ChatTransportMode.network ? _network : _bluetooth;

  Future<void> ensureConnected() async => active.ensureConnected();

  /// For bluetooth mode we don't have server history.
  Future<List<Map<String, dynamic>>> initialMessages(
      String conversationId) async {
    if (mode == ChatTransportMode.network) {
      final res = await ApiService.instance.listMessages(conversationId);
      if (res == null) return [];
      List<dynamic>? rawList;
      // Common shapes: { messages: [...] }, { data: [...] }, direct list (handled by ApiService returning Map or List)
      if (res['messages'] is List) {
        rawList = res['messages'] as List;
      } else if (res['data'] is List) {
        rawList = res['data'] as List;
      } else if (res['items'] is List) {
        rawList = res['items'] as List;
      }
      if (rawList == null) {
        // If backend returned a list but ApiService wrapped? Attempt to detect nested list under key 'list'
        if (res.length == 1 && res.values.first is List) {
          rawList = res.values.first as List;
        }
      }
      if (rawList == null) return [];
      return rawList
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return _bluetooth.listLocalMessages(conversationId);
  }
}
