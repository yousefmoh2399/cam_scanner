import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pendingQuickAction: String?
  private var quickActionChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    
    if let controller = window?.rootViewController as? FlutterViewController {
      setupQuickActionChannel(controller: controller)
    }

    if let shortcutItem = launchOptions?[UIApplication.LaunchOptionsKey.shortcutItem] as? UIApplicationShortcutItem {
      pendingQuickAction = shortcutItem.type
    }

    return result
  }

  private func setupQuickActionChannel(controller: FlutterViewController) {
    let channel = FlutterMethodChannel(name: "ismart/doc_scanner", binaryMessenger: controller.binaryMessenger)
    quickActionChannel = channel

    channel.setMethodCallHandler({ [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      if call.method == "getInitialQuickAction" {
        let action = self?.pendingQuickAction
        self?.pendingQuickAction = nil
        result(action)
      } else {
        result(FlutterMethodNotImplemented)
      }
    })
  }

  override func application(
    _ application: UIApplication,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    if let channel = quickActionChannel {
      channel.invokeMethod("onQuickAction", arguments: shortcutItem.type)
      completionHandler(true)
    } else {
      pendingQuickAction = shortcutItem.type
      completionHandler(true)
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
