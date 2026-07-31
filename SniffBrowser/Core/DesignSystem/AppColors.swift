import UIKit

/// SniffBrowser 的语义颜色入口。
///
/// 页面不应直接保存解析后的颜色，也不应根据深浅模式自行分支。使用这些动态颜色，
/// 让 UIKit 在外观、增强对比度和辅助功能变化时自动重新解析。
enum AppColors {
    /// 管理页面的分组背景。
    static let background = UIColor.systemGroupedBackground
    static let canvas = background
    static let privateBrowsingBackground = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(
                red: 0.075,
                green: 0.075,
                blue: 0.09,
                alpha: 1
            )
        }
        return UIColor(
            red: 0.92,
            green: 0.92,
            blue: 0.95,
            alpha: 1
        )
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
        let color = UIColor.secondarySystemBackground.resolvedColor(with: traits)
        return color.withAlphaComponent(0.98)
    }

    static let primaryText = UIColor.label
    static let secondaryText = UIColor.secondaryLabel
    static let tertiaryText = UIColor.tertiaryLabel
    static let placeholderText = UIColor.placeholderText

    static let accent = UIColor.systemBlue
    static let accentFill = UIColor.systemBlue.withAlphaComponent(0.12)
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
