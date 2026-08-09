import UIKit

@MainActor
protocol NewTabViewDelegate: AnyObject {
  func newTabViewDidBeginEditing(_ view: NewTabView)
  func newTabView(_ view: NewTabView, didSubmit text: String)
}

final class NewTabView: UIView {
  weak var delegate: NewTabViewDelegate?

  private let logoContainer = UIView()
  private let logoView = NewTabLogoView()
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
  private var isPrivateMode = false

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
    delegate?.newTabViewDidBeginEditing(self)
  }

  func setPrivateMode(_ isPrivate: Bool) {
    isPrivateMode = isPrivate
    overrideUserInterfaceStyle = .unspecified
    backgroundColor = AppColors.background
    titleLabel.text = isPrivate ? "无痕浏览" : "嗅探浏览器"
    welcomeLabel.text = isPrivate
      ? "不会保存浏览历史、搜索记录或自动填充信息；下载和主动收藏仍会保留。无痕模式不会让你在网络上匿名。"
      : "从一次安静、专注的浏览开始"
    refreshContentPreferences()
    searchMaterial.overrideUserInterfaceStyle = isPrivate ? .dark : .unspecified
    accessibilityLabel = isPrivate
      ? "无痕浏览。无痕模式不会让你在网络上匿名。"
      : nil
    updateResolvedColors()
  }

  /// 根据设置决定是否显示问候语与日期，设置页变更后回到新标签页时刷新。
  func refreshContentPreferences() {
    let preferences = BrowserPreferences()
    welcomeLabel.isHidden = !preferences.newTabShowsWelcome
    dateLabel.isHidden = !preferences.newTabShowsDate
  }

  private func configure() {
    translatesAutoresizingMaskIntoConstraints = false
    backgroundColor = AppColors.background

    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.text = "嗅探浏览器"
    titleLabel.font = AppTypography.title
    titleLabel.textColor = AppColors.primaryText
    titleLabel.textAlignment = .center
    titleLabel.numberOfLines = 1
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.accessibilityIdentifier = "newTab.title"
    titleLabel.setContentCompressionResistancePriority(
      .required,
      for: .horizontal
    )

    logoContainer.translatesAutoresizingMaskIntoConstraints = false
    logoView.translatesAutoresizingMaskIntoConstraints = false
    logoView.accessibilityLabel = "嗅探浏览器图标"
    logoView.accessibilityIdentifier = "newTab.logo"
    logoContainer.addSubview(logoView)

    welcomeLabel.translatesAutoresizingMaskIntoConstraints = false
    welcomeLabel.text = "从一次安静、专注的浏览开始"
    welcomeLabel.font = AppTypography.body
    welcomeLabel.textColor = AppColors.secondaryText
    welcomeLabel.textAlignment = .center
    welcomeLabel.numberOfLines = 0
    welcomeLabel.adjustsFontForContentSizeCategory = true
    welcomeLabel.accessibilityIdentifier = "newTab.description"
    welcomeLabel.setContentCompressionResistancePriority(
      .defaultHigh,
      for: .horizontal
    )

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.setLocalizedDateFormatFromTemplate("MMMMdEEEE")
    dateLabel.translatesAutoresizingMaskIntoConstraints = false
    dateLabel.text = formatter.string(from: Date())
    dateLabel.font = AppTypography.caption
    dateLabel.textColor = AppColors.tertiaryText
    dateLabel.textAlignment = .center
    dateLabel.numberOfLines = 1
    dateLabel.adjustsFontForContentSizeCategory = true
    dateLabel.accessibilityIdentifier = "newTab.date"
    dateLabel.setContentCompressionResistancePriority(
      .required,
      for: .horizontal
    )

    searchMaterial.translatesAutoresizingMaskIntoConstraints = false
    searchMaterial.layer.cornerRadius = AppRadius.input
    searchMaterial.layer.cornerCurve = .continuous
    searchMaterial.clipsToBounds = true
    searchMaterial.layer.borderWidth = 0.5
    searchMaterial.contentView.accessibilityIdentifier = "newTab.searchSurface"

    searchImageView.translatesAutoresizingMaskIntoConstraints = false
    searchImageView.tintColor = AppColors.secondaryText
    searchImageView.contentMode = .scaleAspectFit
    searchImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
      pointSize: 20,
      weight: .regular
    )

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
    textField.accessibilityIdentifier = "newTab.searchField"
    textField.addTarget(
      self,
      action: #selector(textDidChange),
      for: .editingChanged
    )

    var buttonConfiguration = UIButton.Configuration.plain()
    buttonConfiguration.image = UIImage(
      systemName: "arrow.right",
      withConfiguration: UIImage.SymbolConfiguration(
        pointSize: 19,
        weight: .semibold
      )
    )
    buttonConfiguration.contentInsets = .zero
    submitButton.translatesAutoresizingMaskIntoConstraints = false
    submitButton.configuration = buttonConfiguration
    submitButton.tintColor = AppColors.accent
    submitButton.accessibilityLabel = "打开"
    submitButton.accessibilityIdentifier = "newTab.submit"
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
    contentStack.addArrangedSubview(logoContainer)
    contentStack.setCustomSpacing(AppSpacing.sm, after: logoContainer)
    contentStack.addArrangedSubview(titleLabel)
    contentStack.setCustomSpacing(AppSpacing.lg, after: titleLabel)
    contentStack.addArrangedSubview(searchMaterial)
    contentStack.setCustomSpacing(AppSpacing.lg, after: searchMaterial)
    contentStack.addArrangedSubview(welcomeLabel)
    contentStack.setCustomSpacing(AppSpacing.sm, after: welcomeLabel)
    contentStack.addArrangedSubview(dateLabel)
    contentContainer.addSubview(contentStack)

    searchMaterial.contentView.addSubview(searchImageView)
    searchMaterial.contentView.addSubview(textField)
    searchMaterial.contentView.addSubview(submitButton)

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

      contentStack.topAnchor.constraint(
        equalTo: contentContainer.topAnchor,
        constant: AppSpacing.xxl
      ),
      contentStack.bottomAnchor.constraint(
        lessThanOrEqualTo: contentContainer.bottomAnchor,
        constant: -AppSpacing.xl
      ),
      contentStack.leadingAnchor.constraint(
        equalTo: contentContainer.leadingAnchor,
        constant: AppSpacing.xl
      ),
      contentStack.trailingAnchor.constraint(
        equalTo: contentContainer.trailingAnchor,
        constant: -AppSpacing.xl
      ),

      logoContainer.heightAnchor.constraint(equalToConstant: 72),
      logoView.centerXAnchor.constraint(equalTo: logoContainer.centerXAnchor),
      logoView.centerYAnchor.constraint(equalTo: logoContainer.centerYAnchor),
      logoView.widthAnchor.constraint(equalToConstant: 72),
      logoView.heightAnchor.constraint(equalTo: logoView.widthAnchor),

      searchMaterial.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
      searchImageView.leadingAnchor.constraint(
        equalTo: searchMaterial.contentView.leadingAnchor,
        constant: AppSpacing.md
      ),
      searchImageView.centerYAnchor.constraint(
        equalTo: searchMaterial.contentView.centerYAnchor
      ),
      searchImageView.widthAnchor.constraint(equalToConstant: 24),
      searchImageView.heightAnchor.constraint(equalToConstant: 24),
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
    updateSubmitButton()
    updateResolvedColors()
    registerForTraitChanges([
      UITraitUserInterfaceStyle.self,
      UITraitAccessibilityContrast.self,
    ]) { (view: NewTabView, _) in
      view.updateResolvedColors()
    }
  }

  private func updateResolvedColors() {
    let searchPrimary = isPrivateMode
      ? UIColor.white.withAlphaComponent(0.96)
      : AppColors.primaryText
    let searchSecondary = isPrivateMode
      ? UIColor.white.withAlphaComponent(0.68)
      : AppColors.secondaryText

    titleLabel.textColor = isPrivateMode
      ? AppColors.privateBrowsingDescription
      : AppColors.primaryText
    welcomeLabel.textColor = isPrivateMode
      ? AppColors.privateBrowsingDescription.withAlphaComponent(0.82)
      : AppColors.secondaryText
    dateLabel.textColor = AppColors.tertiaryText
    searchImageView.tintColor = searchSecondary
    textField.textColor = searchPrimary
    textField.tintColor = isPrivateMode
      ? AppColors.privateBrowsingAccent
      : AppColors.accent
    textField.attributedPlaceholder = NSAttributedString(
      string: "搜索或输入网址",
      attributes: [.foregroundColor: searchSecondary.withAlphaComponent(0.72)]
    )
    submitButton.tintColor = isPrivateMode
      ? AppColors.privateBrowsingAccent
      : AppColors.accent
    searchMaterial.contentView.backgroundColor = isPrivateMode
      ? UIColor(
        red: 0.17,
        green: 0.17,
        blue: 0.20,
        alpha: 0.62
      )
      : .clear
    searchMaterial.layer.borderColor = AppColors.separator
      .resolvedColor(
        with: isPrivateMode
          ? UITraitCollection(userInterfaceStyle: .dark)
          : traitCollection
      )
      .cgColor
  }

  @objc private func textDidChange() {
    updateSubmitButton()
  }

  private func updateSubmitButton() {
    let hasText = textField.text?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .isEmpty == false
    submitButton.alpha = hasText ? 1 : 0
    submitButton.isUserInteractionEnabled = hasText
    submitButton.accessibilityElementsHidden = !hasText
  }

  @objc private func submit() {
    let input = textField.text?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !input.isEmpty else {
      UINotificationFeedbackGenerator().notificationOccurred(.warning)
      return
    }
    delegate?.newTabView(self, didSubmit: input)
    textField.resignFirstResponder()
  }
}

