import Foundation

struct DownloadSettingsState: Equatable, Sendable {
    let allowsCellularDownloads: Bool
    let maximumConcurrentDownloads: Int
    let completionNotificationsEnabled: Bool
    let automaticRetryEnabled: Bool
    let defaultSaveLocationDescription: String
}

/// 下载策略的单一持久化入口。
///
/// 下载服务应在创建任务与重试任务时读取这里的快照，设置页面不保存第二份状态。
struct DownloadPreferences {
    static let concurrentDownloadRange = 1...5
    static let defaultConcurrentDownloadCount = 3
    static let defaultSaveLocationDescription = "App 沙盒的 Documents/Downloads 目录"

    private enum Key {
        static let allowsCellularDownloads = "download.allowsCellularDownloads"
        static let maximumConcurrentDownloads = "download.maximumConcurrentDownloads"
        static let completionNotificationsEnabled = "download.completionNotificationsEnabled"
        static let automaticRetryEnabled = "download.automaticRetryEnabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var allowsCellularDownloads: Bool {
        get {
            defaults.object(forKey: Key.allowsCellularDownloads) == nil
                ? true
                : defaults.bool(forKey: Key.allowsCellularDownloads)
        }
        nonmutating set {
            defaults.set(newValue, forKey: Key.allowsCellularDownloads)
        }
    }

    var maximumConcurrentDownloads: Int {
        get {
            guard defaults.object(forKey: Key.maximumConcurrentDownloads) != nil else {
                return Self.defaultConcurrentDownloadCount
            }
            return Self.clampedConcurrentDownloadCount(
                defaults.integer(forKey: Key.maximumConcurrentDownloads)
            )
        }
        nonmutating set {
            defaults.set(
                Self.clampedConcurrentDownloadCount(newValue),
                forKey: Key.maximumConcurrentDownloads
            )
        }
    }

    var completionNotificationsEnabled: Bool {
        get {
            defaults.object(forKey: Key.completionNotificationsEnabled) == nil
                ? false
                : defaults.bool(forKey: Key.completionNotificationsEnabled)
        }
        nonmutating set {
            defaults.set(newValue, forKey: Key.completionNotificationsEnabled)
        }
    }

    var automaticRetryEnabled: Bool {
        get {
            defaults.object(forKey: Key.automaticRetryEnabled) == nil
                ? true
                : defaults.bool(forKey: Key.automaticRetryEnabled)
        }
        nonmutating set {
            defaults.set(newValue, forKey: Key.automaticRetryEnabled)
        }
    }

    var state: DownloadSettingsState {
        DownloadSettingsState(
            allowsCellularDownloads: allowsCellularDownloads,
            maximumConcurrentDownloads: maximumConcurrentDownloads,
            completionNotificationsEnabled: completionNotificationsEnabled,
            automaticRetryEnabled: automaticRetryEnabled,
            defaultSaveLocationDescription: Self.defaultSaveLocationDescription
        )
    }

    private static func clampedConcurrentDownloadCount(_ value: Int) -> Int {
        min(
            max(value, concurrentDownloadRange.lowerBound),
            concurrentDownloadRange.upperBound
        )
    }
}
