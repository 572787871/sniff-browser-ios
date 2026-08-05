import UIKit

/// 静态文本内容片段，用于隐私政策、条款等说明页。
struct StaticContentSegment {
    enum Kind {
        case heading
        case paragraph
        case bullet
        case link
        case spacer
    }

    let kind: Kind
    let text: String
    let link: URL?

    init(kind: Kind, text: String, link: URL? = nil) {
        self.kind = kind
        self.text = text
        self.link = link
    }
}

/// 通用静态内容页：滚动文本，支持标题、段落、列表与可点击链接。
final class StaticContentViewController: BaseViewController {
    private let segments: [StaticContentSegment]
    private let textView = UITextView()
    private let contentPadding: CGFloat = 20

    init(
        title: String,
        segments: [StaticContentSegment],
        prefersLargeTitle: Bool = false
    ) {
        self.segments = segments
        super.init(title: title, prefersLargeTitle: prefersLargeTitle)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureTextView()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        textView.attributedText = Self.attributedText(for: segments)
    }

    private func configureTextView() {
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.showsVerticalScrollIndicator = true
        textView.textContainerInset = UIEdgeInsets(
            top: contentPadding,
            left: contentPadding,
            bottom: contentPadding,
            right: contentPadding
        )
        textView.textContainer.lineFragmentPadding = 0
        textView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: contentView.topAnchor),
            textView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        textView.attributedText = Self.attributedText(for: segments)
    }

    private static func attributedText(
        for segments: [StaticContentSegment]
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for segment in segments {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            paragraph.paragraphSpacing = 10
            switch segment.kind {
            case .heading:
                paragraph.paragraphSpacing = 6
                result.append(
                    NSAttributedString(
                        string: segment.text + "\n",
                        attributes: [
                            .font: AppTypography.title3,
                            .foregroundColor: AppColors.primaryText,
                            .paragraphStyle: paragraph,
                        ]
                    )
                )
            case .paragraph:
                result.append(
                    NSAttributedString(
                        string: segment.text + "\n",
                        attributes: textAttributes(paragraph: paragraph)
                    )
                )
            case .bullet:
                result.append(
                    NSAttributedString(
                        string: "• " + segment.text + "\n",
                        attributes: textAttributes(paragraph: paragraph)
                    )
                )
            case .link:
                let url = segment.link
                    ?? URL(string: "https://github.com/572787871/sniff-browser-ios")!
                result.append(
                    NSAttributedString(
                        string: segment.text + "\n",
                        attributes: [
                            .font: UIFont.preferredFont(forTextStyle: .body),
                            .foregroundColor: AppColors.accent,
                            .link: url,
                            .underlineStyle: NSUnderlineStyle.single.rawValue,
                            .paragraphStyle: paragraph,
                        ]
                    )
                )
            case .spacer:
                result.append(NSAttributedString(string: "\n"))
            }
        }
        return result
    }

    private static func textAttributes(
        paragraph: NSMutableParagraphStyle
    ) -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: AppColors.primaryText,
            .paragraphStyle: paragraph,
        ]
    }
}
