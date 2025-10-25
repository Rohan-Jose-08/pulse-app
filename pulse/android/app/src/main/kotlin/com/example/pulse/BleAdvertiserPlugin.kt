package com.example.pulse

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.os.ParcelUuid
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class BleAdvertiserPlugin(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        private const val TAG = "BleAdvertiser"
    }

    private var bluetoothLeAdvertiser: BluetoothLeAdvertiser? = null
    private var advertiseCallback: AdvertiseCallback? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAdvertisingSupported" -> {
                result.success(isAdvertisingSupported())
            }
            "startAdvertising" -> {
                val serviceUuid = call.argument<String>("serviceUuid")
                val userId = call.argument<String>("userId")
                
                if (serviceUuid == null || userId == null) {
                    result.error("INVALID_ARGS", "serviceUuid and userId are required", null)
                    return
                }
                
                startAdvertising(serviceUuid, userId, result)
            }
            "stopAdvertising" -> {
                stopAdvertising()
                result.success(null)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun isAdvertisingSupported(): Boolean {
        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val bluetoothAdapter = bluetoothManager?.adapter
        return bluetoothAdapter?.bluetoothLeAdvertiser != null &&
               bluetoothAdapter.isMultipleAdvertisementSupported
    }

    private fun startAdvertising(serviceUuid: String, userId: String, result: MethodChannel.Result) {
        try {
            val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val bluetoothAdapter = bluetoothManager?.adapter

            if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled) {
                result.error("BT_DISABLED", "Bluetooth is not enabled", null)
                return
            }

            bluetoothLeAdvertiser = bluetoothAdapter.bluetoothLeAdvertiser
            if (bluetoothLeAdvertiser == null) {
                result.error("NOT_SUPPORTED", "BLE advertising not supported on this device", null)
                return
            }

            // Parse UUID
            val uuid = try {
                UUID.fromString(serviceUuid)
            } catch (e: IllegalArgumentException) {
                result.error("INVALID_UUID", "Invalid service UUID format", null)
                return
            }

            // Configure advertising settings
            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setConnectable(true)
                .setTimeout(0) // Advertise indefinitely
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .build()

            // Configure advertising data
            val data = AdvertiseData.Builder()
                .setIncludeDeviceName(false)
                .addServiceUuid(ParcelUuid(uuid))
                .build()

            // Configure scan response (optional, can include user ID)
            val scanResponse = AdvertiseData.Builder()
                .setIncludeDeviceName(true)
                .build()

            // Create callback
            advertiseCallback = object : AdvertiseCallback() {
                override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                    Log.d(TAG, "BLE advertising started successfully")
                    result.success(true)
                }

                override fun onStartFailure(errorCode: Int) {
                    val errorMsg = when (errorCode) {
                        ADVERTISE_FAILED_DATA_TOO_LARGE -> "Data too large"
                        ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "Too many advertisers"
                        ADVERTISE_FAILED_ALREADY_STARTED -> "Already started"
                        ADVERTISE_FAILED_INTERNAL_ERROR -> "Internal error"
                        ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "Feature unsupported"
                        else -> "Unknown error: $errorCode"
                    }
                    Log.e(TAG, "BLE advertising failed: $errorMsg")
                    result.error("ADVERTISE_FAILED", errorMsg, errorCode)
                }
            }

            // Start advertising
            bluetoothLeAdvertiser?.startAdvertising(settings, data, scanResponse, advertiseCallback!!)

        } catch (e: Exception) {
            Log.e(TAG, "Error starting BLE advertising", e)
            result.error("EXCEPTION", e.message, null)
        }
    }

    private fun stopAdvertising() {
        try {
            advertiseCallback?.let { callback ->
                bluetoothLeAdvertiser?.stopAdvertising(callback)
                Log.d(TAG, "BLE advertising stopped")
            }
            advertiseCallback = null
            bluetoothLeAdvertiser = null
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping BLE advertising", e)
        }
    }

    fun cleanup() {
        stopAdvertising()
    }
}
