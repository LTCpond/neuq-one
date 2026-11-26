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
    let notificationSettings = FlutterMethodChannel(
      name: "org.neuqone.neuq_one/notification_settings",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    notificationSettings.setMethodCallHandler { call, result in
      guard call.method == "open" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let path: String
      if #available(iOS 16.0, *) {
        path = UIApplication.openNotificationSettingsURLString
      } else {
        path = UIApplication.openSettingsURLString
      }
      guard let url = URL(string: path) else {
        result(false)
        return
      }
      UIApplication.shared.open(url, options: [:]) { result($0) }
    }
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
