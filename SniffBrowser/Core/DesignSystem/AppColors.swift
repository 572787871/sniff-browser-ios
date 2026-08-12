import UIKit

/// SniffBrowser 的语义颜色入口。
///
/// 页面不应直接保存解析后的颜色，也不应根据深浅模式自行分支。使用这些动态颜色，
/// 让 UIKit 在外观、增强对比度和辅助功能变化时自动重新解析。
enum AppColors {
    /// Deep Ocean 的冷灰蓝画布。浅色模式保持通透，深色模式使用低亮度海军蓝。
    static let background = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.027, green: 0.063, blue: 0.106, alpha: 1)
        }
        return UIColor(red: 0.957, green: 0.973, blue: 0.992, alpha: 1)
    }
    static let canvas = background
    /// 搜索与建议层沿用同一画布色，不改变网页本身的背景。
    static let browserCanvas = background
    /// 无痕模式使用更深的蓝黑色，与普通深色模式保持可辨识差异。
    static let privateBrowsingBackground = UIColor(
        red: 0.016,
        green: 0.027,
        blue: 0.055,
        alpha: 1
    )
    static let privateBrowsingSurface = UIColor(
        red: 0.047,
        green: 0.071,
        blue: 0.125,
        alpha: 1
    )
    static let privateBrowsingChrome = UIColor(
        red: 0.027,
        green: 0.047,
        blue: 0.090,
        alpha: 1
    )
    /// 无痕模式继承用户选择的全局主题色，并按深色表面自动提高可读性。
    static let privateBrowsingAccent = UIColor { traits in
        traits.appThemeColor.resolvedPrivateColor(for: traits)
    }
    static let privateBrowsingAccentContent = UIColor(
        red: 0.020,
        green: 0.043,
        blue: 0.075,
        alpha: 1
    )
    /// 普通与无痕主页共用布局和画布，仅用该动态色强调无痕说明。
    static let privateBrowsingDescription = UIColor { traits in
        traits.appThemeColor.resolvedDescriptionColor(for: traits)
    }

    /// 普通卡片与列表分组背景，形成轻量玻璃的层次。
    static let surface = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.055, green: 0.118, blue: 0.184, alpha: 1)
        }
        return UIColor(red: 0.996, green: 0.998, blue: 1.000, alpha: 1)
    }
    static let secondarySurface = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.078, green: 0.157, blue: 0.235, alpha: 1)
        }
        return UIColor(red: 0.902, green: 0.937, blue: 0.976, alpha: 1)
    }
    static let tertiarySurface = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.110, green: 0.196, blue: 0.286, alpha: 1)
        }
        return UIColor(red: 0.835, green: 0.890, blue: 0.949, alpha: 1)
    }

    /// 浮层的轻透明动态背景。实际的毛玻璃应由 `AppMaterialView` 提供。
    static let elevatedSurface = UIColor { traits in
        surface
            .resolvedColor(with: traits)
            .withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.88 : 0.92)
    }

    /// Reduce Transparency 时供地址栏和工具栏使用的不透明回退色。
    static let chromeFallback = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.047, green: 0.098, blue: 0.153, alpha: 0.98)
        }
        return UIColor(red: 0.976, green: 0.988, blue: 1.000, alpha: 0.98)
    }

    /// 浏览器悬浮控件使用低饱和蓝灰玻璃，不与网页内容争夺注意力。
    static let browserChromeTint = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.047, green: 0.094, blue: 0.145, alpha: 0.82)
        }
        return UIColor(red: 0.980, green: 0.990, blue: 1.000, alpha: 0.88)
    }

    static let browserChromeBorder = UIColor { traits in
        let highContrast = traits.accessibilityContrast == .high
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.420, green: 0.624, blue: 0.820, alpha: highContrast ? 0.54 : 0.30)
        }
        return UIColor(
            red: 0.208,
            green: 0.376,
            blue: 0.557,
            alpha: highContrast ? 0.46 : 0.28
        )
    }

    static let browserChromeSeparator = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.420, green: 0.624, blue: 0.820, alpha: 0.18)
        }
        return UIColor(red: 0.208, green: 0.376, blue: 0.557, alpha: 0.14)
    }

    static let primaryText = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.949, green: 0.973, blue: 1.000, alpha: 1)
            : UIColor(red: 0.063, green: 0.118, blue: 0.196, alpha: 1)
    }
    static let secondaryText = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.624, green: 0.714, blue: 0.808, alpha: 1)
            : UIColor(red: 0.357, green: 0.439, blue: 0.537, alpha: 1)
    }
    static let tertiaryText = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.455, green: 0.557, blue: 0.663, alpha: 1)
            : UIColor(red: 0.494, green: 0.565, blue: 0.647, alpha: 1)
    }
    static let placeholderText = tertiaryText

    /// 用户选择的全局主题色，仅用于选中、进度和关键操作。
    static let accent = UIColor { traits in
        traits.appThemeColor.resolvedColor(for: traits)
    }
    static let accentFill = UIColor { traits in
        accent.resolvedColor(with: traits).withAlphaComponent(
            traits.userInterfaceStyle == .dark ? 0.18 : 0.11
        )
    }
    /// 强调色实心背景上的文字与图标颜色。
    static let accentContent = UIColor { traits in
        traits.appThemeColor.resolvedContentColor(for: traits)
    }
    static let browserChromeSelection = accentFill
    static let progressTrack = tertiarySurface

    static let separator = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.302, green: 0.494, blue: 0.686, alpha: 0.28)
        }
        return UIColor(red: 0.208, green: 0.376, blue: 0.557, alpha: 0.18)
    }
    static let opaqueSeparator = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.129, green: 0.235, blue: 0.337, alpha: 1)
            : UIColor(red: 0.788, green: 0.855, blue: 0.925, alpha: 1)
    }

    static let success = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.361, green: 0.788, blue: 0.612, alpha: 1)
            : UIColor(red: 0.106, green: 0.553, blue: 0.369, alpha: 1)
    }
    static let warning = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.969, green: 0.702, blue: 0.333, alpha: 1)
            : UIColor(red: 0.812, green: 0.467, blue: 0.078, alpha: 1)
    }
    static let danger = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.988, green: 0.467, blue: 0.471, alpha: 1)
            : UIColor(red: 0.745, green: 0.180, blue: 0.220, alpha: 1)
    }

    /// 空状态插图使用低饱和中性色，不与可操作主题色争夺注意力。
    static let stateSymbol = secondaryText
    static let stateSymbolBackground = secondarySurface
}
