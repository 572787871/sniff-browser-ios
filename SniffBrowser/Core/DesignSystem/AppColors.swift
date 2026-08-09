import UIKit

/// SniffBrowser 的语义颜色入口。
///
/// 页面不应直接保存解析后的颜色，也不应根据深浅模式自行分支。使用这些动态颜色，
/// 让 UIKit 在外观、增强对比度和辅助功能变化时自动重新解析。
enum AppColors {
    /// 管理页面的分组背景。
    static let background = UIColor.systemGroupedBackground
    static let canvas = background
    /// 浏览器搜索与建议层使用的冷调画布，不改变网页本身的背景。
    static let browserCanvas = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.063, green: 0.071, blue: 0.102, alpha: 1)
        }
        return UIColor(red: 0.961, green: 0.969, blue: 0.988, alpha: 1)
    }
    /// 无痕模式始终使用独立深色层级，在深色系统外观下也能与普通模式明显区分。
    /// 使用紫黑色调，与系统深色的灰蓝色调形成视觉差异。
    static let privateBrowsingBackground = UIColor(
        red: 0.055,
        green: 0.04,
        blue: 0.09,
        alpha: 1
    )
    static let privateBrowsingSurface = UIColor(
        red: 0.10,
        green: 0.07,
        blue: 0.16,
        alpha: 1
    )
    static let privateBrowsingChrome = UIColor(
        red: 0.08,
        green: 0.05,
        blue: 0.13,
        alpha: 1
    )
    /// 无痕模式强调色：紫蓝调，与系统蓝色区分。
    static let privateBrowsingAccent = UIColor(
        red: 0.55,
        green: 0.55,
        blue: 0.95,
        alpha: 1
    )
    /// 普通与无痕主页共用布局和画布，仅用该动态色强调无痕说明。
    static let privateBrowsingDescription = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.72, green: 0.72, blue: 0.96, alpha: 1)
        }
        return UIColor(red: 0.31, green: 0.27, blue: 0.58, alpha: 1)
    }

    /// 普通卡片与列表分组背景。
    static let surface = UIColor.secondarySystemGroupedBackground
    static let secondarySurface = surface
    static let tertiarySurface = UIColor.tertiarySystemGroupedBackground

    /// 浮层的轻透明动态背景。实际的毛玻璃应由 `AppMaterialView` 提供。
    static let elevatedSurface = UIColor { traits in
        UIColor.systemBackground
            .resolvedColor(with: traits)
            .withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.88 : 0.92)
    }

    /// Reduce Transparency 时供地址栏和工具栏使用的不透明回退色。
    static let chromeFallback = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.090, green: 0.098, blue: 0.137, alpha: 0.98)
        }
        return UIColor(red: 0.969, green: 0.976, blue: 0.996, alpha: 0.98)
    }

    /// 浏览器悬浮控件的冷调玻璃着色与光学边缘。
    static let browserChromeTint = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.19, green: 0.22, blue: 0.34, alpha: 0.38)
        }
        return UIColor(red: 0.82, green: 0.86, blue: 1.0, alpha: 0.22)
    }

    static let browserChromeBorder = UIColor { traits in
        let highContrast = traits.accessibilityContrast == .high
        if traits.userInterfaceStyle == .dark {
            return UIColor.white.withAlphaComponent(highContrast ? 0.34 : 0.20)
        }
        return UIColor(
            red: 0.24,
            green: 0.36,
            blue: 0.93,
            alpha: highContrast ? 0.34 : 0.18
        )
    }

    static let browserChromeSeparator = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor.white.withAlphaComponent(0.12)
        }
        return UIColor(red: 0.24, green: 0.36, blue: 0.70, alpha: 0.13)
    }

    static let primaryText = UIColor.label
    static let secondaryText = UIColor.secondaryLabel
    static let tertiaryText = UIColor.tertiaryLabel
    static let placeholderText = UIColor.placeholderText

    /// 蓝靛强调色：保持系统蓝的清晰度，同时加入预览方案中的轻微紫调。
    static let accent = UIColor { traits in
        let highContrast = traits.accessibilityContrast == .high
        if traits.userInterfaceStyle == .dark {
            return UIColor(
                red: highContrast ? 0.58 : 0.43,
                green: highContrast ? 0.67 : 0.56,
                blue: 1,
                alpha: 1
            )
        }
        return UIColor(
            red: highContrast ? 0.16 : 0.24,
            green: highContrast ? 0.26 : 0.36,
            blue: highContrast ? 0.80 : 0.93,
            alpha: 1
        )
    }
    static let accentFill = UIColor { traits in
        accent.resolvedColor(with: traits).withAlphaComponent(
            traits.userInterfaceStyle == .dark ? 0.18 : 0.11
        )
    }
    /// 强调色实心背景上的文字与图标颜色。
    static let accentContent = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.black : UIColor.white
    }
    static let browserChromeSelection = accentFill
    static let progressTrack = UIColor.systemFill

    static let separator = UIColor.separator.withAlphaComponent(0.5)
    static let opaqueSeparator = UIColor.opaqueSeparator

    static let success = UIColor.systemGreen
    static let warning = UIColor.systemOrange
    static let danger = UIColor.systemRed

    /// 空状态插图的中性填充，不与可操作的系统蓝争夺注意力。
    static let stateSymbol = UIColor.secondaryLabel
    static let stateSymbolBackground = UIColor.tertiarySystemFill
}
