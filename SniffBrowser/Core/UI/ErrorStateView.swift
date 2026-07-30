import UIKit

final class ErrorStateView: UIView {
    struct Configuration {
        let symbolName: String
        let title: String
        let message: String
        let retryTitle: String?

        init(
            symbolName: String = "exclamationmark.triangle.fill",
            title: String,
            message: String,
            retryTitle: String? = "重试"
        ) {
            self.symbolName = symbolName
            self.title = title
            self.message = message
            self.retryTitle = retryTitle
        }
    }

    private let symbolView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let stackView = UIStackView()
    private var retryAction: (() -> Void)?

    init(
        configuration: Configuration,
        retryAction: (() -> Void)? = nil
    ) {
        super.init(frame: .zero)
        buildView()
        configure(configuration, retryAction: retryAction)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildView()
    }

    func configure(
        _ configuration: Configuration,
        retryAction: (() -> Void)? = nil
    ) {
        self.retryAction = retryAction
        symbolView.image = UIImage(
            systemName: configuration.symbolName,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: AppMetrics.stateSymbolSize,
                weight: .regular
            )
        )
        titleLabel.text = configuration.title
        messageLabel.text = configuration.message

        var buttonConfiguration = UIButton.Configuration.tinted()
        buttonConfiguration.title = configuration.retryTitle
        buttonConfiguration.baseBackgroundColor = AppColors.accentFill
        buttonConfiguration.baseForegroundColor = AppColors.accent
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
        retryButton.configuration = buttonConfiguration
        retryButton.isHidden = configuration.retryTitle == nil || retryAction == nil
        retryButton.accessibilityLabel = configuration.retryTitle

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

        symbolView.tintColor = AppColors.danger
        symbolView.contentMode = .scaleAspectFit
        symbolView.isAccessibilityElement = false
        symbolView.translatesAutoresizingMaskIntoConstraints = false

        AppTypography.configure(titleLabel, style: .title3, weight: .semibold)
        titleLabel.textColor = AppColors.primaryText
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        AppTypography.configure(messageLabel, style: .subheadline)
        messageLabel.textColor = AppColors.secondaryText
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        retryButton.addTarget(self, action: #selector(retryPressed), for: .touchUpInside)
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.accessibilityIdentifier = "errorState.retry"

        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = AppSpacing.sm
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(symbolView)
        stackView.setCustomSpacing(AppSpacing.lg, after: symbolView)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(messageLabel)
        stackView.setCustomSpacing(AppSpacing.lg, after: messageLabel)
        stackView.addArrangedSubview(retryButton)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            symbolView.widthAnchor.constraint(equalToConstant: AppMetrics.stateSymbolSize),
            symbolView.heightAnchor.constraint(equalTo: symbolView.widthAnchor),
            retryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: AppMetrics.minimumTapSize),

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
    private func retryPressed() {
        retryAction?()
    }
}
