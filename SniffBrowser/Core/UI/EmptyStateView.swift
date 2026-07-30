import UIKit

final class EmptyStateView: UIView {
    struct Configuration {
        let symbolName: String
        let title: String
        let message: String
        let actionTitle: String?

        init(
            symbolName: String,
            title: String,
            message: String,
            actionTitle: String? = nil
        ) {
            self.symbolName = symbolName
            self.title = title
            self.message = message
            self.actionTitle = actionTitle
        }
    }

    private let symbolContainer = UIView()
    private let symbolView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let stackView = UIStackView()
    private let scrollView = UIScrollView()
    private let contentContainer = UIView()
    private var action: (() -> Void)?

    init(
        configuration: Configuration,
        action: (() -> Void)? = nil
    ) {
        super.init(frame: .zero)
        buildView()
        configure(configuration, action: action)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildView()
    }

    func configure(
        _ configuration: Configuration,
        action: (() -> Void)? = nil
    ) {
        self.action = action

        symbolView.image = UIImage(
            systemName: configuration.symbolName,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: AppMetrics.stateSymbolSize,
                weight: .regular
            )
        )
        titleLabel.text = configuration.title
        messageLabel.text = configuration.message

        var buttonConfiguration = UIButton.Configuration.filled()
        buttonConfiguration.title = configuration.actionTitle
        buttonConfiguration.baseBackgroundColor = AppColors.accent
        buttonConfiguration.baseForegroundColor = .white
        buttonConfiguration.cornerStyle = .medium
        buttonConfiguration.contentInsets = NSDirectionalEdgeInsets(
            top: AppSpacing.sm,
            leading: AppSpacing.lg,
            bottom: AppSpacing.sm,
            trailing: AppSpacing.lg
        )
        buttonConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = AppTypography.headline
            return attributes
        }
        actionButton.configuration = buttonConfiguration
        actionButton.isHidden = configuration.actionTitle == nil || action == nil
        actionButton.accessibilityLabel = configuration.actionTitle

        var elements: [Any] = [titleLabel, messageLabel]
        if !actionButton.isHidden {
            elements.append(actionButton)
        }
        accessibilityElements = elements
    }

    private func buildView() {
        isAccessibilityElement = false
        contentContainer.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: AppSpacing.xl,
            leading: AppSpacing.xl,
            bottom: AppSpacing.xl,
            trailing: AppSpacing.xl
        )

        symbolContainer.backgroundColor = AppColors.stateSymbolBackground
        symbolContainer.layer.cornerRadius = AppRadius.card
        symbolContainer.translatesAutoresizingMaskIntoConstraints = false
        symbolContainer.isAccessibilityElement = false

        symbolView.tintColor = AppColors.stateSymbol
        symbolView.contentMode = .scaleAspectFit
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        symbolView.isAccessibilityElement = false
        symbolContainer.addSubview(symbolView)

        AppTypography.configure(titleLabel, style: .title3, weight: .semibold)
        titleLabel.textColor = AppColors.primaryText
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        AppTypography.configure(messageLabel, style: .subheadline)
        messageLabel.textColor = AppColors.secondaryText
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        actionButton.addTarget(self, action: #selector(actionPressed), for: .touchUpInside)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.accessibilityIdentifier = "emptyState.action"

        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = AppSpacing.sm
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(symbolContainer)
        stackView.setCustomSpacing(AppSpacing.lg, after: symbolContainer)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(messageLabel)
        stackView.setCustomSpacing(AppSpacing.lg, after: messageLabel)
        stackView.addArrangedSubview(actionButton)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = false
        addSubview(scrollView)

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentContainer)
        contentContainer.addSubview(stackView)

        let centerConstraint = stackView.centerYAnchor.constraint(
            equalTo: contentContainer.centerYAnchor
        )
        centerConstraint.priority = .defaultHigh
        let viewportHeightConstraint = contentContainer.heightAnchor.constraint(
            equalTo: scrollView.frameLayoutGuide.heightAnchor
        )
        viewportHeightConstraint.priority = .defaultLow

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentContainer.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor
            ),
            contentContainer.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor
            ),
            contentContainer.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor
            ),
            contentContainer.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor
            ),
            contentContainer.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor
            ),
            contentContainer.heightAnchor.constraint(
                greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor
            ),
            viewportHeightConstraint,

            symbolContainer.widthAnchor.constraint(equalToConstant: 72),
            symbolContainer.heightAnchor.constraint(equalTo: symbolContainer.widthAnchor),
            symbolView.centerXAnchor.constraint(equalTo: symbolContainer.centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: symbolContainer.centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: AppMetrics.stateSymbolSize),
            symbolView.heightAnchor.constraint(equalTo: symbolView.widthAnchor),

            actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: AppMetrics.minimumTapSize),

            stackView.centerXAnchor.constraint(
                equalTo: contentContainer.layoutMarginsGuide.centerXAnchor
            ),
            centerConstraint,
            stackView.leadingAnchor.constraint(
                greaterThanOrEqualTo: contentContainer.layoutMarginsGuide.leadingAnchor
            ),
            stackView.trailingAnchor.constraint(
                lessThanOrEqualTo: contentContainer.layoutMarginsGuide.trailingAnchor
            ),
            stackView.topAnchor.constraint(
                greaterThanOrEqualTo: contentContainer.layoutMarginsGuide.topAnchor
            ),
            stackView.bottomAnchor.constraint(
                lessThanOrEqualTo: contentContainer.layoutMarginsGuide.bottomAnchor
            ),
            stackView.widthAnchor.constraint(lessThanOrEqualToConstant: 440)
        ])
    }

    @objc
    private func actionPressed() {
        action?()
    }
}
