import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func windowScene(
    _ windowScene: UIWindowScene,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
      appDelegate.application(UIApplication.shared, performActionFor: shortcutItem, completionHandler: completionHandler)
    } else {
      completionHandler(false)
    }
  }
}
