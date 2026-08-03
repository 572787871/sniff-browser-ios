import UIKit

/// 用户偏好的外观模式，持久化到 UserDefaults。
enum AppearancePreference: String, CaseIterable, Sendable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    static let storageKey = "com.sniffbrowser.appearance"

    /// 当前保存的偏好。
    static var current: AppearancePreference {
        get {
            let raw = UserDefaults.standard.string(forKey: storageKey) ?? "system"
            return AppearancePreference(rawValue: raw) ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
            applyGlobal(newValue)
        }
    }

    /// 对应的 UIUserInterfaceStyle。
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    /// 显示名称。
    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light:  return "浅色"
        case .dark:   return "深色"
        }
    }

    /// 系统图标名称。
    var symbolName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    /// 将保存的偏好应用到所有窗口。
    static func applyGlobal(_ preference: AppearancePreference? = nil) {
        let style = (preference ?? current).userInterfaceStyle
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}
