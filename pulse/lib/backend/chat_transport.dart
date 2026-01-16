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

/// Real Bluetooth mesh networking implementation with message relay,
/// routing, duplicate detection, and multi-hop forwarding.
class BluetoothMeshChatTransport implements IChatTransport {
  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  final _typing = StreamController<Map<String, dynamic>>.broadcast();
  final _conversationUpdates =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Local in-memory store: conversationId -> list<message map>
  final Map<String, List<Map<String, dynamic>>> _localStore = {};

  /// Message cache for duplicate detection (messageId -> timestamp)
  final Map<String, int> _messageCache = {};

  /// Routing table: deviceId -> last seen timestamp & signal strength
  final Map<String, _MeshNeighbor> _neighbors = {};

  /// Pending acknowledgments: messageId -> retry count
  final Map<String, int> _pendingAcks = {};

  /// Message relay queue for forwarding
  final List<_MeshPacket> _relayQueue = [];

  bool _started = false;
  bool _scanning = false;
  Timer? _cleanupTimer;
  Timer? _neighborDiscoveryTimer;
  Timer? _relayTimer;

  // Mesh networking constants
  static const int maxHops = 5;
  static const int messageCacheSize = 1000;
  static const int messageCacheTtlSeconds = 300; // 5 minutes
  static const int neighborTimeoutSeconds = 60;
  static const int maxRetries = 3;
  static const int relayDelayMs = 100;

  // UUIDs for service & characteristics
  static final Guid _serviceUuid = Guid("0000fade-0000-1000-8000-00805f9b34fb");
  static final Guid _messageCharUuid =
      Guid("0000fab0-0000-1000-8000-00805f9b34fb");
  static final Guid _typingCharUuid =
      Guid("0000fab1-0000-1000-8000-00805f9b34fb");

  StreamSubscription<List<ScanResult>>? _scanSub;
  final Set<String> _seenPeripheralIds = {};
  final Map<String, BluetoothDevice> _connectedDevices = {};
  final Map<String, StreamSubscription> _deviceSubscriptions = {};

  /// Track RSSI for routing decisions
  final Map<String, int> _deviceRssi = {};

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
    // Start maintenance timers
    _startMaintenanceTimers();
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
    final msgId =
        'bt_${DateTime.now().microsecondsSinceEpoch}_${currentUserUid}';
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

    // Create mesh packet with routing metadata
    final meshPacket = _MeshPacket(
      messageId: msgId,
      originatorId: currentUserUid,
      payload: map,
      packetType: _PacketType.message,
      ttl: maxHops,
      hopCount: 0,
      routePath: [currentUserUid],
    );

