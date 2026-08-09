import UIKit

/// 少量、语义化的阴影样式。普通内容卡片不应使用阴影。
struct AppShadow {
    let opacity: Float
    let radius: CGFloat
    let offset: CGSize

    static let floating = AppShadow(
        opacity: 0.065,
        radius: 12,
        offset: CGSize(width: 0, height: 3)
    )

    /// 地址栏与浏览器工具栏使用的更柔和、扩散更广的玻璃阴影。
    static let browserChrome = AppShadow(
        opacity: 0.075,
        radius: 14,
        offset: CGSize(width: 0, height: 4)
    )

    static let sheet = AppShadow(
        opacity: 0.10,
        radius: 20,
        offset: CGSize(width: 0, height: 7)
    )

    func apply(to view: UIView) {
        view.layer.shadowColor = UIColor.black.cgColor
        let appearanceOpacity = view.traitCollection.userInterfaceStyle == .dark
            ? opacity * 0.6
            : opacity
        view.layer.shadowOpacity = UIAccessibility.isDarkerSystemColorsEnabled
            ? min(appearanceOpacity + 0.04, 0.22)
            : appearanceOpacity
        view.layer.shadowRadius = radius
        view.layer.shadowOffset = offset
        view.layer.masksToBounds = false
    }

    static func remove(from view: UIView) {
        view.layer.shadowOpacity = 0
        view.layer.shadowRadius = 0
        view.layer.shadowOffset = .zero
        view.layer.shadowPath = nil
    }
}
