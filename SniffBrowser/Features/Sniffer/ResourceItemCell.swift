import UIKit

final class ResourceListCell: UITableViewCell {
    static let reuseIdentifier = "ResourceListCell"
    private static let downloadActionIdentifier = UIAction.Identifier(
        "com.example.SniffBrowser.resource.download"
    )

    private let cardView = UIView()
    private let typeIconView = UIImageView()
    private let nameLabel = UILabel()
    private let metadataLabel = UILabel()
    private let domainLabel = UILabel()
    private let downloadButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)
    private var thumbnailTask: Task<Void, Never>?
    private var thumbnailToken: ResourceThumbnailToken?
    private var representedResourceID: UUID?
    private var iconWidthConstraint: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailTask?.cancel()
        thumbnailTask = nil
        thumbnailToken?.cancel()
        thumbnailToken = nil
        representedResourceID = nil
        typeIconView.image = nil
        moreButton.menu = nil
    }

    func configure(
        resource: DetectedResource,
        allowsThumbnailDiskCache: Bool,
        thumbnailRequestProvider: @escaping @MainActor () async -> URLRequest?,
        onCopy: @escaping () -> Void,
        onShare: @escaping () -> Void,
        onDetails: @escaping () -> Void,
        onPreview: (() -> Void)?,
        onDownload: (() -> Void)?
    ) {
        thumbnailTask?.cancel()
        thumbnailTask = nil
        thumbnailToken?.cancel()
        thumbnailToken = nil
        representedResourceID = resource.id
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
        typeIconView.backgroundColor = AppColors.accentFill
        iconWidthConstraint?.constant = resource.resourceType == .image ? 80 : 48
        typeIconView.contentMode = resource.resourceType == .image
            ? .scaleAspectFill
            : .center
        typeIconView.clipsToBounds = true
        if resource.resourceType == .image {
            let scale = UIScreen.main.scale
            thumbnailTask = Task { [weak self] in
                guard let request = await thumbnailRequestProvider(),
                      !Task.isCancelled
                else { return }
                let thumbnail = ResourceThumbnailRequest(
                    resourceID: resource.id,
                    tabID: resource.tabID,
                    request: request,
                    targetPixelSize: CGSize(
                        width: 80 * scale,
                        height: 64 * scale
                    ),
                    allowsDiskCache: allowsThumbnailDiskCache
                )
                self?.thumbnailToken = ResourceThumbnailLoader.shared.load(
                    thumbnail
                ) { [weak self] image in
                    guard let self,
                          self.representedResourceID == resource.id,
                          let image
                    else { return }
                    self.typeIconView.image = image
                    self.typeIconView.backgroundColor = AppColors.progressTrack
                }
            }
        }
        var menuActions: [UIMenuElement] = []
        if let onPreview {
            menuActions.append(UIAction(
                title: resource.resourceType == .image ? "预览图片" : "在线播放",
                image: UIImage(systemName: resource.resourceType == .image ? "photo" : "play.circle")
            ) { _ in onPreview() })
        }
        menuActions.append(contentsOf: [
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
        moreButton.menu = UIMenu(children: menuActions)
        moreButton.showsMenuAsPrimaryAction = true
        downloadButton.setImage(
            UIImage(systemName: resource.resourceType == .hls
                ? "arrow.down.circle"
                : "arrow.down.to.line"),
            for: .normal
        )
        downloadButton.accessibilityLabel = resource.resourceType == .hls
            ? "离线保存"
            : "下载"
        downloadButton.isEnabled = onDownload != nil
        downloadButton.alpha = onDownload == nil ? 0.35 : 1
        downloadButton.removeAction(
            identifiedBy: Self.downloadActionIdentifier,
            for: .touchUpInside
        )
        if let onDownload {
            downloadButton.addAction(
                UIAction(identifier: Self.downloadActionIdentifier) { _ in
                    onDownload()
                },
                for: .touchUpInside
            )
        }
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

        downloadButton.tintColor = AppColors.accent
        downloadButton.accessibilityLabel = "下载资源"

        let stack = UIStackView(
            arrangedSubviews: [typeIconView, labels, downloadButton, moreButton]
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
            typeIconView.heightAnchor.constraint(equalToConstant: 64),
            moreButton.widthAnchor.constraint(
                equalToConstant: AppMetrics.minimumTapSize
            ),
            moreButton.heightAnchor.constraint(
                equalToConstant: AppMetrics.minimumTapSize
            ),
            downloadButton.widthAnchor.constraint(
                equalToConstant: AppMetrics.minimumTapSize
            ),
            downloadButton.heightAnchor.constraint(
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
        iconWidthConstraint = typeIconView.widthAnchor.constraint(
            equalToConstant: 48
        )
        iconWidthConstraint?.isActive = true
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
