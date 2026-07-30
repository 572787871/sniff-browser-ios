import UIKit

final class LoadingStateView: UIView {
    private let indicator = UIActivityIndicatorView(style: .medium)
    private let messageLabel = UILabel()
    private let stackView = UIStackView()

    init(message: String = "正在加载…") {
        super.init(frame: .zero)
        buildView()
        setMessage(message)
        startAnimating()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildView()
    }

    func setMessage(_ message: String) {
        messageLabel.text = message
        accessibilityLabel = message
    }

    func startAnimating() {
        indicator.startAnimating()
        isHidden = false
        accessibilityTraits.insert(.updatesFrequently)
    }

    func stopAnimating(hide: Bool = true) {
        indicator.stopAnimating()
        isHidden = hide
        accessibilityTraits.remove(.updatesFrequently)
    }

    private func buildView() {
        isAccessibilityElement = true
        accessibilityIdentifier = "state.loading"

        indicator.color = AppColors.secondaryText
        indicator.hidesWhenStopped = true
        indicator.setContentHuggingPriority(.required, for: .horizontal)

        AppTypography.configure(messageLabel, style: .subheadline)
        messageLabel.textColor = AppColors.secondaryText
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.isAccessibilityElement = false

        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = AppSpacing.sm
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(indicator)
        stackView.addArrangedSubview(messageLabel)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: AppSpacing.xl),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -AppSpacing.xl)
        ])
    }
}
