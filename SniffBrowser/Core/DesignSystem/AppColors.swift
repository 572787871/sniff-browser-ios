import UIKit

/// SniffBrowser 的语义颜色入口。
///
/// 页面不应直接保存解析后的颜色，也不应根据深浅模式自行分支。使用这些动态颜色，
/// 让 UIKit 在外观、增强对比度和辅助功能变化时自动重新解析。
enum AppColors {
    /// 使用系统分组画布，让浅色、深色、增强对比度与未来系统外观自动适配。
    static let background = UIColor.systemGroupedBackground
    static let canvas = background
    /// 搜索与建议层沿用同一画布色，不改变网页本身的背景。
    static let browserCanvas = background
    /// 无痕模式使用更深的蓝黑色，与普通深色模式保持可辨识差异。
    static let privateBrowsingBackground = UIColor.black
    static let privateBrowsingSurface = UIColor.secondarySystemBackground
    /// 无痕主页仍使用普通画布，只让搜索控件保持系统深色表面以明确模式差异。
    static let privateBrowsingChrome = UIColor { _ in
        UIColor.secondarySystemBackground.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .dark)
        )
    }
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

    /// 平面内容只使用不透明系统表面；玻璃仅由真正重叠的 chrome / sheet 提供。
    static let surface = UIColor.secondarySystemGroupedBackground
    static let secondarySurface = UIColor.secondarySystemFill
    static let tertiarySurface = UIColor.tertiarySystemFill

    /// 浮层的轻透明动态背景。实际的毛玻璃应由 `AppMaterialView` 提供。
    static let elevatedSurface = UIColor { traits in
        surface
            .resolvedColor(with: traits)
            .withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.88 : 0.92)
    }

    /// Reduce Transparency 时供地址栏和工具栏使用的不透明回退色。
    static let chromeFallback = UIColor.secondarySystemBackground

    /// 浏览器悬浮控件使用低饱和蓝灰玻璃，不与网页内容争夺注意力。
    static let browserChromeTint = UIColor { traits in
        UIColor.systemBackground
            .resolvedColor(with: traits)
            .withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.78 : 0.82)
    }

    static let browserChromeBorder = UIColor.separator

    static let browserChromeSeparator = UIColor.separator

    static let primaryText = UIColor.label
    static let secondaryText = UIColor.secondaryLabel
    static let tertiaryText = UIColor.tertiaryLabel
    static let placeholderText = UIColor.placeholderText

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
    static let progressTrack = UIColor.systemFill

    static let separator = UIColor.separator
    static let opaqueSeparator = UIColor.opaqueSeparator

    static let success = UIColor.systemGreen
    static let warning = UIColor.systemOrange
    static let danger = UIColor.systemRed

    /// 空状态插图使用低饱和中性色，不与可操作主题色争夺注意力。
    static let stateSymbol = tertiaryText
    static let stateSymbolBackground = tertiarySurface
}
