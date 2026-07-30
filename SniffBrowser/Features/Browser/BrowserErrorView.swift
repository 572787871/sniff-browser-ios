import UIKit

final class BrowserErrorView: UIView {
  var onRetry: (() -> Void)?

  private let symbolView = UIImageView()
  private let titleLabel = UILabel()
  private let messageLabel = UILabel()
  private let retryButton = UIButton(type: .system)

  override init(frame: CGRect) {
    super.init(frame: frame)
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }

  func apply(_ error: BrowserDisplayError) {
    symbolView.image = UIImage(systemName: error.symbolName)
    titleLabel.text = error.title
    messageLabel.text = error.message
    retryButton.isHidden = !error.canRetry
    accessibilityLabel = "\(error.title)。\(error.message)"
  }

  private func configure() {
    translatesAutoresizingMaskIntoConstraints = false
    backgroundColor = AppColors.background

    symbolView.translatesAutoresizingMaskIntoConstraints = false
    symbolView.tintColor = AppColors.secondaryText
    symbolView.contentMode = .scaleAspectFit

    titleLabel.font = AppTypography.title
    titleLabel.textColor = AppColors.primaryText
    titleLabel.textAlignment = .center
    titleLabel.numberOfLines = 0
    titleLabel.adjustsFontForContentSizeCategory = true

    messageLabel.font = AppTypography.body
    messageLabel.textColor = AppColors.secondaryText
    messageLabel.textAlignment = .center
    messageLabel.numberOfLines = 0
    messageLabel.adjustsFontForContentSizeCategory = true

    var configuration = UIButton.Configuration.filled()
    configuration.title = "重试"
    configuration.cornerStyle = .medium
    retryButton.configuration = configuration
    retryButton.addTarget(self, action: #selector(retry), for: .touchUpInside)

    let stack = UIStackView(
      arrangedSubviews: [symbolView, titleLabel, messageLabel, retryButton]
    )
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = AppSpacing.md
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: AppSpacing.xl),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -AppSpacing.xl),
      symbolView.widthAnchor.constraint(equalToConstant: 46),
      symbolView.heightAnchor.constraint(equalToConstant: 46),
      retryButton.heightAnchor.constraint(
        greaterThanOrEqualToConstant: AppMetrics.minimumTapSize
      ),
    ])
  }

  @objc private func retry() {
    onRetry?()
  }
}
