import UIKit

protocol NewTabViewDelegate: AnyObject {
  func newTabView(_ view: NewTabView, didSubmit text: String)
}

final class NewTabView: UIView {
  weak var delegate: NewTabViewDelegate?

  private let titleLabel = UILabel()
  private let welcomeLabel = UILabel()
  private let dateLabel = UILabel()
  private let searchMaterial = UIVisualEffectView(
    effect: UIBlurEffect(style: .systemThinMaterial)
  )
  private let searchImageView = UIImageView(image: UIImage(systemName: "magnifyingglass"))
  private let textField = UITextField()
  private let submitButton = UIButton(type: .system)

  override init(frame: CGRect) {
    super.init(frame: frame)
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }

  func focusSearch() {
    textField.becomeFirstResponder()
  }

  private func configure() {
    translatesAutoresizingMaskIntoConstraints = false
    backgroundColor = AppColors.background

    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.text = "嗅探浏览器"
    titleLabel.font = AppTypography.title
    titleLabel.textColor = AppColors.primaryText
    titleLabel.textAlignment = .center
    titleLabel.adjustsFontForContentSizeCategory = true

    welcomeLabel.translatesAutoresizingMaskIntoConstraints = false
    welcomeLabel.text = "从一次安静、专注的浏览开始"
    welcomeLabel.font = AppTypography.body
    welcomeLabel.textColor = AppColors.secondaryText
    welcomeLabel.textAlignment = .center
    welcomeLabel.numberOfLines = 0
    welcomeLabel.adjustsFontForContentSizeCategory = true

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.setLocalizedDateFormatFromTemplate("MMMMdEEEE")
    dateLabel.translatesAutoresizingMaskIntoConstraints = false
    dateLabel.text = formatter.string(from: Date())
    dateLabel.font = AppTypography.caption
    dateLabel.textColor = AppColors.tertiaryText
    dateLabel.textAlignment = .center
    dateLabel.adjustsFontForContentSizeCategory = true

    searchMaterial.translatesAutoresizingMaskIntoConstraints = false
    searchMaterial.layer.cornerRadius = AppRadius.input
    searchMaterial.layer.cornerCurve = .continuous
    searchMaterial.clipsToBounds = true
    searchMaterial.layer.borderWidth = 0.5
    searchMaterial.layer.borderColor = AppColors.separator.cgColor

    searchImageView.translatesAutoresizingMaskIntoConstraints = false
    searchImageView.tintColor = AppColors.secondaryText
    searchImageView.contentMode = .scaleAspectFit

    textField.translatesAutoresizingMaskIntoConstraints = false
    textField.font = AppTypography.body
    textField.textColor = AppColors.primaryText
    textField.tintColor = AppColors.accent
    textField.placeholder = "搜索或输入网址"
    textField.autocapitalizationType = .none
    textField.autocorrectionType = .no
    textField.keyboardType = .webSearch
    textField.returnKeyType = .search
    textField.delegate = self
    textField.accessibilityLabel = "新标签页搜索"

    var buttonConfiguration = UIButton.Configuration.plain()
    buttonConfiguration.image = UIImage(systemName: "arrow.right")
    submitButton.configuration = buttonConfiguration
    submitButton.tintColor = AppColors.accent
    submitButton.accessibilityLabel = "打开"
    submitButton.addTarget(
      self,
      action: #selector(submit),
      for: .touchUpInside
    )

    addSubview(titleLabel)
    addSubview(welcomeLabel)
    addSubview(dateLabel)
    addSubview(searchMaterial)
    searchMaterial.contentView.addSubview(searchImageView)
    searchMaterial.contentView.addSubview(textField)
    searchMaterial.contentView.addSubview(submitButton)

    let readable = readableContentGuide
    NSLayoutConstraint.activate([
      titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      titleLabel.centerYAnchor.constraint(
        equalTo: centerYAnchor,
        constant: -96
      ),
      titleLabel.leadingAnchor.constraint(
        greaterThanOrEqualTo: readable.leadingAnchor
      ),
      titleLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: readable.trailingAnchor
      ),
      welcomeLabel.topAnchor.constraint(
        equalTo: titleLabel.bottomAnchor,
        constant: AppSpacing.xs
      ),
      welcomeLabel.leadingAnchor.constraint(
        equalTo: readable.leadingAnchor,
        constant: AppSpacing.md
      ),
      welcomeLabel.trailingAnchor.constraint(
        equalTo: readable.trailingAnchor,
        constant: -AppSpacing.md
      ),
      dateLabel.topAnchor.constraint(
        equalTo: welcomeLabel.bottomAnchor,
        constant: AppSpacing.sm
      ),
      dateLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      searchMaterial.topAnchor.constraint(
        equalTo: dateLabel.bottomAnchor,
        constant: AppSpacing.xl
      ),
      searchMaterial.leadingAnchor.constraint(
        equalTo: readable.leadingAnchor,
        constant: AppSpacing.md
      ),
      searchMaterial.trailingAnchor.constraint(
        equalTo: readable.trailingAnchor,
        constant: -AppSpacing.md
      ),
      searchMaterial.heightAnchor.constraint(equalToConstant: 52),
      searchImageView.leadingAnchor.constraint(
        equalTo: searchMaterial.contentView.leadingAnchor,
        constant: AppSpacing.md
      ),
      searchImageView.centerYAnchor.constraint(
        equalTo: searchMaterial.contentView.centerYAnchor
      ),
      searchImageView.widthAnchor.constraint(equalToConstant: 18),
      searchImageView.heightAnchor.constraint(equalToConstant: 18),
      textField.leadingAnchor.constraint(
        equalTo: searchImageView.trailingAnchor,
        constant: AppSpacing.sm
      ),
      textField.trailingAnchor.constraint(
        equalTo: submitButton.leadingAnchor,
        constant: -AppSpacing.xs
      ),
      textField.topAnchor.constraint(equalTo: searchMaterial.contentView.topAnchor),
      textField.bottomAnchor.constraint(equalTo: searchMaterial.contentView.bottomAnchor),
      submitButton.trailingAnchor.constraint(
        equalTo: searchMaterial.contentView.trailingAnchor,
        constant: -AppSpacing.xs
      ),
      submitButton.centerYAnchor.constraint(
        equalTo: searchMaterial.contentView.centerYAnchor
      ),
      submitButton.widthAnchor.constraint(
        equalToConstant: AppMetrics.minimumTapSize
      ),
      submitButton.heightAnchor.constraint(
        equalToConstant: AppMetrics.minimumTapSize
      ),
    ])
  }

  @objc private func submit() {
    delegate?.newTabView(self, didSubmit: textField.text ?? "")
    textField.resignFirstResponder()
  }
}

extension NewTabView: UITextFieldDelegate {
  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    submit()
    return true
  }
}
