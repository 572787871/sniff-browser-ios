import Foundation
import UserNotifications

final class DownloadNotificationService {
    private let preferences: DownloadPreferences

    init(preferences: DownloadPreferences) {
        self.preferences = preferences
    }

    func notifyCompleted(fileName: String, taskID: UUID) {
        guard preferences.completionNotificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "下载完成"
        content.body = fileName
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "download.\(taskID.uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
