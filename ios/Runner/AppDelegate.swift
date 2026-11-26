import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let appVersion = FlutterMethodChannel(
      name: "org.neuqone.neuq_one/app_version",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    appVersion.setMethodCallHandler { call, result in
      switch call.method {
      case "getVersion":
        result(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString"))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
