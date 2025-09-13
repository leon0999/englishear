import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Register native audio channel
    if let controller = window?.rootViewController as? FlutterViewController {
      AudioChannelHandler.register(with: controller.registrar(forPlugin: "AudioChannelHandler")!)
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
