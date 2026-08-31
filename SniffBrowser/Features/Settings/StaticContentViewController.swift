import SwiftUI
import UIKit

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

/// 法律、许可与关于页面使用 SwiftUI 排版，链接仍交给系统打开。
final class StaticContentViewController: BaseViewController {
    private let segments: [StaticContentSegment]

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
        installSwiftUI(
            StaticContentSwiftUIScreen(segments: segments),
            in: contentView
        )
    }
}

private struct StaticContentSwiftUIScreen: View {
    let segments: [StaticContentSegment]

    var body: some View {
        AppSwiftUIScreen {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        segmentView(segment)
                    }
                }
                .padding(20)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func segmentView(_ segment: StaticContentSegment) -> some View {
        switch segment.kind {
        case .heading:
            Text(segment.text)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppSwiftUIColors.primaryText)
                .padding(.top, 14)
                .padding(.bottom, 7)
                .accessibilityAddTraits(.isHeader)
        case .paragraph:
            Text(segment.text)
                .font(.body)
                .foregroundStyle(AppSwiftUIColors.primaryText)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Circle()
                    .fill(AppSwiftUIColors.accent)
                    .frame(width: 6, height: 6)
                Text(segment.text)
                    .font(.body)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 4)
            .padding(.bottom, 9)
        case .link:
            Link(
                destination: segment.link
                    ?? SettingsLegalContent.repositoryURL
            ) {
                Label(segment.text, systemImage: "arrow.up.right.square")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppSwiftUIColors.accent)
                    .padding(.vertical, 6)
            }
            .padding(.bottom, 10)
        case .spacer:
            Color.clear.frame(height: 8)
        }
    }
}
