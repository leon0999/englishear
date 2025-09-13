import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Native audio channel registration temporarily disabled
    // AudioChannelHandler will be registered automatically if needed
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
