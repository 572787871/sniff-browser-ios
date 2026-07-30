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

        accessibilityLabel = [
            configuration.title,
            configuration.message
        ].joined(separator: "，")
    }

    private func buildView() {
        layoutMargins = UIEdgeInsets(
            top: AppSpacing.xl,
            left: AppSpacing.xl,
            bottom: AppSpacing.xl,
            right: AppSpacing.xl
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
        addSubview(stackView)

        NSLayoutConstraint.activate([
            symbolContainer.widthAnchor.constraint(equalToConstant: 72),
            symbolContainer.heightAnchor.constraint(equalTo: symbolContainer.widthAnchor),
            symbolView.centerXAnchor.constraint(equalTo: symbolContainer.centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: symbolContainer.centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: AppMetrics.stateSymbolSize),
            symbolView.heightAnchor.constraint(equalTo: symbolView.widthAnchor),

            actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: AppMetrics.minimumTapSize),

            stackView.centerXAnchor.constraint(equalTo: layoutMarginsGuide.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: layoutMarginsGuide.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.topAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.bottomAnchor),
            stackView.widthAnchor.constraint(lessThanOrEqualToConstant: 440)
        ])
    }

    @objc
    private func actionPressed() {
        action?()
    }
}
