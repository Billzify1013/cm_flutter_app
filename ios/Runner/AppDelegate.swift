import Flutter
import UIKit
import Firebase

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(_ application: UIApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
    return false
  }

  override func application(_ application: UIApplication, shouldRestoreApplicationState coder: NSCoder) -> Bool {
    return false
  }
}