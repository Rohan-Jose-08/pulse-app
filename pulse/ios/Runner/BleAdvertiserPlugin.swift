import Flutter
import CoreBluetooth
import UIKit

class BleAdvertiserPlugin: NSObject, FlutterPlugin, CBPeripheralManagerDelegate {
    private var peripheralManager: CBPeripheralManager?
    private var isAdvertising = false
    private var serviceUUID: CBUUID?
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.pulse.ble/advertiser", binaryMessenger: registrar.messenger())
        let instance = BleAdvertiserPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
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
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func startAdvertising(serviceUuid: String, userId: String, result: @escaping FlutterResult) {
        guard let uuid = UUID(uuidString: serviceUuid) else {
            result(FlutterError(code: "INVALID_UUID", message: "Invalid service UUID format", details: nil))
            return
        }
        
        serviceUUID = CBUUID(nsuuid: uuid)
        
        // Initialize peripheral manager if needed
        if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        }
        
        // Store result callback for later (when state updates)
        if peripheralManager?.state == .poweredOn {
            actuallyStartAdvertising(result: result)
        } else {
            // Will be called when state becomes powered on
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if self?.peripheralManager?.state == .poweredOn {
                    self?.actuallyStartAdvertising(result: result)
                } else {
                    result(FlutterError(code: "BT_NOT_READY", message: "Bluetooth is not powered on", details: nil))
                }
            }
        }
    }
    
    private func actuallyStartAdvertising(result: @escaping FlutterResult) {
        guard let peripheralManager = peripheralManager,
              let serviceUUID = serviceUUID else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "Peripheral manager not initialized", details: nil))
            return
        }
        
        // Create service
        let service = CBMutableService(type: serviceUUID, primary: true)
        
        // Create characteristics for messages and typing
        let messageCharUUID = CBUUID(string: "0000FAB0-0000-1000-8000-00805F9B34FB")
        let typingCharUUID = CBUUID(string: "0000FAB1-0000-1000-8000-00805F9B34FB")
        
        let messageCharacteristic = CBMutableCharacteristic(
            type: messageCharUUID,
            properties: [.read, .write, .notify],
            value: nil,
            permissions: [.readable, .writeable]
        )
        
        let typingCharacteristic = CBMutableCharacteristic(
            type: typingCharUUID,
            properties: [.read, .write, .notify],
            value: nil,
            permissions: [.readable, .writeable]
        )
        
        service.characteristics = [messageCharacteristic, typingCharacteristic]
        
        // Add service
        peripheralManager.add(service)
        
        // Start advertising
        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBAdvertisementDataLocalNameKey: "Pulse"
        ]
        
        peripheralManager.startAdvertising(advertisementData)
        isAdvertising = true
        
        print("✅ BLE advertising started on iOS")
        result(true)
    }
    
    private func stopAdvertising() {
        peripheralManager?.stopAdvertising()
        isAdvertising = false
        print("🛑 BLE advertising stopped on iOS")
    }
    
    // MARK: - CBPeripheralManagerDelegate
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            print("📱 Bluetooth powered on")
        case .poweredOff:
            print("📱 Bluetooth powered off")
        case .resetting:
            print("📱 Bluetooth resetting")
        case .unauthorized:
            print("📱 Bluetooth unauthorized")
        case .unsupported:
            print("📱 Bluetooth unsupported")
        case .unknown:
            print("📱 Bluetooth state unknown")
        @unknown default:
            print("📱 Bluetooth state unknown")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            print("❌ Error adding service: \(error.localizedDescription)")
        } else {
            print("✅ Service added successfully")
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            print("❌ Error starting advertising: \(error.localizedDescription)")
        } else {
            print("✅ Started advertising successfully")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        // Handle incoming write requests from central devices
        for request in requests {
            if let value = request.value {
                print("📥 Received write: \(value.count) bytes")
                // Process the received data
                // This would be handled by your chat transport layer
            }
            peripheral.respond(to: request, withResult: .success)
        }
    }
}
