import UIKit

@MainActor
protocol NewTabViewDelegate: AnyObject {
  func newTabView(_ view: NewTabView, didSubmit text: String)
}

final class NewTabView: UIView {
  weak var delegate: NewTabViewDelegate?

  private let titleLabel = UILabel()
  private let welcomeLabel = UILabel()
  private let dateLabel = UILabel()
  private let scrollView = UIScrollView()
  private let contentContainer = UIView()
  private let contentStack = UIStackView()
  private let searchMaterial = AppMaterialView(
    style: .systemThinMaterial,
    fallbackColor: AppColors.chromeFallback
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

  override func didMoveToWindow() {
    super.didMoveToWindow()
    updateResolvedColors()
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

    searchImageView.translatesAutoresizingMaskIntoConstraints = false
    searchImageView.tintColor = AppColors.secondaryText
    searchImageView.contentMode = .scaleAspectFit

    textField.translatesAutoresizingMaskIntoConstraints = false
    textField.font = AppTypography.body
    textField.adjustsFontForContentSizeCategory = true
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

    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.alwaysBounceVertical = false
    scrollView.keyboardDismissMode = .interactive
    scrollView.showsVerticalScrollIndicator = false
    addSubview(scrollView)

    contentContainer.translatesAutoresizingMaskIntoConstraints = false
    scrollView.addSubview(contentContainer)

    contentStack.translatesAutoresizingMaskIntoConstraints = false
    contentStack.axis = .vertical
    contentStack.alignment = .fill
    contentStack.spacing = AppSpacing.xs
    contentStack.addArrangedSubview(titleLabel)
    contentStack.addArrangedSubview(welcomeLabel)
    contentStack.setCustomSpacing(AppSpacing.sm, after: welcomeLabel)
    contentStack.addArrangedSubview(dateLabel)
    contentStack.setCustomSpacing(AppSpacing.xl, after: dateLabel)
    contentStack.addArrangedSubview(searchMaterial)
    contentContainer.addSubview(contentStack)

    searchMaterial.contentView.addSubview(searchImageView)
    searchMaterial.contentView.addSubview(textField)
    searchMaterial.contentView.addSubview(submitButton)

    let centerConstraint = contentStack.centerYAnchor.constraint(
      equalTo: contentContainer.centerYAnchor,
      constant: -AppSpacing.xxl
    )
    centerConstraint.priority = .defaultHigh
    let viewportHeightConstraint = contentContainer.heightAnchor.constraint(
      equalTo: scrollView.frameLayoutGuide.heightAnchor
    )
    viewportHeightConstraint.priority = .defaultLow
    let preferredWidthConstraint = contentStack.widthAnchor.constraint(
      equalTo: contentContainer.widthAnchor,
      constant: -(AppSpacing.xl * 2)
    )
    preferredWidthConstraint.priority = .defaultHigh
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

      contentStack.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
      centerConstraint,
      contentStack.topAnchor.constraint(
        greaterThanOrEqualTo: contentContainer.topAnchor,
        constant: AppSpacing.xl
      ),
      contentStack.bottomAnchor.constraint(
        lessThanOrEqualTo: contentContainer.bottomAnchor,
        constant: -AppSpacing.xl
      ),
      contentStack.leadingAnchor.constraint(
        greaterThanOrEqualTo: contentContainer.leadingAnchor,
        constant: AppSpacing.xl
      ),
      contentStack.trailingAnchor.constraint(
        lessThanOrEqualTo: contentContainer.trailingAnchor,
        constant: -AppSpacing.xl
      ),
      preferredWidthConstraint,
      contentStack.widthAnchor.constraint(
        lessThanOrEqualToConstant: AppMetrics.maximumReadableWidth
      ),

      searchMaterial.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
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
    updateResolvedColors()
    registerForTraitChanges([
      UITraitUserInterfaceStyle.self,
      UITraitAccessibilityContrast.self,
    ]) { (view: NewTabView, _) in
      view.updateResolvedColors()
    }
  }

  private func updateResolvedColors() {
    searchMaterial.layer.borderColor = AppColors.separator
      .resolvedColor(with: traitCollection)
      .cgColor
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
