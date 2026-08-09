import UIKit

@main
@MainActor
final class AppDelegate: UIResponder, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions:
      [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    AppAppearance.configure()
    // Apply saved appearance preference before any window is shown
    AppearancePreference.applyGlobal()
    return true
  }

  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    UISceneConfiguration(
      name: "Default Configuration",
      sessionRole: connectingSceneSession.role
    )
  }

  func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    DownloadCenter.shared.handleBackgroundEvents(
      identifier: identifier,
      completionHandler: completionHandler
    )
  }

  func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
    ResourceThumbnailLoader.shared.clearMemoryCache()
    RemoteMediaThumbnailLoader.shared.clearMemoryCache()
    FileThumbnailLoader.shared.clearMemory()
  }
}
