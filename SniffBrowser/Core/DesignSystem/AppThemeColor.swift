import UIKit

/// 应用级强调色预设。颜色通过自定义 UIKit trait 从场景根部向下传播，
/// 因此切换时无需重建浏览器或丢失当前网页状态。
enum AppThemeColor: Int, CaseIterable, Sendable {
  case amber
  case ocean
  case pine
  case violet
  case coral

  private static let storageKey = "com.sniffbrowser.themeColor"

  @MainActor
  static var current: AppThemeColor {
    get {
      let rawValue = UserDefaults.standard.object(forKey: storageKey) as? Int
      return rawValue.flatMap(AppThemeColor.init(rawValue:)) ?? .ocean
    }
    set {
      guard newValue != current else { return }
      UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
      applyGlobal(newValue)
    }
  }

  var displayName: String {
    switch self {
    case .amber: return "琥珀"
    case .ocean: return "海蓝"
    case .pine: return "松绿"
    case .violet: return "鸢紫"
    case .coral: return "珊瑚"
    }
  }

  /// 设置列表中的固定预览色，避免色块随系统深浅模式产生歧义。
  var previewColor: UIColor {
    color(isDark: false, highContrast: false)
  }

  func resolvedColor(for traits: UITraitCollection) -> UIColor {
    color(
      isDark: traits.userInterfaceStyle == .dark,
      highContrast: traits.accessibilityContrast == .high
    )
  }

  func resolvedPrivateColor(for traits: UITraitCollection) -> UIColor {
    color(
      isDark: true,
      highContrast: traits.accessibilityContrast == .high
    )
  }

  func resolvedDescriptionColor(for traits: UITraitCollection) -> UIColor {
    color(
      isDark: traits.userInterfaceStyle == .dark,
      highContrast: true
    )
  }

  func resolvedContentColor(for traits: UITraitCollection) -> UIColor {
    if traits.userInterfaceStyle == .dark || self == .amber {
      return UIColor(red: 0.105, green: 0.094, blue: 0.080, alpha: 1)
    }
    return UIColor.white
  }

  @MainActor
  static func applyGlobal(_ theme: AppThemeColor? = nil) {
    let resolvedTheme = theme ?? current
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      windowScene.traitOverrides.appThemeColor = resolvedTheme
      for window in windowScene.windows {
        window.tintColor = AppColors.accent
        window.setNeedsLayout()
      }
    }
    AppAppearance.refreshThemeAppearance()
  }

  private func color(isDark: Bool, highContrast: Bool) -> UIColor {
    switch (self, isDark, highContrast) {
    case (.amber, false, false):
      return UIColor(red: 0.773, green: 0.478, blue: 0.165, alpha: 1)
    case (.amber, false, true):
      return UIColor(red: 0.584, green: 0.306, blue: 0.075, alpha: 1)
    case (.amber, true, false):
      return UIColor(red: 0.878, green: 0.573, blue: 0.286, alpha: 1)
    case (.amber, true, true):
      return UIColor(red: 0.949, green: 0.690, blue: 0.392, alpha: 1)

    case (.ocean, false, false):
      return UIColor(red: 0.000, green: 0.443, blue: 0.890, alpha: 1)
    case (.ocean, false, true):
      return UIColor(red: 0.090, green: 0.286, blue: 0.604, alpha: 1)
    case (.ocean, true, false):
      return UIColor(red: 0.039, green: 0.518, blue: 1.000, alpha: 1)
    case (.ocean, true, true):
      return UIColor(red: 0.545, green: 0.729, blue: 0.980, alpha: 1)

    case (.pine, false, false):
      return UIColor(red: 0.180, green: 0.463, blue: 0.361, alpha: 1)
    case (.pine, false, true):
      return UIColor(red: 0.086, green: 0.353, blue: 0.255, alpha: 1)
    case (.pine, true, false):
      return UIColor(red: 0.365, green: 0.706, blue: 0.565, alpha: 1)
    case (.pine, true, true):
      return UIColor(red: 0.494, green: 0.808, blue: 0.655, alpha: 1)

    case (.violet, false, false):
      return UIColor(red: 0.455, green: 0.322, blue: 0.690, alpha: 1)
    case (.violet, false, true):
      return UIColor(red: 0.337, green: 0.204, blue: 0.584, alpha: 1)
    case (.violet, true, false):
      return UIColor(red: 0.659, green: 0.533, blue: 0.890, alpha: 1)
    case (.violet, true, true):
      return UIColor(red: 0.769, green: 0.655, blue: 0.965, alpha: 1)

    case (.coral, false, false):
      return UIColor(red: 0.714, green: 0.286, blue: 0.259, alpha: 1)
    case (.coral, false, true):
      return UIColor(red: 0.596, green: 0.173, blue: 0.153, alpha: 1)
    case (.coral, true, false):
      return UIColor(red: 0.902, green: 0.475, blue: 0.431, alpha: 1)
    case (.coral, true, true):
      return UIColor(red: 0.969, green: 0.596, blue: 0.545, alpha: 1)
    }
  }
}

struct AppThemeColorTrait: UITraitDefinition {
  static let defaultValue = AppThemeColor.ocean
  static let affectsColorAppearance = true
  static let name = "SniffBrowser Theme Color"
  static let identifier = "com.sniffbrowser.themeColor.trait"
}

extension UITraitCollection {
  var appThemeColor: AppThemeColor {
    self[AppThemeColorTrait.self]
  }
}

extension UIMutableTraits {
  var appThemeColor: AppThemeColor {
    get { self[AppThemeColorTrait.self] }
    set { self[AppThemeColorTrait.self] = newValue }
  }
}
