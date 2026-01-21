import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Data received from a BLE Central device writing to our characteristics.
class BleIncomingData {
  final String type; // 'message' or 'typing'
  final List<int> data;
  final String? deviceAddress; // Android: MAC address, iOS: UUID

  BleIncomingData({
    required this.type,
    required this.data,
    this.deviceAddress,
  });
}

/// Connection event from a BLE Central device.
class BleConnectionEvent {
  final String
      event; // 'connected', 'disconnected', 'subscribed', 'unsubscribed'
  final String? deviceAddress;
  final int connectedCount;

  BleConnectionEvent({
    required this.event,
    this.deviceAddress,
    required this.connectedCount,
  });
}

/// BLE Advertiser for making the device discoverable to nearby devices.
///
/// Uses platform channels to access native BLE peripheral APIs:
/// - Android: BluetoothLeAdvertiser + BluetoothGattServer
/// - iOS: CBPeripheralManager
///
/// This class handles bidirectional BLE mesh communication:
/// - Advertising: Makes device discoverable
/// - GATT Server: Receives data from connected Central devices
/// - EventChannel: Streams incoming data to Dart
class BleAdvertiser {
  static const MethodChannel _methodChannel =
      MethodChannel('com.pulse.ble/advertiser');
  static const EventChannel _eventChannel =
      EventChannel('com.pulse.ble/advertiser_events');

  static bool _isAdvertising = false;
  static StreamSubscription? _eventSubscription;

  // Stream controllers for incoming data
  static final _incomingDataController =
      StreamController<BleIncomingData>.broadcast();
  static final _connectionEventController =
      StreamController<BleConnectionEvent>.broadcast();
  static final _bluetoothStateController = StreamController<String>.broadcast();

  /// Stream of incoming mesh data from connected Central devices.
  static Stream<BleIncomingData> get incomingData =>
      _incomingDataController.stream;

  /// Stream of connection events (devices connecting/disconnecting).
  static Stream<BleConnectionEvent> get connectionEvents =>
      _connectionEventController.stream;

  /// Stream of Bluetooth state changes (poweredOn, poweredOff, etc.)
  static Stream<String> get bluetoothState => _bluetoothStateController.stream;

