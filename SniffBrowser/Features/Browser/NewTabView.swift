import UIKit

@MainActor
protocol NewTabViewDelegate: AnyObject {
  func newTabViewDidBeginEditing(_ view: NewTabView)
  func newTabView(_ view: NewTabView, didSubmit text: String)
  func newTabViewDidSelectFavorite(_ view: NewTabView, item: FavoriteItem)
  func newTabViewDidSelectViewAll(_ view: NewTabView)
  func newTabViewDidSelectAddFavorite(_ view: NewTabView)
  func newTabView(_ view: NewTabView, didLongPressFavorite item: FavoriteItem, at point: CGPoint)
}

final class NewTabView: UIView {
  weak var delegate: NewTabViewDelegate?

  private let titleLabel = UILabel()
  private let privacyBadge = UILabel()
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

  // Favorites section
  private let favoritesSection = UIStackView()
  private let favoritesHeader = UIStackView()
  private let favoritesTitle = UILabel()
  private let favoritesViewAll = UIButton(type: .system)
  private let favoritesGrid = UIStackView()
  private let favoritesEmptyState = UIStackView()
  private let favoritesEmptyLabel = UILabel()
  private let favoritesAddButton = UIButton(type: .system)
  private var favoriteItems: [FavoriteItem] = []
  private var favoriteChangeObserver: NSObjectProtocol?
  private let maxFavoritesDisplay = 8

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

  func setPrivateMode(_ isPrivate: Bool) {
    isPrivateMode = isPrivate
    overrideUserInterfaceStyle = isPrivate ? .dark : .unspecified
    backgroundColor = isPrivate
      ? AppColors.privateBrowsingBackground
      : AppColors.background
    privacyBadge.isHidden = !isPrivate
    titleLabel.text = isPrivate ? "无痕浏览" : "嗅探浏览器"
    welcomeLabel.text = isPrivate
      ? "无痕标签不会保存到浏览历史，下载和主动收藏的内容仍会保留。"
      : "从一次安静、专注的浏览开始"
    accessibilityLabel = isPrivate
      ? "无痕浏览。无痕模式不会让你在网络上匿名。"
      : nil
    updateResolvedColors()
    updateEmptyStateForPrivateMode()
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
    titleLabel.setContentCompressionResistancePriority(
      .required,
      for: .horizontal
    )

    welcomeLabel.translatesAutoresizingMaskIntoConstraints = false
    welcomeLabel.text = "从一次安静、专注的浏览开始"
    welcomeLabel.font = AppTypography.body
    welcomeLabel.textColor = AppColors.secondaryText
    welcomeLabel.textAlignment = .center
    welcomeLabel.numberOfLines = 0
    welcomeLabel.adjustsFontForContentSizeCategory = true
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
    dateLabel.setContentCompressionResistancePriority(
      .required,
      for: .horizontal
    )

    searchMaterial.translatesAutoresizingMaskIntoConstraints = false
    searchMaterial.layer.cornerRadius = AppRadius.input
    searchMaterial.layer.cornerCurve = .continuous
    searchMaterial.clipsToBounds = true
    searchMaterial.layer.borderWidth = 0.5

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
    contentStack.addArrangedSubview(titleLabel)
    privacyBadge.isHidden = true
    contentStack.addArrangedSubview(privacyBadge)
    contentStack.setCustomSpacing(AppSpacing.xxs, after: privacyBadge)
    contentStack.addArrangedSubview(welcomeLabel)
    contentStack.setCustomSpacing(AppSpacing.sm, after: welcomeLabel)
    contentStack.addArrangedSubview(dateLabel)
    contentStack.setCustomSpacing(AppSpacing.xl, after: dateLabel)
    contentStack.addArrangedSubview(searchMaterial)
    contentContainer.addSubview(contentStack)
    configureFavoritesSection()
    contentStack.addArrangedSubview(favoritesSection)

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
        equalTo: contentContainer.leadingAnchor,
        constant: AppSpacing.xl
      ),
      contentStack.trailingAnchor.constraint(
        equalTo: contentContainer.trailingAnchor,
        constant: -AppSpacing.xl
      ),

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

