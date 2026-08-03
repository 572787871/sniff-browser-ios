import UIKit

/// SniffBrowser 的语义颜色入口。
///
/// 页面不应直接保存解析后的颜色，也不应根据深浅模式自行分支。使用这些动态颜色，
/// 让 UIKit 在外观、增强对比度和辅助功能变化时自动重新解析。
enum AppColors {
    /// 管理页面的分组背景。
    static let background = UIColor.systemGroupedBackground
    static let canvas = background
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
