import 'package:flutter/foundation.dart';

// Optional manual override. Set to something like 'http://192.168.1.10:3000'
// when running on a physical device and your backend is on your LAN.
// You can also provide this via --dart-define=BACKEND_BASE=... at build/run time.
const String _backendBaseEnv =
    String.fromEnvironment('BACKEND_BASE', defaultValue: '');
final String? backendBaseOverride =
    _backendBaseEnv.isEmpty ? null : _backendBaseEnv;

String _detectBackendOrigin() {
  if (backendBaseOverride != null && backendBaseOverride!.isNotEmpty) {
    return backendBaseOverride!;
  }

  if (kIsWeb) {
    // For web dev, the backend typically runs on localhost
    return 'http://localhost:3000';
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      // Android emulator maps host loopback to 10.0.2.2
      return 'http://192.168.1.10:3000';
    default:
      // iOS simulator, desktop platforms
      return 'http://localhost:3000';
  }
}

String getBackendHttpBase() {
  return _detectBackendOrigin() + '/api';
}

String getBackendSocketBase() {
  return _detectBackendOrigin();
}