extension NewTabView: UITextFieldDelegate {
  func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
    delegate?.newTabViewDidBeginEditing(self)
    return false
  }

  func textFieldDidBeginEditing(_ textField: UITextField) {
    updateSubmitButton()
  }

  func textFieldDidEndEditing(_ textField: UITextField) {
    updateSubmitButton()
  }

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    submit()
    return true
  }
}

private final class NewTabLogoView: UIView {
  private let symbolView = UIImageView(
    image: UIImage(
      systemName: "dot.radiowaves.left.and.right",
      withConfiguration: UIImage.SymbolConfiguration(
        pointSize: 32,
        weight: .medium
      )
    )
  )

  override init(frame: CGRect) {
    super.init(frame: frame)
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }

  private func configure() {
    layer.cornerRadius = 22
    layer.cornerCurve = .continuous
    clipsToBounds = true
    isAccessibilityElement = true
    accessibilityTraits = .image

    symbolView.translatesAutoresizingMaskIntoConstraints = false
    symbolView.contentMode = .scaleAspectFit
    addSubview(symbolView)
    NSLayoutConstraint.activate([
      symbolView.centerXAnchor.constraint(equalTo: centerXAnchor),
      symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
      symbolView.widthAnchor.constraint(equalToConstant: 44),
      symbolView.heightAnchor.constraint(equalToConstant: 44),
    ])
    backgroundColor = AppColors.accent
    symbolView.tintColor = .white
  }
}