    // Broadcast with mesh routing
    _broadcastMeshPacket(meshPacket);
  }

  @override
  void setTyping(String conversationId, bool isTyping) {
    final typingData = {
      'conversationId': conversationId,
      'userId': currentUserUid,
      'isTyping': isTyping,
      'userName': 'You'
    };
    _typing.add(typingData);

    // Create mesh packet for typing indicator (ephemeral, no relay)
    final meshPacket = _MeshPacket(
      messageId: 'typing_${DateTime.now().microsecondsSinceEpoch}',
      originatorId: currentUserUid,
      payload: typingData,
      packetType: _PacketType.typing,
      ttl: 1, // Don't relay typing indicators
      hopCount: 0,
      routePath: [currentUserUid],
    );

    _broadcastMeshPacket(meshPacket);
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
    _cleanupTimer?.cancel();
    _neighborDiscoveryTimer?.cancel();
    _relayTimer?.cancel();

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

    // Clear mesh data structures
    _messageCache.clear();
    _neighbors.clear();
    _pendingAcks.clear();
    _relayQueue.clear();

    await _messages.close();
    await _typing.close();
    await _conversationUpdates.close();
  }

  void _startScanning() {
    if (_scanning) return;
    _scanning = true;
    if (kDebugMode) debugPrint('🔍 Starting BLE mesh scan...');

    FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 0)); // unlimited until stopped
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final device = r.device;
        final rssi = r.rssi;

        // Update RSSI tracking
        _deviceRssi[device.remoteId.str] = rssi;

        if (_seenPeripheralIds.add(device.remoteId.str)) {
          if (kDebugMode) {
            debugPrint(
                '🆕 Discovered mesh node: ${device.remoteId} (RSSI: $rssi)');
          }
          _handleDiscovery(device);
        } else {
          // Update neighbor information for existing devices
          _updateNeighbor(device.remoteId.str, rssi);
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
              c.onValueReceived
                  .listen((data) => _handleIncomingMeshPacket(data));
              if (kDebugMode) {
                debugPrint('📡 Subscribed to mesh characteristic: ${c.uuid}');
              }
            } else if (c.properties.read) {
              final data = await c.read();
              _handleIncomingMeshPacket(data);
            }
          }
        }
      }

      // Register as neighbor
      _updateNeighbor(
          device.remoteId.str, _deviceRssi[device.remoteId.str] ?? -100);
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

  void _handleIncomingMeshPacket(List<int> data) {
    if (data.isEmpty) return;

    try {
      // Decode mesh packet from JSON
      final payload = String.fromCharCodes(data);
      final packetJson = _tryDecodeJson(payload);
      if (packetJson == null) return;

      final meshPacket = _MeshPacket.fromJson(packetJson);

      // Check for duplicate
      if (_isDuplicate(meshPacket.messageId)) {
        if (kDebugMode) {
          debugPrint('⏭️ Ignoring duplicate packet: ${meshPacket.messageId}');
        }
        return;
      }

      // Add to cache
      _cacheMessage(meshPacket.messageId);

      // Check TTL
      if (meshPacket.ttl <= 0) {
        if (kDebugMode) {
          debugPrint('💀 Packet TTL expired: ${meshPacket.messageId}');
        }
        return;
      }

      // Check if packet is in a loop (contains our ID in route path)
      if (meshPacket.routePath.contains(currentUserUid)) {
        if (kDebugMode) {
          debugPrint('🔄 Loop detected in packet: ${meshPacket.messageId}');
        }
        return;
      }

      if (kDebugMode) {
        debugPrint('📥 Received mesh packet: ${meshPacket.messageId} '
            'from ${meshPacket.originatorId}, hop ${meshPacket.hopCount}/${maxHops}');
      }

      // Process packet based on type
      if (meshPacket.packetType == _PacketType.message) {
        final map = meshPacket.payload;
        final cid = map['conversationId'] as String?;
        if (cid != null) {
          _localStore.putIfAbsent(cid, () => []).add(map);
          _messages.add(map);
          _conversationUpdates.add({'id': cid});
        }

        // Send acknowledgment
        _sendAck(meshPacket.messageId, meshPacket.originatorId);
      } else if (meshPacket.packetType == _PacketType.typing) {
        _typing.add(meshPacket.payload);
      } else if (meshPacket.packetType == _PacketType.ack) {
        _handleAck(meshPacket.messageId);
      }

      // Relay to other nodes if TTL allows
      if (meshPacket.ttl > 1 && meshPacket.packetType != _PacketType.typing) {
        _queueForRelay(meshPacket);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error handling mesh packet: $e');
      }
    }
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

  Future<void> _broadcastMeshPacket(_MeshPacket packet,
      {List<String>? excludeDevices}) async {
    // Increment hop count
    packet.hopCount++;
    packet.ttl--;

    // Add ourselves to route path
    if (!packet.routePath.contains(currentUserUid)) {
      packet.routePath.add(currentUserUid);
    }

    final jsonData = jsonEncode(packet.toJson());
    final data = utf8.encode(jsonData);

    if (_connectedDevices.isEmpty) {
      if (kDebugMode) {
        debugPrint('⚠️ No mesh neighbors to broadcast to');
      }
      return;
    }

    if (kDebugMode) {
      debugPrint('📤 Broadcasting mesh packet ${packet.messageId} to '
          '${_connectedDevices.length} neighbor(s), TTL: ${packet.ttl}');
    }

    // Select best neighbors based on signal strength
    final sortedDevices = _selectBestNeighbors(excludeDevices);

    for (final deviceId in sortedDevices) {
      final device = _connectedDevices[deviceId];
      if (device == null) continue;

      try {
        final services = await device.discoverServices();
        final service = services.firstWhere(
          (s) => s.uuid == _serviceUuid,
          orElse: () => throw Exception('Service not found'),
        );

        // Use message characteristic for all mesh packets
        final char = service.characteristics.firstWhere(
          (c) => c.uuid == _messageCharUuid,
          orElse: () => throw Exception('Characteristic not found'),
        );

        if (!char.properties.write && !char.properties.writeWithoutResponse) {
          if (kDebugMode) {
            debugPrint('⚠️ Characteristic not writable on $deviceId');
          }
          continue;
        }

        // Get MTU and chunk if necessary
        final mtu = await device.mtu.first;
        final maxChunkSize = mtu - 3;

        if (data.length <= maxChunkSize) {
          await char.write(data, withoutResponse: true);
          if (kDebugMode) {
            debugPrint(
                '✅ Sent ${data.length} bytes to mesh neighbor $deviceId');
          }
        } else {
          // Send in chunks
          for (int i = 0; i < data.length; i += maxChunkSize) {
            final end = (i + maxChunkSize < data.length)
                ? i + maxChunkSize
                : data.length;
            final chunk = data.sublist(i, end);
            await char.write(chunk, withoutResponse: true);
            await Future.delayed(const Duration(milliseconds: 10));
          }
          if (kDebugMode) {
            debugPrint('✅ Sent ${data.length} bytes in chunks to $deviceId');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ Broadcast error to $deviceId: $e');
        }
        if (e.toString().contains('disconnected') ||
            e.toString().contains('not connected')) {
          _connectedDevices.remove(deviceId);
          _neighbors.remove(deviceId);
        }
      }
    }
  }

  // Mesh networking helper methods

  void _startMaintenanceTimers() {
    // Cleanup expired cache entries
    _cleanupTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _cleanupMessageCache();
      _cleanupStaleNeighbors();
    });

    // Periodic neighbor discovery broadcast
    _neighborDiscoveryTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _broadcastNeighborDiscovery();
    });

    // Process relay queue
    _relayTimer =
        Timer.periodic(const Duration(milliseconds: relayDelayMs), (_) {
      _processRelayQueue();
    });
  }

  void _cleanupMessageCache() {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _messageCache.removeWhere(
        (key, timestamp) => now - timestamp > messageCacheTtlSeconds);

    // Keep cache size under limit
    if (_messageCache.length > messageCacheSize) {
      final sortedEntries = _messageCache.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final toRemove = _messageCache.length - messageCacheSize;
      for (var i = 0; i < toRemove; i++) {
        _messageCache.remove(sortedEntries[i].key);
      }
    }
  }

  void _cleanupStaleNeighbors() {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _neighbors.removeWhere(
        (key, neighbor) => now - neighbor.lastSeen > neighborTimeoutSeconds);

    if (kDebugMode && _neighbors.isNotEmpty) {
      debugPrint('🗺️ Active mesh neighbors: ${_neighbors.length}');
    }
  }

  void _broadcastNeighborDiscovery() {
    final packet = _MeshPacket(
      messageId: 'discovery_${DateTime.now().microsecondsSinceEpoch}',
      originatorId: currentUserUid,
      payload: {
        'type': 'discovery',
        'timestamp': DateTime.now().toIso8601String()
      },
      packetType: _PacketType.discovery,
      ttl: 1,
      hopCount: 0,
      routePath: [currentUserUid],
    );
    _broadcastMeshPacket(packet);
  }

  bool _isDuplicate(String messageId) {
    return _messageCache.containsKey(messageId);
  }

  void _cacheMessage(String messageId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _messageCache[messageId] = timestamp;
  }

  void _updateNeighbor(String deviceId, int rssi) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _neighbors[deviceId] = _MeshNeighbor(
      deviceId: deviceId,
      lastSeen: now,
      rssi: rssi,
    );
  }

  List<String> _selectBestNeighbors(List<String>? excludeDevices) {
    // Select neighbors with best signal strength
    final candidates = _connectedDevices.keys.toList();
    if (excludeDevices != null) {
      candidates.removeWhere((id) => excludeDevices.contains(id));
    }

    // Sort by RSSI (higher is better)
    candidates.sort((a, b) {
      final rssiA = _neighbors[a]?.rssi ?? -100;
      final rssiB = _neighbors[b]?.rssi ?? -100;
      return rssiB.compareTo(rssiA);
    });

    // Limit to top neighbors to avoid broadcast storm
    return candidates.take(3).toList();
  }

  void _queueForRelay(_MeshPacket packet) {
    if (_relayQueue.length < 100) {
      // Limit queue size
      _relayQueue.add(packet);
      if (kDebugMode) {
        debugPrint('📬 Queued packet ${packet.messageId} for relay');
      }
    }
  }

  void _processRelayQueue() {
    if (_relayQueue.isEmpty) return;

    final packet = _relayQueue.removeAt(0);

    if (kDebugMode) {
      debugPrint(
          '🔄 Relaying packet ${packet.messageId} (${_relayQueue.length} remaining)');
    }

    // Create a copy for relay
    final relayPacket = _MeshPacket(
      messageId: packet.messageId,
      originatorId: packet.originatorId,
      payload: packet.payload,
      packetType: packet.packetType,
      ttl: packet.ttl,
      hopCount: packet.hopCount,
      routePath: List.from(packet.routePath),
    );

    _broadcastMeshPacket(relayPacket);
  }

  void _sendAck(String messageId, String originatorId) {
    final ackPacket = _MeshPacket(
      messageId: 'ack_$messageId',
      originatorId: currentUserUid,
      payload: {'ackFor': messageId, 'from': currentUserUid},
      packetType: _PacketType.ack,
      ttl: maxHops,
      hopCount: 0,
      routePath: [currentUserUid],
    );

    _broadcastMeshPacket(ackPacket);
  }

  void _handleAck(String ackMessageId) {
    // Extract original message ID from ack
    if (ackMessageId.startsWith('ack_')) {
      final originalId = ackMessageId.substring(4);
      _pendingAcks.remove(originalId);
      if (kDebugMode) {
        debugPrint('✅ Received ACK for message: $originalId');
      }
    }
  }
}