  /// Start advertising with the given service UUID and user ID.
  ///
  /// This will:
  /// 1. Set up a GATT server with message/typing characteristics
  /// 2. Start BLE advertising to be discoverable
  /// 3. Begin listening for incoming data via EventChannel
  static Future<bool> startAdvertising({
    required String serviceUuid,
    required String userId,
  }) async {
    if (_isAdvertising) {
      if (kDebugMode) debugPrint('⚠️ Already advertising');
      return true;
    }

    try {
      if (kDebugMode) {
        debugPrint('📡 Starting BLE advertising...');
        debugPrint('   Service UUID: $serviceUuid');
        debugPrint('   User ID: $userId');
      }

      // Start listening for events before starting advertising
      _startEventListener();

      final result =
          await _methodChannel.invokeMethod<bool>('startAdvertising', {
        'serviceUuid': serviceUuid,
        'userId': userId,
      });

      _isAdvertising = result ?? false;

      if (kDebugMode) {
        if (_isAdvertising) {
          debugPrint('✅ BLE advertising started successfully');
        } else {
          debugPrint('❌ Failed to start BLE advertising');
        }
      }

      return _isAdvertising;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('❌ BLE advertising error: ${e.message}');
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Unexpected advertising error: $e');
      }
      return false;
    }
  }

  /// Stop BLE advertising and GATT server.
  static Future<void> stopAdvertising() async {
    if (!_isAdvertising) return;

    try {
      if (kDebugMode) debugPrint('🛑 Stopping BLE advertising...');
      await _methodChannel.invokeMethod('stopAdvertising');
      _isAdvertising = false;
      _stopEventListener();
      if (kDebugMode) debugPrint('✅ BLE advertising stopped');
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('⚠️ Error stopping advertising: ${e.message}');
    }
  }

  /// Check if BLE advertising is supported on this device.
  static Future<bool> isSupported() async {
    try {
      final result =
          await _methodChannel.invokeMethod<bool>('isAdvertisingSupported');
      return result ?? false;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Could not check advertising support: $e');
      return false;
    }
  }

  /// Send data to all connected Central devices via GATT notifications.
  ///
  /// [data] - The bytes to send
  /// [characteristicType] - 'message' or 'typing'
  static Future<bool> sendToConnectedDevices({
    required List<int> data,
    String characteristicType = 'message',
  }) async {
    if (!_isAdvertising) {
      if (kDebugMode) debugPrint('⚠️ Not advertising, cannot send data');
      return false;
    }

    try {
      final result =
          await _methodChannel.invokeMethod<bool>('sendToConnectedDevices', {
        'data': Uint8List.fromList(data),
        'characteristicType': characteristicType,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      if (kDebugMode)
        debugPrint('⚠️ Error sending to connected devices: ${e.message}');
      return false;
    }
  }

  /// Get the number of connected Central devices.
  static Future<int> getConnectedDeviceCount() async {
    try {
      final result =
          await _methodChannel.invokeMethod<int>('getConnectedDeviceCount');
      return result ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Check if currently advertising.
  static bool get isAdvertising => _isAdvertising;

  /// Start listening for events from native platform.
  static void _startEventListener() {
    _eventSubscription?.cancel();
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          _handleNativeEvent(Map<String, dynamic>.from(event));
        }
      },
      onError: (dynamic error) {
        if (kDebugMode) {
          debugPrint('❌ BLE EventChannel error: $error');
        }
      },
    );
    if (kDebugMode) {
      debugPrint('📡 BLE EventChannel listener started');
    }
  }

  /// Stop listening for events.
  static void _stopEventListener() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  /// Handle events from native platform.
  static void _handleNativeEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;

    switch (type) {
      case 'data':
        // Incoming data from a connected Central device
        final charType = event['characteristicType'] as String? ?? 'message';
        final dataList = event['data'] as List<dynamic>?;
        final deviceAddress =
            event['deviceAddress'] as String? ?? event['centralId'] as String?;

        if (dataList != null && dataList.isNotEmpty) {
          final data = dataList.map((e) => (e as num).toInt()).toList();
          if (kDebugMode) {
            debugPrint(
                '📥 BLE incoming data: ${data.length} bytes from $deviceAddress ($charType)');
          }
          _incomingDataController.add(BleIncomingData(
            type: charType,
            data: data,
            deviceAddress: deviceAddress,
          ));
        }
        break;

      case 'connection':
        // Connection event
        final eventType = event['event'] as String? ?? 'unknown';
        final deviceAddress =
            event['deviceAddress'] as String? ?? event['centralId'] as String?;
        final connectedCount = event['connectedCount'] as int? ?? 0;

        if (kDebugMode) {
          debugPrint(
              '🔗 BLE connection event: $eventType, device: $deviceAddress, count: $connectedCount');
        }
        _connectionEventController.add(BleConnectionEvent(
          event: eventType,
          deviceAddress: deviceAddress,
          connectedCount: connectedCount,
        ));
        break;

      case 'bluetoothState':
        // Bluetooth state change
        final state = event['state'] as String? ?? 'unknown';
        if (kDebugMode) {
          debugPrint('📱 Bluetooth state: $state');
        }
        _bluetoothStateController.add(state);
        break;

      default:
        if (kDebugMode) {
          debugPrint('⚠️ Unknown BLE event type: $type');
        }
    }
  }

  /// Dispose resources (call when app terminates).
  static Future<void> dispose() async {
    await stopAdvertising();
    await _incomingDataController.close();
    await _connectionEventController.close();
    await _bluetoothStateController.close();
  }
}
