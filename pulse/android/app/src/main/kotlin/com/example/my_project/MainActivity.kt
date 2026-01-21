package com.example.pulse

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val METHOD_CHANNEL = "com.pulse.ble/advertiser"
    private val EVENT_CHANNEL = "com.pulse.ble/advertiser_events"
    private var bleAdvertiserPlugin: BleAdvertiserPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Create BLE Advertiser plugin instance
        bleAdvertiserPlugin = BleAdvertiserPlugin(this)
        
        // Register MethodChannel for commands (start/stop advertising, send data)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler(bleAdvertiserPlugin)
        
        // Register EventChannel for incoming BLE data from connected Central devices
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(bleAdvertiserPlugin)
    }

    override fun onDestroy() {
        bleAdvertiserPlugin?.cleanup()
        super.onDestroy()
    }
}

