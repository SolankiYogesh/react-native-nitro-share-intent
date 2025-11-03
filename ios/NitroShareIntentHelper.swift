import Foundation
import UIKit

/**
 * Helper class to integrate NitroShareIntent with your iOS app.
 * 
 * Usage in your AppDelegate:
 * 
 * func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
 *   NitroShareIntentHelper.handleURL(url)
 *   return true
 * }
 * 
 * func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
 *   NitroShareIntentHelper.handleUserActivity(userActivity)
 *   return true
 * }
 */
@objc public class NitroShareIntentHelper: NSObject {
  
  @objc public static func handleURL(_ url: URL) {
    let shareIntent = NitroShareIntent.shared
    shareIntent.processShareIntent(from: url)
  }
  
  @objc public static func handleUserActivity(_ userActivity: NSUserActivity) {
    guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
          let url = userActivity.webpageURL else {
      return
    }
    
    handleURL(url)
  }
  
  @objc public static func handleShareExtension(text: String?, subject: String? = nil, files: [URL]? = nil) {
    let shareIntent = NitroShareIntent.shared
    
    if let files = files, !files.isEmpty {
      shareIntent.processShareIntent(files: files, text: text, subject: subject)
    } else if let text = text {
      shareIntent.processShareIntent(text: text, subject: subject)
    }
  }
}