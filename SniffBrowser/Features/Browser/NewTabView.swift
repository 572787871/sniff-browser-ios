import UIKit

enum NewTabQuickAction: Int, CaseIterable {
  case downloads
  case files
  case favorites
  case history

  var title: String {
    switch self {
    case .downloads: return "下载"
    case .files: return "文件"
    case .favorites: return "收藏"
    case .history: return "历史"
    }
  }

  var symbol: String {
    switch self {
    case .downloads: return "arrow.down"
    case .files: return "folder"
    case .favorites: return "bookmark"
    case .history: return "clock.arrow.circlepath"
    }
  }
}

@MainActor
protocol NewTabViewDelegate: AnyObject {
  func newTabViewDidBeginEditing(_ view: NewTabView)
  func newTabView(_ view: NewTabView, didSubmit text: String)
  func newTabView(_ view: NewTabView, didSelect action: NewTabQuickAction)
  func newTabView(_ view: NewTabView, didSelect favorite: FavoriteItem)
}

final class NewTabView: UIView {
  weak var delegate: NewTabViewDelegate?

  private let backgroundImageView = UIImageView()
  private let backgroundScrimView = NewTabPhotoScrimView()
  private let logoContainer = UIView()
  private let logoView = NewTabLogoView()
  private let headerContainer = UIView()
  private let titleLabel = UILabel()
  private let welcomeLabel = UILabel()
  private let dateLabel = UILabel()
  private let quickActionsTitleLabel = UILabel()
  private let quickActionsStack = UIStackView()
  private let favoritesTitleLabel = UILabel()
  private let favoritesStack = UIStackView()
  private let scrollView = UIScrollView()
  private let contentContainer = UIView()
  private let contentStack = UIStackView()
  private var contentTopConstraint: NSLayoutConstraint?
  private let searchMaterial = UIView()
  private let searchImageView = UIImageView(
    image: UIImage(systemName: "magnifyingglass")
  )
  private let textField = UITextField()
  private let submitButton = UIButton(type: .system)
  private var isPrivateMode = false
  private var hasCustomBackground = false
  private var displayedFavorites: [FavoriteItem] = []
  private var backgroundChangeObserver: NSObjectProtocol?

  override init(frame: CGRect) {
    super.init(frame: frame)
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }

  deinit {
    if let backgroundChangeObserver {
      NotificationCenter.default.removeObserver(backgroundChangeObserver)
    }
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    updateResolvedColors()
    updateContentTopInset()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    updateContentTopInset()
  }

  override func safeAreaInsetsDidChange() {
    super.safeAreaInsetsDidChange()
    updateContentTopInset()
  }

  /// 自定义背景图是否正在展示（供浏览器调整状态栏样式）。
  var showsPhotoBackground: Bool {
    hasCustomBackground
  }

  func focusSearch() {
    delegate?.newTabViewDidBeginEditing(self)
  }

  func updateFavorites(_ favorites: [FavoriteItem]) {
    displayedFavorites = Array(favorites.prefix(4))
    favoritesStack.arrangedSubviews.forEach {
      favoritesStack.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }

    displayedFavorites.forEach { favorite in
      let button = NewTabFavoriteButton(favorite: favorite)
      button.addTarget(
        self,
        action: #selector(favoritePressed(_:)),
        for: .touchUpInside
      )
      favoritesStack.addArrangedSubview(button)
    }
    for _ in displayedFavorites.count..<4 {
      let spacer = UIView()
      spacer.isAccessibilityElement = false
      favoritesStack.addArrangedSubview(spacer)
    }

    let isEmpty = displayedFavorites.isEmpty
    favoritesTitleLabel.isHidden = isEmpty
    favoritesStack.isHidden = isEmpty
    contentStack.setCustomSpacing(
      isEmpty ? AppSpacing.md : AppSpacing.lg,
      after: quickActionsStack
    )
    updateResolvedColors()
  }

  func setPrivateMode(_ isPrivate: Bool) {
    isPrivateMode = isPrivate
    overrideUserInterfaceStyle = .unspecified
    backgroundColor = AppColors.background
    titleLabel.text = isPrivate ? "无痕浏览" : "嗅探浏览器"
    welcomeLabel.text = isPrivate
      ? "不会保存浏览历史、搜索记录或自动填充信息；下载和主动收藏仍会保留。"
      : "专注浏览，随时发现"
    refreshContentPreferences()
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
    let backgroundImage = NewTabBackgroundStore.shared.image()
    backgroundImageView.image = backgroundImage
    hasCustomBackground = backgroundImage != nil
    backgroundImageView.isHidden = !hasCustomBackground
    backgroundScrimView.isHidden = !hasCustomBackground
    updateResolvedColors()
  }

