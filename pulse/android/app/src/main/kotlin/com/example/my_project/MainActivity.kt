package com.example.pulse

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.pulse.ble/advertiser"
    private var bleAdvertiserPlugin: BleAdvertiserPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Register BLE Advertiser plugin
        bleAdvertiserPlugin = BleAdvertiserPlugin(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(bleAdvertiserPlugin)
    }

    override fun onDestroy() {
        bleAdvertiserPlugin?.cleanup()
        super.onDestroy()
    }
}