  private func configureFavoritesSection() {
    favoritesSection.axis = .vertical
    favoritesSection.alignment = .fill
    favoritesSection.spacing = AppSpacing.md
    favoritesSection.translatesAutoresizingMaskIntoConstraints = false
    favoritesSection.isHidden = true
    contentStack.setCustomSpacing(32, after: searchMaterial)

    // Header
    favoritesHeader.axis = .horizontal
    favoritesHeader.alignment = .center
    favoritesHeader.distribution = .equalSpacing
    favoritesHeader.translatesAutoresizingMaskIntoConstraints = false

    favoritesTitle.text = "收藏夹"
    favoritesTitle.font = AppTypography.subheadline
    favoritesTitle.textColor = AppColors.primaryText
    favoritesTitle.setContentHuggingPriority(.defaultLow, for: .horizontal)

    var viewAllConfig = UIButton.Configuration.plain()
    viewAllConfig.title = "查看全部"
    viewAllConfig.baseForegroundColor = AppColors.accent
    viewAllConfig.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
    favoritesViewAll.configuration = viewAllConfig
    favoritesViewAll.addTarget(self, action: #selector(viewAllPressed), for: .touchUpInside)
    favoritesViewAll.setContentHuggingPriority(.required, for: .horizontal)
    favoritesViewAll.accessibilityLabel = "查看全部收藏"

    favoritesHeader.addArrangedSubview(favoritesTitle)
    favoritesHeader.addArrangedSubview(favoritesViewAll)

    // Grid
    favoritesGrid.axis = .vertical
    favoritesGrid.alignment = .fill
    favoritesGrid.spacing = AppSpacing.sm
    favoritesGrid.translatesAutoresizingMaskIntoConstraints = false

    // Empty state
    favoritesEmptyState.axis = .vertical
    favoritesEmptyState.alignment = .center
    favoritesEmptyState.spacing = AppSpacing.sm
    favoritesEmptyState.translatesAutoresizingMaskIntoConstraints = false

    favoritesEmptyLabel.text = "还没有收藏的网站"
    favoritesEmptyLabel.font = AppTypography.body
    favoritesEmptyLabel.textColor = AppColors.secondaryText
    favoritesEmptyLabel.textAlignment = .center

    var addBtnConfig = UIButton.Configuration.tinted()
    addBtnConfig.title = "添加收藏"
    addBtnConfig.baseForegroundColor = AppColors.accent
    addBtnConfig.baseBackgroundColor = AppColors.accentFill
    addBtnConfig.cornerStyle = .capsule
    favoritesAddButton.configuration = addBtnConfig
    favoritesAddButton.addTarget(self, action: #selector(addFavoritePressed), for: .touchUpInside)

    favoritesEmptyState.addArrangedSubview(favoritesEmptyLabel)
    favoritesEmptyState.addArrangedSubview(favoritesAddButton)

    favoritesSection.addArrangedSubview(favoritesHeader)
    favoritesSection.addArrangedSubview(favoritesGrid)
    favoritesSection.addArrangedSubview(favoritesEmptyState)

    observeFavorites()
    reloadFavorites()
  }

  private func observeFavorites() {
    favoriteChangeObserver = NotificationCenter.default.addObserver(
      forName: .favoriteItemsDidChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.reloadFavorites()
    }
  }

  private func reloadFavorites() {
    guard let items = try? FavoriteService.shared.allFavorites() else { return }
    favoriteItems = items
    updateFavoritesSection()
  }

  private func updateFavoritesSection() {
    let isEmpty = favoriteItems.isEmpty
    favoritesGrid.isHidden = isEmpty
    favoritesEmptyState.isHidden = !isEmpty
    favoritesSection.isHidden = false

    if isEmpty {
      updateEmptyStateForPrivateMode()
      return
    }

    favoritesGrid.arrangedSubviews.forEach {
      favoritesGrid.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }

    let displayItems = Array(favoriteItems.prefix(maxFavoritesDisplay))
    let isWide = bounds.width > 400
    let columnCount = isWide ? 4 : 2
    var currentRow: UIStackView?

    for (index, item) in displayItems.enumerated() {
      if index % columnCount == 0 {
        currentRow = UIStackView()
        currentRow?.axis = .horizontal
        currentRow?.alignment = .fill
        currentRow?.distribution = .fillEqually
        currentRow?.spacing = AppSpacing.sm
        favoritesGrid.addArrangedSubview(currentRow!)
      }
      let itemView = createFavoriteItemView(item)
      currentRow?.addArrangedSubview(itemView)
    }
  }

  private func createFavoriteItemView(_ item: FavoriteItem) -> UIView {
    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false

    let iconView = UIImageView()
    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.contentMode = .scaleAspectFit
    iconView.backgroundColor = AppColors.tertiarySurface
    iconView.layer.cornerRadius = 14
    iconView.layer.cornerCurve = .continuous
    iconView.clipsToBounds = true
    iconView.tintColor = AppColors.secondaryText

    // Derive favicon URL from domain if not provided
    let effectiveFaviconURL = item.faviconURL ?? FaviconLoader.faviconURL(for: item.url)

    // Show fallback immediately (synchronous)
    let firstLetter = item.title.trimmingCharacters(in: .whitespaces).first.map(String.init)
    if let letter = firstLetter {
      let fallbackLabel = UILabel()
      fallbackLabel.text = letter
      fallbackLabel.font = UIFont.systemFont(ofSize: 22, weight: .medium)
      fallbackLabel.textColor = AppColors.primaryText
      fallbackLabel.textAlignment = .center
      fallbackLabel.translatesAutoresizingMaskIntoConstraints = false
      iconView.addSubview(fallbackLabel)
      NSLayoutConstraint.activate([
        fallbackLabel.centerXAnchor.constraint(equalTo: iconView.centerXAnchor),
        fallbackLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor)
      ])
    } else {
      iconView.image = UIImage(systemName: "globe")
      iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
    }

    // Try to load favicon asynchronously (overrides fallback when loaded)
    if let faviconURL = effectiveFaviconURL {
      FaviconLoader.shared.load(url: faviconURL) { [weak iconView] image in
        guard let image, let iconView else { return }
        // Remove fallback label
        iconView.subviews.forEach { $0.removeFromSuperview() }
        iconView.image = nil
        iconView.contentMode = .scaleAspectFill
        iconView.backgroundColor = .clear
        iconView.image = image
      }
    }

    let nameLabel = UILabel()
    nameLabel.translatesAutoresizingMaskIntoConstraints = false
    nameLabel.text = item.title
    nameLabel.font = AppTypography.caption
    nameLabel.textColor = AppColors.primaryText
    nameLabel.textAlignment = .center
    nameLabel.numberOfLines = 1
    nameLabel.lineBreakMode = .byTruncatingTail

    container.addSubview(iconView)
    container.addSubview(nameLabel)

    NSLayoutConstraint.activate([
      iconView.topAnchor.constraint(equalTo: container.topAnchor, constant: AppSpacing.xs),
      iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      iconView.widthAnchor.constraint(equalToConstant: 52),
      iconView.heightAnchor.constraint(equalToConstant: 52),

      nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: AppSpacing.xs),
      nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: AppSpacing.xxs),
      nameLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -AppSpacing.xxs),
      nameLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      nameLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 18),
    ])

    let tapGesture = UITapGestureRecognizer(target: self, action: #selector(favoriteTapped(_:)))
    container.addGestureRecognizer(tapGesture)
    container.isUserInteractionEnabled = true
    container.accessibilityLabel = item.title
    container.accessibilityHint = "打开收藏"

    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(favoriteLongPressed(_:)))
    longPress.minimumPressDuration = 0.5
    container.addGestureRecognizer(longPress)

    return container
  }

  private func updateEmptyStateForPrivateMode() {
    let secondary = isPrivateMode
      ? UIColor.white.withAlphaComponent(0.68)
      : AppColors.secondaryText
    favoritesEmptyLabel.textColor = secondary
  }

  @objc
  private func viewAllPressed() {
    delegate?.newTabViewDidSelectViewAll(self)
  }

  @objc
  private func addFavoritePressed() {
    delegate?.newTabViewDidSelectAddFavorite(self)
  }

  @objc
  private func favoriteTapped(_ gesture: UITapGestureRecognizer) {
    guard let container = gesture.view,
          let index = findFavoriteIndex(for: container) else { return }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    delegate?.newTabViewDidSelectFavorite(self, item: favoriteItems[index])
  }

  @objc
  private func favoriteLongPressed(_ gesture: UILongPressGestureRecognizer) {
    guard gesture.state == .began,
          let container = gesture.view,
          let index = findFavoriteIndex(for: container) else { return }
    let point = gesture.location(in: self)
    delegate?.newTabView(self, didLongPressFavorite: favoriteItems[index], at: point)
  }

  private func findFavoriteIndex(for view: UIView) -> Int? {
    let visibleItems = Array(favoriteItems.prefix(maxFavoritesDisplay))
    guard let row = favoritesGrid.arrangedSubviews.firstIndex(where: { $0.subviews.contains(view) }),
          let column = (favoritesGrid.arrangedSubviews[row] as? UIStackView)?.arrangedSubviews.firstIndex(of: view) else {
      return nil
    }
    let isWide = bounds.width > 400
    let columnCount = isWide ? 4 : 2
    return row * columnCount + column
  }

  private func updateResolvedColors() {
    let primary = isPrivateMode
      ? UIColor.white.withAlphaComponent(0.96)
      : AppColors.primaryText
    let secondary = isPrivateMode
      ? UIColor.white.withAlphaComponent(0.68)
      : AppColors.secondaryText
    let tertiary = isPrivateMode
      ? UIColor.white.withAlphaComponent(0.48)
      : AppColors.tertiaryText

    titleLabel.textColor = primary
    welcomeLabel.textColor = secondary
    dateLabel.textColor = tertiary
    searchImageView.tintColor = secondary
    textField.textColor = primary
    textField.tintColor = isPrivateMode
      ? AppColors.privateBrowsingAccent
      : AppColors.accent
    textField.attributedPlaceholder = NSAttributedString(
      string: "搜索或输入网址",
      attributes: [.foregroundColor: secondary.withAlphaComponent(0.72)]
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
      .resolvedColor(with: traitCollection)
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
  func textFieldDidBeginEditing(_ textField: UITextField) {
    updateSubmitButton()
    delegate?.newTabViewDidBeginEditing(self)
  }

  func textFieldDidEndEditing(_ textField: UITextField) {
    updateSubmitButton()
  }

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    submit()
    return true
  }
}