  private func configure() {
    translatesAutoresizingMaskIntoConstraints = false
    backgroundColor = AppColors.background

    configureHeader()
    configureSearch()
    configureQuickActions()
    configureFavorites()
    configureDate()
    configureHierarchy()
    observeBackgroundChanges()

    refreshContentPreferences()
    updateSubmitButton()
    updateResolvedColors()
    registerForTraitChanges([
      UITraitUserInterfaceStyle.self,
      UITraitAccessibilityContrast.self,
      AppThemeColorTrait.self,
    ]) { (view: NewTabView, _) in
      view.updateResolvedColors()
    }
  }

  private func observeBackgroundChanges() {
    backgroundChangeObserver = NotificationCenter.default.addObserver(
      forName: .newTabBackgroundDidChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.refreshContentPreferences()
      }
    }
  }

  private func configureHeader() {
    headerContainer.translatesAutoresizingMaskIntoConstraints = false

    logoContainer.translatesAutoresizingMaskIntoConstraints = false
    logoView.translatesAutoresizingMaskIntoConstraints = false
    logoView.accessibilityLabel = "嗅探浏览器图标"
    logoView.accessibilityIdentifier = "newTab.logo"
    logoContainer.addSubview(logoView)

    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.text = "嗅探浏览器"
    titleLabel.font = AppTypography.title
    titleLabel.textColor = AppColors.primaryText
    titleLabel.textAlignment = .left
    titleLabel.numberOfLines = 1
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.accessibilityIdentifier = "newTab.title"
    titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)

    welcomeLabel.translatesAutoresizingMaskIntoConstraints = false
    welcomeLabel.text = "专注浏览，随时发现"
    welcomeLabel.font = AppTypography.footnote
    welcomeLabel.textColor = AppColors.secondaryText
    welcomeLabel.textAlignment = .left
    welcomeLabel.numberOfLines = 3
    welcomeLabel.adjustsFontForContentSizeCategory = true
    welcomeLabel.accessibilityIdentifier = "newTab.description"
    welcomeLabel.setContentCompressionResistancePriority(.required, for: .vertical)

    headerContainer.addSubview(logoContainer)
    headerContainer.addSubview(titleLabel)
    headerContainer.addSubview(welcomeLabel)

    let preferredHeaderHeight = headerContainer.heightAnchor.constraint(
      equalToConstant: 88
    )
    preferredHeaderHeight.priority = UILayoutPriority(999)
    NSLayoutConstraint.activate([
      headerContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 88),
      preferredHeaderHeight,
      logoContainer.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
      logoContainer.topAnchor.constraint(equalTo: headerContainer.topAnchor),
      logoContainer.widthAnchor.constraint(equalToConstant: 56),
      logoContainer.heightAnchor.constraint(equalToConstant: 88),
      logoView.topAnchor.constraint(equalTo: logoContainer.topAnchor, constant: 6),
      logoView.leadingAnchor.constraint(equalTo: logoContainer.leadingAnchor),
      logoView.widthAnchor.constraint(equalToConstant: 52),
      logoView.heightAnchor.constraint(equalTo: logoView.widthAnchor),

      titleLabel.topAnchor.constraint(equalTo: headerContainer.topAnchor, constant: 7),
      titleLabel.leadingAnchor.constraint(
        equalTo: logoContainer.trailingAnchor,
        constant: AppSpacing.sm
      ),
      titleLabel.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),

      welcomeLabel.topAnchor.constraint(
        equalTo: titleLabel.bottomAnchor,
        constant: AppSpacing.xxs
      ),
      welcomeLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      welcomeLabel.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
      welcomeLabel.bottomAnchor.constraint(
        lessThanOrEqualTo: headerContainer.bottomAnchor,
        constant: -AppSpacing.xxs
      ),
    ])
  }

  private func configureSearch() {
    searchMaterial.translatesAutoresizingMaskIntoConstraints = false
    searchMaterial.layer.cornerRadius = AppRadius.input
    searchMaterial.layer.cornerCurve = .continuous
    searchMaterial.layer.borderWidth = 1
    searchMaterial.accessibilityIdentifier = "newTab.searchSurface"

    searchImageView.translatesAutoresizingMaskIntoConstraints = false
    searchImageView.tintColor = AppColors.secondaryText
    searchImageView.contentMode = .scaleAspectFit
    searchImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
      pointSize: 19,
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
    textField.addTarget(self, action: #selector(textDidChange), for: .editingChanged)

    var buttonConfiguration = UIButton.Configuration.filled()
    buttonConfiguration.image = UIImage(
      systemName: "arrow.up.right",
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
    )
    buttonConfiguration.baseBackgroundColor = AppColors.accent
    buttonConfiguration.baseForegroundColor = AppColors.accentContent
    buttonConfiguration.cornerStyle = .capsule
    buttonConfiguration.contentInsets = .zero
    submitButton.translatesAutoresizingMaskIntoConstraints = false
    submitButton.configuration = buttonConfiguration
    submitButton.accessibilityLabel = "打开"
    submitButton.accessibilityIdentifier = "newTab.submit"
    submitButton.addTarget(self, action: #selector(submit), for: .touchUpInside)

    searchMaterial.addSubview(searchImageView)
    searchMaterial.addSubview(textField)
    searchMaterial.addSubview(submitButton)

    NSLayoutConstraint.activate([
      searchMaterial.heightAnchor.constraint(greaterThanOrEqualToConstant: 58),
      searchImageView.leadingAnchor.constraint(
        equalTo: searchMaterial.leadingAnchor,
        constant: AppSpacing.md
      ),
      searchImageView.centerYAnchor.constraint(equalTo: searchMaterial.centerYAnchor),
      searchImageView.widthAnchor.constraint(equalToConstant: 22),
      searchImageView.heightAnchor.constraint(equalToConstant: 22),
      textField.leadingAnchor.constraint(
        equalTo: searchImageView.trailingAnchor,
        constant: AppSpacing.sm
      ),
      textField.trailingAnchor.constraint(
        equalTo: submitButton.leadingAnchor,
        constant: -AppSpacing.xs
      ),
      textField.topAnchor.constraint(equalTo: searchMaterial.topAnchor),
      textField.bottomAnchor.constraint(equalTo: searchMaterial.bottomAnchor),
      submitButton.trailingAnchor.constraint(
        equalTo: searchMaterial.trailingAnchor,
        constant: -AppSpacing.sm
      ),
      submitButton.centerYAnchor.constraint(equalTo: searchMaterial.centerYAnchor),
      submitButton.widthAnchor.constraint(equalToConstant: 36),
      submitButton.heightAnchor.constraint(equalTo: submitButton.widthAnchor),
    ])
  }

  private func configureQuickActions() {
    quickActionsTitleLabel.text = "快捷入口"
    quickActionsTitleLabel.font = AppTypography.headline
    quickActionsTitleLabel.textColor = AppColors.primaryText
    quickActionsTitleLabel.adjustsFontForContentSizeCategory = true

    quickActionsStack.axis = .horizontal
    quickActionsStack.alignment = .fill
    quickActionsStack.distribution = .fillEqually
    quickActionsStack.spacing = AppSpacing.xs

    for action in NewTabQuickAction.allCases {
      let button = NewTabQuickActionButton(action: action)
      button.tag = action.rawValue
      button.addTarget(self, action: #selector(quickActionPressed(_:)), for: .touchUpInside)
      quickActionsStack.addArrangedSubview(button)
    }
    quickActionsStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true
  }

  private func configureFavorites() {
    favoritesTitleLabel.text = "收藏网页"
    favoritesTitleLabel.font = AppTypography.headline
    favoritesTitleLabel.textColor = AppColors.primaryText
    favoritesTitleLabel.adjustsFontForContentSizeCategory = true
    favoritesTitleLabel.accessibilityIdentifier = "newTab.favoritesTitle"
    favoritesTitleLabel.isHidden = true

    favoritesStack.axis = .horizontal
    favoritesStack.alignment = .fill
    favoritesStack.distribution = .fillEqually
    favoritesStack.spacing = AppSpacing.xs
    favoritesStack.isHidden = true
    favoritesStack.accessibilityIdentifier = "newTab.favorites"
    favoritesStack.heightAnchor.constraint(
      greaterThanOrEqualToConstant: 88
    ).isActive = true
  }

  private func configureDate() {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.setLocalizedDateFormatFromTemplate("MMMMdEEEE")
    dateLabel.text = formatter.string(from: Date())
    dateLabel.font = AppTypography.caption
    dateLabel.textColor = AppColors.tertiaryText
    dateLabel.textAlignment = .left
    dateLabel.numberOfLines = 1
    dateLabel.adjustsFontForContentSizeCategory = true
    dateLabel.accessibilityIdentifier = "newTab.date"
  }

  private func configureHierarchy() {
    backgroundImageView.translatesAutoresizingMaskIntoConstraints = false
    backgroundImageView.contentMode = .scaleAspectFill
    backgroundImageView.clipsToBounds = true
    backgroundImageView.isUserInteractionEnabled = false
    backgroundImageView.isAccessibilityElement = false
    backgroundImageView.accessibilityIdentifier = "newTab.backgroundImage"
    addSubview(backgroundImageView)

    backgroundScrimView.translatesAutoresizingMaskIntoConstraints = false
    backgroundScrimView.isUserInteractionEnabled = false
    backgroundScrimView.isAccessibilityElement = false
    addSubview(backgroundScrimView)

    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.alwaysBounceVertical = false
    scrollView.keyboardDismissMode = .interactive
    scrollView.showsVerticalScrollIndicator = false
    // 新标签页现在延伸到状态栏下方，内容顶部需要自己按安全区留白，
    // 避免系统再自动叠加一次 safe area inset。
    scrollView.contentInsetAdjustmentBehavior = .never
    addSubview(scrollView)

    contentContainer.translatesAutoresizingMaskIntoConstraints = false
    scrollView.addSubview(contentContainer)

    contentStack.translatesAutoresizingMaskIntoConstraints = false
    contentStack.axis = .vertical
    contentStack.alignment = .fill
    contentStack.spacing = 0
    contentStack.addArrangedSubview(headerContainer)
    contentStack.setCustomSpacing(AppSpacing.sm, after: headerContainer)
    contentStack.addArrangedSubview(searchMaterial)
    contentStack.setCustomSpacing(AppSpacing.xl, after: searchMaterial)
    contentStack.addArrangedSubview(quickActionsTitleLabel)
    contentStack.setCustomSpacing(AppSpacing.sm, after: quickActionsTitleLabel)
    contentStack.addArrangedSubview(quickActionsStack)
    contentStack.setCustomSpacing(AppSpacing.md, after: quickActionsStack)
    contentStack.addArrangedSubview(favoritesTitleLabel)
    contentStack.setCustomSpacing(AppSpacing.sm, after: favoritesTitleLabel)
    contentStack.addArrangedSubview(favoritesStack)
    contentStack.setCustomSpacing(AppSpacing.md, after: favoritesStack)
    contentStack.addArrangedSubview(dateLabel)
    contentContainer.addSubview(contentStack)

    let viewportHeightConstraint = contentContainer.heightAnchor.constraint(
      equalTo: scrollView.frameLayoutGuide.heightAnchor
    )
    viewportHeightConstraint.priority = .defaultLow
    contentTopConstraint = contentStack.topAnchor.constraint(
      equalTo: contentContainer.topAnchor,
      constant: AppSpacing.xxl
    )
    NSLayoutConstraint.activate([
      backgroundImageView.topAnchor.constraint(equalTo: topAnchor),
      backgroundImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
      backgroundImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
      backgroundImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
      backgroundScrimView.topAnchor.constraint(equalTo: topAnchor),
      backgroundScrimView.leadingAnchor.constraint(equalTo: leadingAnchor),
      backgroundScrimView.trailingAnchor.constraint(equalTo: trailingAnchor),
      backgroundScrimView.bottomAnchor.constraint(equalTo: bottomAnchor),

      scrollView.topAnchor.constraint(equalTo: topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

      contentContainer.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
      contentContainer.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
      contentContainer.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
      contentContainer.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
      contentContainer.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
      contentContainer.heightAnchor.constraint(
        greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor
      ),
      viewportHeightConstraint,

      contentTopConstraint!,
      contentStack.leadingAnchor.constraint(
        equalTo: contentContainer.leadingAnchor,
        constant: AppSpacing.xl
      ),
      contentStack.trailingAnchor.constraint(
        equalTo: contentContainer.trailingAnchor,
        constant: -AppSpacing.xl
      ),
      contentStack.bottomAnchor.constraint(
        lessThanOrEqualTo: contentContainer.bottomAnchor,
        constant: -AppSpacing.xl
      ),
    ])
  }

  private func updateResolvedColors() {
    let searchPrimary = isPrivateMode
      ? AppColors.primaryText.resolvedColor(
        with: UITraitCollection(userInterfaceStyle: .dark)
      )
      : AppColors.primaryText
    let searchSecondary = isPrivateMode
      ? AppColors.secondaryText.resolvedColor(
        with: UITraitCollection(userInterfaceStyle: .dark)
      )
      : AppColors.secondaryText

    if hasCustomBackground {
      titleLabel.textColor = isPrivateMode
        ? AppColors.privateBrowsingDescription
        : .white
      welcomeLabel.textColor = isPrivateMode
        ? AppColors.privateBrowsingDescription.withAlphaComponent(0.92)
        : UIColor.white.withAlphaComponent(0.88)
      quickActionsTitleLabel.textColor = .white
      favoritesTitleLabel.textColor = .white
      dateLabel.textColor = UIColor.white.withAlphaComponent(0.76)
    } else {
      titleLabel.textColor = isPrivateMode
        ? AppColors.privateBrowsingDescription
        : AppColors.primaryText
      welcomeLabel.textColor = isPrivateMode
        ? AppColors.privateBrowsingDescription.withAlphaComponent(0.86)
        : AppColors.secondaryText
      quickActionsTitleLabel.textColor = AppColors.primaryText
      favoritesTitleLabel.textColor = AppColors.primaryText
      dateLabel.textColor = AppColors.tertiaryText
    }
    [
      titleLabel,
      welcomeLabel,
      quickActionsTitleLabel,
      favoritesTitleLabel,
      dateLabel,
    ].forEach {
      $0.layer.shadowColor = UIColor.black.cgColor
      $0.layer.shadowOpacity = hasCustomBackground ? 0.38 : 0
      $0.layer.shadowRadius = hasCustomBackground ? 3 : 0
      $0.layer.shadowOffset = CGSize(width: 0, height: 1)
    }
    searchImageView.tintColor = isPrivateMode
      ? AppColors.privateBrowsingAccent
      : searchSecondary
    textField.textColor = searchPrimary
    textField.tintColor = isPrivateMode
      ? AppColors.privateBrowsingAccent
      : AppColors.accent
    textField.attributedPlaceholder = NSAttributedString(
      string: "搜索或输入网址",
      attributes: [.foregroundColor: searchSecondary.withAlphaComponent(0.76)]
    )
    submitButton.configuration?.baseBackgroundColor = isPrivateMode
      ? AppColors.privateBrowsingAccent
      : AppColors.accent
    submitButton.configuration?.baseForegroundColor = isPrivateMode
      ? AppColors.privateBrowsingAccentContent
      : AppColors.accentContent
    searchMaterial.backgroundColor = isPrivateMode
      ? AppColors.privateBrowsingChrome
      : AppColors.surface.withAlphaComponent(hasCustomBackground ? 0.94 : 1)
    searchMaterial.layer.borderColor = (
      isPrivateMode
        ? AppColors.privateBrowsingAccent.withAlphaComponent(0.30)
        : AppColors.browserChromeBorder.resolvedColor(with: traitCollection)
    ).cgColor
    quickActionsStack.arrangedSubviews
      .compactMap { $0 as? NewTabQuickActionButton }
      .forEach { $0.updateAppearance(overPhoto: hasCustomBackground) }
    favoritesStack.arrangedSubviews
      .compactMap { $0 as? NewTabFavoriteButton }
      .forEach { $0.updateAppearance(overPhoto: hasCustomBackground) }
  }

  private func updateContentTopInset() {
    guard let contentTopConstraint else { return }
    let inset = max(0, safeAreaInsets.top) + AppSpacing.xxl
    if contentTopConstraint.constant != inset {
      contentTopConstraint.constant = inset
    }
  }

  @objc private func textDidChange() {
    updateSubmitButton()
  }

  private func updateSubmitButton() {
    let hasText = textField.text?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .isEmpty == false
    submitButton.alpha = hasText ? 1 : 0.38
    submitButton.isUserInteractionEnabled = true
    submitButton.accessibilityElementsHidden = false
    submitButton.accessibilityLabel = hasText ? "打开" : "开始搜索"
  }

  @objc private func quickActionPressed(_ sender: UIButton) {
    guard let action = NewTabQuickAction(rawValue: sender.tag) else { return }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    delegate?.newTabView(self, didSelect: action)
  }

  @objc private func favoritePressed(_ sender: NewTabFavoriteButton) {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    delegate?.newTabView(self, didSelect: sender.favorite)
  }

  @objc private func submit() {
    let input = textField.text?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !input.isEmpty else {
      delegate?.newTabViewDidBeginEditing(self)
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

private final class NewTabPhotoScrimView: UIView {
  override class var layerClass: AnyClass {
    CAGradientLayer.self
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    configureGradient()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configureGradient()
  }

  private func configureGradient() {
    guard let gradient = layer as? CAGradientLayer else { return }
    gradient.colors = [
      UIColor.black.withAlphaComponent(0.38).cgColor,
      UIColor.black.withAlphaComponent(0.14).cgColor,
      UIColor.black.withAlphaComponent(0.30).cgColor,
    ]
    gradient.locations = [0, 0.52, 1]
    gradient.startPoint = CGPoint(x: 0.5, y: 0)
    gradient.endPoint = CGPoint(x: 0.5, y: 1)
  }
}

private final class NewTabLogoView: UIView {
  private let symbolView = UIImageView(image: UIImage(named: "AppLogo"))

  override init(frame: CGRect) {
    super.init(frame: frame)
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }

  private func configure() {
    layer.cornerRadius = AppRadius.control
    layer.cornerCurve = .continuous
    clipsToBounds = true
    isAccessibilityElement = true
    accessibilityTraits = .image

    symbolView.translatesAutoresizingMaskIntoConstraints = false
    symbolView.contentMode = .scaleAspectFill
    addSubview(symbolView)

    NSLayoutConstraint.activate([
      symbolView.topAnchor.constraint(equalTo: topAnchor),
      symbolView.leadingAnchor.constraint(equalTo: leadingAnchor),
      symbolView.trailingAnchor.constraint(equalTo: trailingAnchor),
      symbolView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }
}

private final class NewTabFavoriteButton: UIButton {
  let favorite: FavoriteItem

  private var faviconURL: URL?
  private var faviconRequestID: UUID?

  init(favorite: FavoriteItem) {
    self.favorite = favorite
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false

    var configuration = UIButton.Configuration.filled()
    configuration.image = UIImage(
      systemName: "star.fill",
      withConfiguration: UIImage.SymbolConfiguration(
        pointSize: 20,
        weight: .medium
      )
    )
    configuration.title = favorite.title
    configuration.imagePlacement = .top
    configuration.imagePadding = AppSpacing.xs
    configuration.baseForegroundColor = AppColors.primaryText
    configuration.baseBackgroundColor = AppColors.secondarySurface
    configuration.cornerStyle = .medium
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: AppSpacing.sm,
      leading: AppSpacing.xs,
      bottom: AppSpacing.xs,
      trailing: AppSpacing.xs
    )
    configuration.titleLineBreakMode = .byTruncatingTail
    configuration.titleAlignment = .center
    configuration.titleTextAttributesTransformer =
      UIConfigurationTextAttributesTransformer { attributes in
        var attributes = attributes
        attributes.font = AppTypography.caption
        attributes.foregroundColor = AppColors.primaryText
        return attributes
    }
    self.configuration = configuration
    configureTitleLabel()
    accessibilityLabel = "\(favorite.title)，\(favorite.host)"
    accessibilityHint = "打开收藏网页"
    loadFavicon()
  }

  required init?(coder: NSCoder) {
    return nil
  }

  deinit {
    if let faviconURL, let faviconRequestID {
      FaviconLoader.shared.cancel(url: faviconURL, requestID: faviconRequestID)
    }
  }

  func updateAppearance(overPhoto: Bool) {
    guard var configuration else { return }
    let foreground = overPhoto ? UIColor.white : AppColors.primaryText
    configuration.baseForegroundColor = foreground
    configuration.baseBackgroundColor = overPhoto
      ? UIColor.black.withAlphaComponent(0.34)
      : AppColors.secondarySurface
    configuration.titleTextAttributesTransformer =
      UIConfigurationTextAttributesTransformer { attributes in
        var attributes = attributes
        attributes.font = AppTypography.caption
        attributes.foregroundColor = foreground
        return attributes
    }
    self.configuration = configuration
    configureTitleLabel()
  }

  private func loadFavicon() {
    let resolvedURL = favorite.faviconURL
      ?? FaviconLoader.faviconURL(for: favorite.url)
    guard let resolvedURL else { return }
    faviconURL = resolvedURL
    var requestID: UUID?
    requestID = FaviconLoader.shared.load(url: resolvedURL) {
      [weak self] image in
      guard let self,
            self.faviconRequestID == requestID,
            let image,
            var configuration = self.configuration
      else {
        return
      }
      configuration.image = Self.preparedFavicon(image)
      self.configuration = configuration
      self.configureTitleLabel()
    }
    faviconRequestID = requestID
  }

  private func configureTitleLabel() {
    titleLabel?.numberOfLines = 2
    titleLabel?.textAlignment = .center
    titleLabel?.lineBreakMode = .byTruncatingTail
  }

  private static func preparedFavicon(_ image: UIImage) -> UIImage {
    let size = CGSize(width: 24, height: 24)
    let format = UIGraphicsImageRendererFormat.preferred()
    format.opaque = false
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      let scale = min(size.width / image.size.width, size.height / image.size.height)
      let fittedSize = CGSize(
        width: image.size.width * scale,
        height: image.size.height * scale
      )
      image.draw(in: CGRect(
        x: (size.width - fittedSize.width) / 2,
        y: (size.height - fittedSize.height) / 2,
        width: fittedSize.width,
        height: fittedSize.height
      ))
    }.withRenderingMode(.alwaysOriginal)
  }

  override var isHighlighted: Bool {
    didSet {
      let changes = {
        self.alpha = self.isHighlighted ? 0.72 : 1
        self.transform = self.isHighlighted
          ? CGAffineTransform(scaleX: 0.97, y: 0.97)
          : .identity
      }
      guard !UIAccessibility.isReduceMotionEnabled else {
        changes()
        return
      }
      UIView.animate(
        withDuration: 0.14,
        delay: 0,
        options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut],
        animations: changes
      )
    }
  }
}

private final class NewTabQuickActionButton: UIButton {
  init(action: NewTabQuickAction) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false

    var configuration = UIButton.Configuration.filled()
    configuration.image = UIImage(
      systemName: action.symbol,
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .medium)
    )
    configuration.title = action.title
    configuration.imagePlacement = .top
    configuration.imagePadding = AppSpacing.xs
    configuration.baseForegroundColor = AppColors.primaryText
    configuration.baseBackgroundColor = AppColors.secondarySurface
    configuration.cornerStyle = .medium
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: AppSpacing.sm,
      leading: AppSpacing.xs,
      bottom: AppSpacing.xs,
      trailing: AppSpacing.xs
    )
    configuration.titleTextAttributesTransformer =
      UIConfigurationTextAttributesTransformer { attributes in
        var attributes = attributes
        attributes.font = AppTypography.caption
        attributes.foregroundColor = AppColors.primaryText
        return attributes
      }
    self.configuration = configuration
    accessibilityLabel = action.title
    accessibilityHint = "打开\(action.title)"
  }

  func updateAppearance(overPhoto: Bool) {
    guard var configuration else { return }
    let foreground = overPhoto ? UIColor.white : AppColors.primaryText
    configuration.baseForegroundColor = foreground
    configuration.baseBackgroundColor = overPhoto
      ? UIColor.black.withAlphaComponent(0.34)
      : AppColors.secondarySurface
    configuration.titleTextAttributesTransformer =
      UIConfigurationTextAttributesTransformer { attributes in
        var attributes = attributes
        attributes.font = AppTypography.caption
        attributes.foregroundColor = foreground
        return attributes
      }
    self.configuration = configuration
  }

  required init?(coder: NSCoder) {
    return nil
  }

  override var isHighlighted: Bool {
    didSet {
      let changes = {
        self.alpha = self.isHighlighted ? 0.72 : 1
        self.transform = self.isHighlighted
          ? CGAffineTransform(scaleX: 0.97, y: 0.97)
          : .identity
      }
      guard !UIAccessibility.isReduceMotionEnabled else {
        changes()
        return
      }
      UIView.animate(
        withDuration: 0.14,
        delay: 0,
        options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut],
        animations: changes
      )
    }
  }
}