// Mesh networking data structures

enum _PacketType { message, typing, ack, discovery }

class _MeshPacket {
  final String messageId;
  final String originatorId;
  final Map<String, dynamic> payload;
  final _PacketType packetType;
  int ttl;
  int hopCount;
  final List<String> routePath;

  _MeshPacket({
    required this.messageId,
    required this.originatorId,
    required this.payload,
    required this.packetType,
    required this.ttl,
    required this.hopCount,
    required this.routePath,
  });

  Map<String, dynamic> toJson() => {
        'messageId': messageId,
        'originatorId': originatorId,
        'payload': payload,
        'packetType': packetType.index,
        'ttl': ttl,
        'hopCount': hopCount,
        'routePath': routePath,
      };

  factory _MeshPacket.fromJson(Map<String, dynamic> json) => _MeshPacket(
        messageId: json['messageId'] as String,
        originatorId: json['originatorId'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        packetType: _PacketType.values[json['packetType'] as int],
        ttl: json['ttl'] as int,
        hopCount: json['hopCount'] as int,
        routePath: List<String>.from(json['routePath'] as List),
      );
}

class _MeshNeighbor {
  final String deviceId;
  final int lastSeen;
  final int rssi;

  _MeshNeighbor({
    required this.deviceId,
    required this.lastSeen,
    required this.rssi,
  });
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
