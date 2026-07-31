import UIKit

final class ResourceListCell: UITableViewCell {
    static let reuseIdentifier = "ResourceListCell"

    private let cardView = UIView()
    private let typeIconView = UIImageView()
    private let nameLabel = UILabel()
    private let metadataLabel = UILabel()
    private let domainLabel = UILabel()
    private let moreButton = UIButton(type: .system)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        moreButton.menu = nil
    }

    func configure(
        resource: DetectedResource,
        onCopy: @escaping () -> Void,
        onShare: @escaping () -> Void,
        onDetails: @escaping () -> Void
    ) {
        nameLabel.text = resource.fileName
        var metadata = [
            resource.fileExtension?.uppercased()
                ?? resource.resourceType.localizedTitle,
            resource.estimatedSize.map {
                ByteCountFormatter.string(
                    fromByteCount: $0,
                    countStyle: .file
                )
            } ?? "大小未知"
        ]
        if let width = resource.width, let height = resource.height {
            metadata.append("\(width)×\(height)")
        }
        if let duration = resource.duration, duration.isFinite, duration > 0 {
            let seconds = Int(duration.rounded())
            metadata.append(
                String(format: "%d:%02d", seconds / 60, seconds % 60)
            )
        }
        if let mime = resource.mimeType {
            metadata.append(mime)
        }
        metadataLabel.text = metadata.joined(separator: " · ")
        domainLabel.text = resource.canonicalURL.host
            ?? resource.sourcePageURL?.host
        typeIconView.image = UIImage(
            systemName: symbolName(for: resource.resourceType)
        )
        moreButton.menu = UIMenu(children: [
            UIAction(
                title: "复制链接",
                image: UIImage(systemName: "doc.on.doc")
            ) { _ in onCopy() },
            UIAction(
                title: "分享链接",
                image: UIImage(systemName: "square.and.arrow.up")
            ) { _ in onShare() },
            UIAction(
                title: "查看详细信息",
                image: UIImage(systemName: "info.circle")
            ) { _ in onDetails() }
        ])
        moreButton.showsMenuAsPrimaryAction = true
        accessibilityLabel = "\(resource.fileName)，\(metadataLabel.text ?? "")"
    }

    private func configureView() {
        backgroundColor = .clear
        selectionStyle = .none
        cardView.backgroundColor = AppColors.surface
        cardView.layer.cornerRadius = AppRadius.card
        cardView.layer.cornerCurve = .continuous
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        typeIconView.tintColor = AppColors.accent
        typeIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 23
        )
        typeIconView.contentMode = .center
        typeIconView.backgroundColor = AppColors.accentFill
        typeIconView.layer.cornerRadius = AppRadius.control
        typeIconView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.numberOfLines = 2
        metadataLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        metadataLabel.adjustsFontForContentSizeCategory = true
        metadataLabel.textColor = AppColors.secondaryText
        metadataLabel.numberOfLines = 2
        domainLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        domainLabel.adjustsFontForContentSizeCategory = true
        domainLabel.textColor = AppColors.tertiaryText
        domainLabel.lineBreakMode = .byTruncatingMiddle

        let labels = UIStackView(
            arrangedSubviews: [nameLabel, metadataLabel, domainLabel]
        )
        labels.axis = .vertical
        labels.spacing = 3
        labels.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )

        moreButton.setImage(
            UIImage(systemName: "ellipsis.circle"),
            for: .normal
        )
        moreButton.accessibilityLabel = "资源操作"

        let stack = UIStackView(
            arrangedSubviews: [typeIconView, labels, moreButton]
        )
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = AppSpacing.sm
        stack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(stack)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: AppSpacing.xxs
            ),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -AppSpacing.xxs
            ),
            typeIconView.widthAnchor.constraint(equalToConstant: 48),
            typeIconView.heightAnchor.constraint(equalToConstant: 48),
            moreButton.widthAnchor.constraint(
                equalToConstant: AppMetrics.minimumTapSize
            ),
            moreButton.heightAnchor.constraint(
                equalToConstant: AppMetrics.minimumTapSize
            ),
            stack.topAnchor.constraint(
                equalTo: cardView.topAnchor,
                constant: AppSpacing.sm
            ),
            stack.leadingAnchor.constraint(
                equalTo: cardView.leadingAnchor,
                constant: AppSpacing.sm
            ),
            stack.trailingAnchor.constraint(
                equalTo: cardView.trailingAnchor,
                constant: -AppSpacing.xs
            ),
            stack.bottomAnchor.constraint(
                equalTo: cardView.bottomAnchor,
                constant: -AppSpacing.sm
            )
        ])
    }

    private func symbolName(for type: ResourceType) -> String {
        switch type {
        case .video: return "film"
        case .audio: return "waveform"
        case .hls: return "dot.radiowaves.left.and.right"
        case .image: return "photo"
        case .document: return "doc.text"
        case .subtitle: return "captions.bubble"
        case .archive: return "archivebox"
        case .other: return "doc"
        }
    }
}
