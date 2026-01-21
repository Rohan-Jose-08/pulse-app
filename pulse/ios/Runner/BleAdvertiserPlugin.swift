import Flutter
import CoreBluetooth
import UIKit

/**
 * Complete BLE Peripheral Plugin for Pulse Mesh Networking (iOS).
 *
 * This plugin provides:
 * - BLE Advertising (to be discoverable)
 * - GATT Server via CBPeripheralManager (to receive incoming data)
 * - EventChannel (to stream incoming data to Dart)
 */
class BleAdvertiserPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, CBPeripheralManagerDelegate {
    
    // MARK: - Properties
    
    private var peripheralManager: CBPeripheralManager?
    private var isAdvertising = false
    private var serviceUUID: CBUUID?
    private var eventSink: FlutterEventSink?
    
    // Characteristic UUIDs - must match Android and Dart code
    private let messageCharUUID = CBUUID(string: "0000FAB0-0000-1000-8000-00805F9B34FB")
    private let typingCharUUID = CBUUID(string: "0000FAB1-0000-1000-8000-00805F9B34FB")
    
    // Mutable characteristics for sending notifications
    private var messageCharacteristic: CBMutableCharacteristic?
    private var typingCharacteristic: CBMutableCharacteristic?
    
    // Track subscribed centrals
    private var subscribedCentrals: [CBCentral] = []
    
    // Pending result for async operations
    private var pendingStartResult: FlutterResult?
    
    // MARK: - Plugin Registration
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = BleAdvertiserPlugin()
        
        // Method Channel for commands
        let methodChannel = FlutterMethodChannel(
            name: "com.pulse.ble/advertiser",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        
        // Event Channel for incoming BLE data
        let eventChannel = FlutterEventChannel(
            name: "com.pulse.ble/advertiser_events",
            binaryMessenger: registrar.messenger()
        )
        eventChannel.setStreamHandler(instance)
    }
    
