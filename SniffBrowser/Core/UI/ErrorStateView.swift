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
    private let scrollView = UIScrollView()
    private let contentContainer = UIView()
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

        var elements: [Any] = [titleLabel, messageLabel]
        if !retryButton.isHidden {
            elements.append(retryButton)
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

            symbolView.widthAnchor.constraint(equalToConstant: AppMetrics.stateSymbolSize),
            symbolView.heightAnchor.constraint(equalTo: symbolView.widthAnchor),
            retryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: AppMetrics.minimumTapSize),

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
    private func retryPressed() {
        retryAction?()
    }
}
