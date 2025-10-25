import UIKit
import Flutter
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GMSServices.provideAPIKey("AIzaSyCUXDdV3hPkr2u2TcrsoGRxRXn8UxYmb8o")
    
    // Register BLE Advertiser plugin
    let controller = window?.rootViewController as! FlutterViewController
    BleAdvertiserPlugin.register(with: registrar(forPlugin: "BleAdvertiserPlugin")!)
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