    // MARK: - FlutterStreamHandler
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        print("📡 iOS: EventChannel listener attached")
        self.eventSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        print("📡 iOS: EventChannel listener detached")
        self.eventSink = nil
        return nil
    }
    
    // MARK: - Method Channel Handler
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isAdvertisingSupported":
            // iOS always supports BLE peripheral mode (if BLE is available)
            result(true)
            
        case "startAdvertising":
            guard let args = call.arguments as? [String: Any],
                  let serviceUuidString = args["serviceUuid"] as? String,
                  let userId = args["userId"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "serviceUuid and userId are required", details: nil))
                return
            }
            startAdvertising(serviceUuid: serviceUuidString, userId: userId, result: result)
            
        case "stopAdvertising":
            stopAdvertising()
            result(nil)
            
        case "sendToConnectedDevices":
            guard let args = call.arguments as? [String: Any],
                  let dataList = args["data"] as? [Int] else {
                result(FlutterError(code: "INVALID_ARGS", message: "data is required", details: nil))
                return
            }
            let charType = args["characteristicType"] as? String ?? "message"
            let data = Data(dataList.map { UInt8($0) })
            sendToSubscribedCentrals(data: data, charType: charType)
            result(true)
            
        case "getConnectedDeviceCount":
            result(subscribedCentrals.count)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - BLE Advertising
    
    private func startAdvertising(serviceUuid: String, userId: String, result: @escaping FlutterResult) {
        guard let uuid = UUID(uuidString: serviceUuid) else {
            result(FlutterError(code: "INVALID_UUID", message: "Invalid service UUID format", details: nil))
            return
        }
        
        serviceUUID = CBUUID(nsuuid: uuid)
        pendingStartResult = result
        
        // Initialize peripheral manager if needed
        if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        } else if peripheralManager?.state == .poweredOn {
            actuallyStartAdvertising()
        }
        // If not powered on, will be called from peripheralManagerDidUpdateState
    }
    
    private func actuallyStartAdvertising() {
        guard let peripheralManager = peripheralManager,
              let serviceUUID = serviceUUID else {
            pendingStartResult?(FlutterError(code: "NOT_INITIALIZED", message: "Peripheral manager not initialized", details: nil))
            pendingStartResult = nil
            return
        }
        
        // Create service
        let service = CBMutableService(type: serviceUUID, primary: true)
        
        // Create message characteristic (read, write, notify)
        messageCharacteristic = CBMutableCharacteristic(
            type: messageCharUUID,
            properties: [.read, .write, .writeWithoutResponse, .notify],
            value: nil,
            permissions: [.readable, .writeable]
        )
        
        // Create typing characteristic (read, write, notify)
        typingCharacteristic = CBMutableCharacteristic(
            type: typingCharUUID,
            properties: [.read, .write, .writeWithoutResponse, .notify],
            value: nil,
            permissions: [.readable, .writeable]
        )
        
        service.characteristics = [messageCharacteristic!, typingCharacteristic!]
        
        // Add service
        peripheralManager.add(service)
        
        // Start advertising
        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBAdvertisementDataLocalNameKey: "Pulse"
        ]
        
        peripheralManager.startAdvertising(advertisementData)
        isAdvertising = true
        
        print("✅ iOS: BLE advertising started")
        pendingStartResult?(true)
        pendingStartResult = nil
    }
    
    private func stopAdvertising() {
        peripheralManager?.stopAdvertising()
        peripheralManager?.removeAllServices()
        isAdvertising = false
        subscribedCentrals.removeAll()
        print("🛑 iOS: BLE advertising stopped")
    }
    
    // MARK: - Send Data to Connected Centrals
    
    private func sendToSubscribedCentrals(data: Data, charType: String) {
        guard let peripheralManager = peripheralManager else {
            print("⚠️ iOS: PeripheralManager not available")
            return
        }
        
        let characteristic: CBMutableCharacteristic? = charType == "typing" ? typingCharacteristic : messageCharacteristic
        
        guard let char = characteristic else {
            print("⚠️ iOS: Characteristic not available for type: \(charType)")
            return
        }
        
        char.value = data
        
        // Send notification to all subscribed centrals
        let success = peripheralManager.updateValue(data, for: char, onSubscribedCentrals: nil)
        
        if success {
            print("📤 iOS: Sent \(data.count) bytes to \(subscribedCentrals.count) subscribed central(s)")
        } else {
            print("⚠️ iOS: Failed to send data (queue full), will retry")
            // The peripheral manager will call peripheralManagerIsReady(toUpdateSubscribers:) when ready
        }
    }
    
    // MARK: - CBPeripheralManagerDelegate
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        var stateString = ""
        switch peripheral.state {
        case .poweredOn:
            stateString = "poweredOn"
            print("📱 iOS: Bluetooth powered on")
            // If we have a pending start request, proceed
            if pendingStartResult != nil {
                actuallyStartAdvertising()
            }
        case .poweredOff:
            stateString = "poweredOff"
            print("📱 iOS: Bluetooth powered off")
            isAdvertising = false
            subscribedCentrals.removeAll()
        case .resetting:
            stateString = "resetting"
            print("📱 iOS: Bluetooth resetting")
        case .unauthorized:
            stateString = "unauthorized"
            print("📱 iOS: Bluetooth unauthorized")
            pendingStartResult?(FlutterError(code: "UNAUTHORIZED", message: "Bluetooth not authorized", details: nil))
            pendingStartResult = nil
        case .unsupported:
            stateString = "unsupported"
            print("📱 iOS: Bluetooth unsupported")
            pendingStartResult?(FlutterError(code: "UNSUPPORTED", message: "BLE not supported", details: nil))
            pendingStartResult = nil
        case .unknown:
            stateString = "unknown"
            print("📱 iOS: Bluetooth state unknown")
        @unknown default:
            stateString = "unknown"
            print("📱 iOS: Bluetooth state unknown")
        }
        
        // Send state change event to Dart
        sendEventToDart([
            "type": "bluetoothState",
            "state": stateString
        ])
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            print("❌ iOS: Error adding service: \(error.localizedDescription)")
        } else {
            print("✅ iOS: Service added successfully: \(service.uuid)")
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            print("❌ iOS: Error starting advertising: \(error.localizedDescription)")
        } else {
            print("✅ iOS: Started advertising successfully")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        print("🔵 iOS: Central \(central.identifier) subscribed to \(characteristic.uuid)")
        if !subscribedCentrals.contains(where: { $0.identifier == central.identifier }) {
            subscribedCentrals.append(central)
        }
        
        sendEventToDart([
            "type": "connection",
            "event": "subscribed",
            "centralId": central.identifier.uuidString,
            "characteristicUuid": characteristic.uuid.uuidString,
            "connectedCount": subscribedCentrals.count
        ])
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        print("🔴 iOS: Central \(central.identifier) unsubscribed from \(characteristic.uuid)")
        subscribedCentrals.removeAll { $0.identifier == central.identifier }
        
        sendEventToDart([
            "type": "connection",
            "event": "unsubscribed",
            "centralId": central.identifier.uuidString,
            "characteristicUuid": characteristic.uuid.uuidString,
            "connectedCount": subscribedCentrals.count
        ])
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        // Handle incoming write requests from central devices
        for request in requests {
            if let value = request.value {
                let charUuid = request.characteristic.uuid
                let charType: String
                
                if charUuid == messageCharUUID {
                    charType = "message"
                } else if charUuid == typingCharUUID {
                    charType = "typing"
                } else {
                    charType = "unknown"
                }
                
                print("📥 iOS: Received write: \(value.count) bytes from \(request.central.identifier) to \(charType)")
                
                // Forward data to Dart via EventChannel
                sendEventToDart([
                    "type": "data",
                    "characteristicType": charType,
                    "data": Array(value), // Convert Data to [UInt8] which becomes List<int> in Dart
                    "centralId": request.central.identifier.uuidString
                ])
            }
            
            // Send success response
            peripheral.respond(to: request, withResult: .success)
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        print("📖 iOS: Received read request from \(request.central.identifier)")
        
        // Return current value or empty data
        if let char = request.characteristic as? CBMutableCharacteristic {
            request.value = char.value ?? Data()
        }
        
        peripheral.respond(to: request, withResult: .success)
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        // Called when the peripheral manager is ready to send more updates
        // This is a good place to retry any pending notifications
        print("📡 iOS: Ready to update subscribers")
    }
    
    // MARK: - Event Sending
    
    private func sendEventToDart(_ data: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(data)
        }
    }
}
