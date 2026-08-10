import UIKit

/// SniffBrowser 的语义颜色入口。
///
/// 页面不应直接保存解析后的颜色，也不应根据深浅模式自行分支。使用这些动态颜色，
/// 让 UIKit 在外观、增强对比度和辅助功能变化时自动重新解析。
enum AppColors {
    /// Paper Signal 的暖纸画布。浅色模式避免生硬纯白，深色模式保持暖调炭黑。
    static let background = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.090, green: 0.086, blue: 0.078, alpha: 1)
        }
        return UIColor(red: 0.965, green: 0.953, blue: 0.925, alpha: 1)
    }
    static let canvas = background
    /// 搜索与建议层沿用同一纸张色，不改变网页本身的背景。
    static let browserCanvas = background
    /// 无痕模式使用更深的暖炭色，与普通深色模式保持可辨识差异。
    static let privateBrowsingBackground = UIColor(
        red: 0.068,
        green: 0.061,
        blue: 0.052,
        alpha: 1
    )
    static let privateBrowsingSurface = UIColor(
        red: 0.137,
        green: 0.125,
        blue: 0.106,
        alpha: 1
    )
    static let privateBrowsingChrome = UIColor(
        red: 0.105,
        green: 0.094,
        blue: 0.080,
        alpha: 1
    )
    /// 无痕模式继承用户选择的全局主题色，并按深色表面自动提高可读性。
    static let privateBrowsingAccent = UIColor { traits in
        traits.appThemeColor.resolvedPrivateColor(for: traits)
    }
    static let privateBrowsingAccentContent = UIColor(
        red: 0.105,
        green: 0.094,
        blue: 0.080,
        alpha: 1
    )
    /// 普通与无痕主页共用布局和画布，仅用该动态色强调无痕说明。
    static let privateBrowsingDescription = UIColor { traits in
        traits.appThemeColor.resolvedDescriptionColor(for: traits)
    }

    /// 普通卡片与列表分组背景，像同一张纸上的不同叠层。
    static let surface = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.137, green: 0.129, blue: 0.114, alpha: 1)
        }
        return UIColor(red: 0.996, green: 0.988, blue: 0.965, alpha: 1)
    }
    static let secondarySurface = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.180, green: 0.169, blue: 0.149, alpha: 1)
        }
        return UIColor(red: 0.941, green: 0.925, blue: 0.890, alpha: 1)
    }
    static let tertiarySurface = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.220, green: 0.204, blue: 0.176, alpha: 1)
        }
        return UIColor(red: 0.906, green: 0.882, blue: 0.835, alpha: 1)
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
            return UIColor(red: 0.125, green: 0.116, blue: 0.102, alpha: 0.98)
        }
        return UIColor(red: 0.980, green: 0.969, blue: 0.941, alpha: 0.98)
    }

    /// 浏览器悬浮控件仅保留很浅的暖纸材质，不使用彩色玻璃。
    static let browserChromeTint = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.145, green: 0.133, blue: 0.114, alpha: 0.78)
        }
        return UIColor(red: 0.984, green: 0.973, blue: 0.945, alpha: 0.86)
    }

    static let browserChromeBorder = UIColor { traits in
        let highContrast = traits.accessibilityContrast == .high
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.745, green: 0.698, blue: 0.616, alpha: highContrast ? 0.52 : 0.32)
        }
        return UIColor(
            red: 0.474,
            green: 0.435,
            blue: 0.365,
            alpha: highContrast ? 0.46 : 0.28
        )
    }

    static let browserChromeSeparator = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.745, green: 0.698, blue: 0.616, alpha: 0.16)
        }
        return UIColor(red: 0.376, green: 0.341, blue: 0.286, alpha: 0.14)
    }

    static let primaryText = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.957, green: 0.937, blue: 0.894, alpha: 1)
            : UIColor(red: 0.145, green: 0.145, blue: 0.133, alpha: 1)
    }
    static let secondaryText = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.729, green: 0.694, blue: 0.639, alpha: 1)
            : UIColor(red: 0.424, green: 0.408, blue: 0.373, alpha: 1)
    }
    static let tertiaryText = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.557, green: 0.525, blue: 0.471, alpha: 1)
            : UIColor(red: 0.584, green: 0.557, blue: 0.510, alpha: 1)
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
            return UIColor(red: 0.557, green: 0.518, blue: 0.447, alpha: 0.26)
        }
        return UIColor(red: 0.510, green: 0.475, blue: 0.412, alpha: 0.24)
    }
    static let opaqueSeparator = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.298, green: 0.278, blue: 0.243, alpha: 1)
            : UIColor(red: 0.824, green: 0.796, blue: 0.741, alpha: 1)
    }

    static let success = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.553, green: 0.682, blue: 0.506, alpha: 1)
            : UIColor(red: 0.333, green: 0.451, blue: 0.306, alpha: 1)
    }
    static let warning = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.902, green: 0.643, blue: 0.365, alpha: 1)
            : UIColor(red: 0.773, green: 0.478, blue: 0.165, alpha: 1)
    }
    static let danger = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.890, green: 0.455, blue: 0.404, alpha: 1)
            : UIColor(red: 0.718, green: 0.247, blue: 0.208, alpha: 1)
    }

    /// 空状态插图的中性填充，不与可操作的品牌琥珀争夺注意力。
    static let stateSymbol = secondaryText
    static let stateSymbolBackground = secondarySurface
}
