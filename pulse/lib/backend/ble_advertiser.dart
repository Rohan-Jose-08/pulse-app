import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// BLE Advertiser for making the device discoverable to nearby devices.
/// Uses platform channels to access native BLE peripheral APIs.
class BleAdvertiser {
  static const MethodChannel _channel =
      MethodChannel('com.pulse.ble/advertiser');

  static bool _isAdvertising = false;

  /// Start advertising with the given service UUID and user ID.
  ///
  /// Android: Uses BluetoothLeAdvertiser
  /// iOS: Uses CBPeripheralManager
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

      final result = await _channel.invokeMethod<bool>('startAdvertising', {
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

  /// Stop BLE advertising.
  static Future<void> stopAdvertising() async {
    if (!_isAdvertising) return;

    try {
      if (kDebugMode) debugPrint('🛑 Stopping BLE advertising...');
      await _channel.invokeMethod('stopAdvertising');
      _isAdvertising = false;
      if (kDebugMode) debugPrint('✅ BLE advertising stopped');
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('⚠️ Error stopping advertising: ${e.message}');
    }
  }

  /// Check if BLE advertising is supported on this device.
  static Future<bool> isSupported() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('isAdvertisingSupported');
      return result ?? false;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Could not check advertising support: $e');
      return false;
    }
  }

  /// Check if currently advertising.
  static bool get isAdvertising => _isAdvertising;
}
