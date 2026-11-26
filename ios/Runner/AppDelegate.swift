import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Google Maps key, from Info.plist's GMSApiKey (filled in at build time
    // from GMS_API_KEY in the git-ignored ios/Flutter/Secrets.xcconfig).
    // Without it the map crashes on iOS.
    if let key = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !key.isEmpty {
      GMSServices.provideAPIKey(key)
    }
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    // Register with APNs explicitly: with the implicit-engine AppDelegate,
    // Firebase Messaging's automatic registration doesn't fire (found on
    // SpotLat), so iPhones would never get a push token.
    application.registerForRemoteNotifications()
    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
