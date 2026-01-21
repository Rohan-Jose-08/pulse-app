package com.example.pulse

import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/**
 * Complete BLE Peripheral Plugin for Pulse Mesh Networking.
 * 
 * This plugin provides:
 * - BLE Advertising (to be discoverable)
 * - GATT Server (to receive incoming data from Central devices)
 * - EventChannel (to stream incoming data to Dart)
 */
class BleAdvertiserPlugin(private val context: Context) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        private const val TAG = "BleAdvertiser"
        
        // Service and Characteristic UUIDs - must match iOS and Dart code
        val SERVICE_UUID: UUID = UUID.fromString("0000FADE-0000-1000-8000-00805F9B34FB")
        val MESSAGE_CHAR_UUID: UUID = UUID.fromString("0000FAB0-0000-1000-8000-00805F9B34FB")
        val TYPING_CHAR_UUID: UUID = UUID.fromString("0000FAB1-0000-1000-8000-00805F9B34FB")
    }

    private var bluetoothManager: BluetoothManager? = null
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bluetoothLeAdvertiser: BluetoothLeAdvertiser? = null
    private var bluetoothGattServer: BluetoothGattServer? = null
    private var advertiseCallback: AdvertiseCallback? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val connectedDevices = mutableSetOf<BluetoothDevice>()
    
    // Characteristics references for notifications
    private var messageCharacteristic: BluetoothGattCharacteristic? = null
    private var typingCharacteristic: BluetoothGattCharacteristic? = null

    // ==================== MethodChannel Handler ====================

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
            "sendToConnectedDevices" -> {
                val data = call.argument<ByteArray>("data")
                val charType = call.argument<String>("characteristicType") ?: "message"
                if (data != null) {
                    sendToConnectedDevices(data, charType)
                    result.success(true)
                } else {
                    result.error("INVALID_ARGS", "data is required", null)
                }
            }
            "getConnectedDeviceCount" -> {
                result.success(connectedDevices.size)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    // ==================== EventChannel StreamHandler ====================

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        Log.d(TAG, "EventChannel: Dart listener attached")
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        Log.d(TAG, "EventChannel: Dart listener detached")
        eventSink = null
    }

    // ==================== BLE Advertising ====================

    private fun isAdvertisingSupported(): Boolean {
        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val bluetoothAdapter = bluetoothManager?.adapter
        return bluetoothAdapter?.bluetoothLeAdvertiser != null &&
               bluetoothAdapter.isMultipleAdvertisementSupported
    }

    private fun startAdvertising(serviceUuid: String, userId: String, result: MethodChannel.Result) {
        try {
            bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            bluetoothAdapter = bluetoothManager?.adapter

            if (bluetoothAdapter == null || !bluetoothAdapter!!.isEnabled) {
                result.error("BT_DISABLED", "Bluetooth is not enabled", null)
                return
            }

            bluetoothLeAdvertiser = bluetoothAdapter!!.bluetoothLeAdvertiser
            if (bluetoothLeAdvertiser == null) {
                result.error("NOT_SUPPORTED", "BLE advertising not supported on this device", null)
                return
            }

            // Parse UUID (use our standard service UUID)
            val uuid = try {
                UUID.fromString(serviceUuid)
            } catch (e: IllegalArgumentException) {
                result.error("INVALID_UUID", "Invalid service UUID format", null)
                return
            }

            // First, setup the GATT server
            setupGattServer()

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

            // Configure scan response
            val scanResponse = AdvertiseData.Builder()
                .setIncludeDeviceName(true)
                .build()

            // Create callback
            advertiseCallback = object : AdvertiseCallback() {
                override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                    Log.d(TAG, "✅ BLE advertising started successfully")
                    mainHandler.post { result.success(true) }
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
                    Log.e(TAG, "❌ BLE advertising failed: $errorMsg")
                    mainHandler.post { result.error("ADVERTISE_FAILED", errorMsg, errorCode) }
                }
            }

            // Start advertising
            bluetoothLeAdvertiser?.startAdvertising(settings, data, scanResponse, advertiseCallback!!)

        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception - missing Bluetooth permissions", e)
            result.error("PERMISSION_DENIED", "Bluetooth permissions not granted", null)
        } catch (e: Exception) {
            Log.e(TAG, "Error starting BLE advertising", e)
            result.error("EXCEPTION", e.message, null)
        }
    }

    private fun stopAdvertising() {
        try {
            advertiseCallback?.let { callback ->
                bluetoothLeAdvertiser?.stopAdvertising(callback)
                Log.d(TAG, "🛑 BLE advertising stopped")
            }
            advertiseCallback = null
            bluetoothLeAdvertiser = null
            
            // Close GATT server
            bluetoothGattServer?.close()
            bluetoothGattServer = null
            connectedDevices.clear()
            
        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception stopping advertising", e)
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping BLE advertising", e)
        }
    }

    // ==================== GATT Server ====================

    private fun setupGattServer() {
        try {
            bluetoothGattServer = bluetoothManager?.openGattServer(context, gattServerCallback)
            
            if (bluetoothGattServer == null) {
                Log.e(TAG, "❌ Failed to open GATT server")
                return
            }

            // Create the service
            val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)

            // Create message characteristic (read, write, notify)
            messageCharacteristic = BluetoothGattCharacteristic(
                MESSAGE_CHAR_UUID,
                BluetoothGattCharacteristic.PROPERTY_READ or
                BluetoothGattCharacteristic.PROPERTY_WRITE or
                BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE or
                BluetoothGattCharacteristic.PROPERTY_NOTIFY,
                BluetoothGattCharacteristic.PERMISSION_READ or
                BluetoothGattCharacteristic.PERMISSION_WRITE
            )
            
            // Add Client Characteristic Configuration Descriptor for notifications
            val messageDescriptor = BluetoothGattDescriptor(
                UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"), // CCCD UUID
                BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE
            )
            messageCharacteristic!!.addDescriptor(messageDescriptor)
            service.addCharacteristic(messageCharacteristic!!)

            // Create typing characteristic (read, write, notify)
            typingCharacteristic = BluetoothGattCharacteristic(
                TYPING_CHAR_UUID,
                BluetoothGattCharacteristic.PROPERTY_READ or
                BluetoothGattCharacteristic.PROPERTY_WRITE or
                BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE or
                BluetoothGattCharacteristic.PROPERTY_NOTIFY,
                BluetoothGattCharacteristic.PERMISSION_READ or
                BluetoothGattCharacteristic.PERMISSION_WRITE
            )
            
            val typingDescriptor = BluetoothGattDescriptor(
                UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"),
                BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE
            )
            typingCharacteristic!!.addDescriptor(typingDescriptor)
            service.addCharacteristic(typingCharacteristic!!)

            // Add service to GATT server
            val added = bluetoothGattServer?.addService(service) ?: false
            if (added) {
                Log.d(TAG, "✅ GATT service added successfully")
            } else {
                Log.e(TAG, "❌ Failed to add GATT service")
            }

        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception setting up GATT server", e)
        } catch (e: Exception) {
            Log.e(TAG, "Error setting up GATT server", e)
        }
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        
        override fun onConnectionStateChange(device: BluetoothDevice?, status: Int, newState: Int) {
            super.onConnectionStateChange(device, status, newState)
            try {
                if (device == null) return
                
                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> {
                        connectedDevices.add(device)
                        Log.d(TAG, "🔵 Device connected: ${device.address} (${connectedDevices.size} total)")
                        sendEventToDart(mapOf(
                            "type" to "connection",
                            "event" to "connected",
                            "deviceAddress" to device.address,
                            "connectedCount" to connectedDevices.size
                        ))
                    }
                    BluetoothProfile.STATE_DISCONNECTED -> {
                        connectedDevices.remove(device)
                        Log.d(TAG, "🔴 Device disconnected: ${device.address} (${connectedDevices.size} remaining)")
                        sendEventToDart(mapOf(
                            "type" to "connection",
                            "event" to "disconnected",
                            "deviceAddress" to device.address,
                            "connectedCount" to connectedDevices.size
                        ))
                    }
                }
            } catch (e: SecurityException) {
                Log.e(TAG, "Security exception in connection state change", e)
            }
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice?,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic?
        ) {
            super.onCharacteristicReadRequest(device, requestId, offset, characteristic)
            try {
                Log.d(TAG, "📖 Read request from ${device?.address} for ${characteristic?.uuid}")
                bluetoothGattServer?.sendResponse(
                    device,
                    requestId,
                    BluetoothGatt.GATT_SUCCESS,
                    offset,
                    characteristic?.value ?: ByteArray(0)
                )
            } catch (e: SecurityException) {
                Log.e(TAG, "Security exception handling read request", e)
            }
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice?,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic?,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?
        ) {
            super.onCharacteristicWriteRequest(device, requestId, characteristic, preparedWrite, responseNeeded, offset, value)
            try {
                val charUuid = characteristic?.uuid
                val dataSize = value?.size ?: 0
                Log.d(TAG, "📥 Write request: $dataSize bytes from ${device?.address} to $charUuid")

                // Send response if needed
                if (responseNeeded) {
                    bluetoothGattServer?.sendResponse(
                        device,
                        requestId,
                        BluetoothGatt.GATT_SUCCESS,
                        offset,
                        value
                    )
                }

                // Forward data to Dart via EventChannel
                if (value != null && value.isNotEmpty()) {
                    val charType = when (charUuid) {
                        MESSAGE_CHAR_UUID -> "message"
                        TYPING_CHAR_UUID -> "typing"
                        else -> "unknown"
                    }
                    
                    sendEventToDart(mapOf(
                        "type" to "data",
                        "characteristicType" to charType,
                        "data" to value.toList(), // Convert to List<Int> for Dart
                        "deviceAddress" to (device?.address ?: "unknown")
                    ))
                }

            } catch (e: SecurityException) {
                Log.e(TAG, "Security exception handling write request", e)
            } catch (e: Exception) {
                Log.e(TAG, "Error handling write request", e)
            }
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice?,
            requestId: Int,
            descriptor: BluetoothGattDescriptor?,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?
        ) {
            super.onDescriptorWriteRequest(device, requestId, descriptor, preparedWrite, responseNeeded, offset, value)
            try {
                Log.d(TAG, "📝 Descriptor write from ${device?.address}")
                
                // Handle CCCD writes for notifications
                if (responseNeeded) {
                    bluetoothGattServer?.sendResponse(
                        device,
                        requestId,
                        BluetoothGatt.GATT_SUCCESS,
                        offset,
                        value
                    )
                }
            } catch (e: SecurityException) {
                Log.e(TAG, "Security exception handling descriptor write", e)
            }
        }

        override fun onServiceAdded(status: Int, service: BluetoothGattService?) {
            super.onServiceAdded(status, service)
            if (status == BluetoothGatt.GATT_SUCCESS) {
                Log.d(TAG, "✅ Service ${service?.uuid} added successfully")
            } else {
                Log.e(TAG, "❌ Failed to add service: status $status")
            }
        }

        override fun onNotificationSent(device: BluetoothDevice?, status: Int) {
            super.onNotificationSent(device, status)
            if (status == BluetoothGatt.GATT_SUCCESS) {
                Log.d(TAG, "✅ Notification sent to ${device?.address}")
            } else {
                Log.e(TAG, "❌ Notification failed to ${device?.address}: status $status")
            }
        }
    }

    // ==================== Send Data to Connected Devices ====================

    private fun sendToConnectedDevices(data: ByteArray, charType: String) {
        try {
            val characteristic = when (charType) {
                "typing" -> typingCharacteristic
                else -> messageCharacteristic
            }

            if (characteristic == null) {
                Log.e(TAG, "Characteristic not available for type: $charType")
                return
            }

            characteristic.value = data

            for (device in connectedDevices.toList()) {
                try {
                    val sent = bluetoothGattServer?.notifyCharacteristicChanged(
                        device,
                        characteristic,
                        false // indicate = false means notification
                    )
                    Log.d(TAG, "📤 Notified ${device.address}: $sent (${data.size} bytes)")
                } catch (e: SecurityException) {
                    Log.e(TAG, "Security exception notifying device", e)
                } catch (e: Exception) {
                    Log.e(TAG, "Error notifying device ${device.address}", e)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error sending to connected devices", e)
        }
    }

    // ==================== Event Sending ====================

    private fun sendEventToDart(data: Map<String, Any>) {
        mainHandler.post {
            eventSink?.success(data)
        }
    }

    // ==================== Cleanup ====================

    fun cleanup() {
        stopAdvertising()
        eventSink = null
    }
}
