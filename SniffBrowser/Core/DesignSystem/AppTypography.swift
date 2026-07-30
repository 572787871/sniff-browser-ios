import UIKit

/// 全局文字层级。所有字体均使用 San Francisco 并响应 Dynamic Type。
enum AppTypography {
    static let largeTitle = font(for: .largeTitle, weight: .bold)
    static let pageTitle = font(for: .title1, weight: .semibold)
    static let title = font(for: .title2, weight: .semibold)
    static let title3 = font(for: .title3, weight: .semibold)
    static let headline = font(for: .headline, weight: .semibold)
    static let body = UIFont.preferredFont(forTextStyle: .body)
    static let emphasizedBody = font(for: .body, weight: .semibold)
    static let callout = UIFont.preferredFont(forTextStyle: .callout)
    static let subheadline = UIFont.preferredFont(forTextStyle: .subheadline)
    static let footnote = UIFont.preferredFont(forTextStyle: .footnote)
    static let caption = UIFont.preferredFont(forTextStyle: .caption1)
    static let caption2 = UIFont.preferredFont(forTextStyle: .caption2)

    /// 适用于地址和域名；仍使用系统字体，不引入第三方字形。
    static let address = UIFont.preferredFont(forTextStyle: .body)

    static func font(
        for textStyle: UIFont.TextStyle,
        weight: UIFont.Weight
    ) -> UIFont {
        let preferred = UIFont.preferredFont(forTextStyle: textStyle)
        let descriptor = preferred.fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight.rawValue]
        ])
        return UIFont(descriptor: descriptor, size: 0)
    }

    static func configure(_ label: UILabel, style: UIFont.TextStyle, weight: UIFont.Weight = .regular) {
        label.font = weight == .regular
            ? UIFont.preferredFont(forTextStyle: style)
            : font(for: style, weight: weight)
        label.adjustsFontForContentSizeCategory = true
    }
}
