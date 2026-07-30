import UIKit

/// 跨页面共享的控件尺寸。布局仍需服从 Safe Area 与 Dynamic Type。
enum AppMetrics {
    static let minimumTapSize: CGFloat = 44
    static let compactButtonHeight: CGFloat = 36
    static let primaryButtonHeight: CGFloat = 48

    static let navigationIconSize: CGFloat = 19
    static let toolbarIconSize: CGFloat = 21
    static let stateSymbolSize: CGFloat = 44

    static let addressBarHeight: CGFloat = 48
    static let toolbarHeight: CGFloat = 58
    static let progressHeight: CGFloat = 2
    static let separatorHeight: CGFloat = 1 / UIScreen.main.scale

    static let pageHorizontalInset = AppSpacing.md
    static let cardContentInset = AppSpacing.md
    static let maximumReadableWidth: CGFloat = 620
}
