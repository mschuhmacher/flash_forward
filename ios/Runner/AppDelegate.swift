import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // flutter_local_notifications requires the AppDelegate to be set as the
    // UNUserNotificationCenter delegate. FlutterAppDelegate forwards the
    // delegate calls to registered plugins via FlutterPluginAppLifeCycleDelegate.
    UNUserNotificationCenter.current().delegate = self

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
