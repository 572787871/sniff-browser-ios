import UIKit

enum BrowserToolbarAction {
  case back
  case forward
  case sniff
  case tabs
  case more
}

@MainActor
protocol BrowserToolbarDelegate: AnyObject {
  func browserToolbar(
    _ toolbar: BrowserToolbar,
    didSelect action: BrowserToolbarAction,
    sourceView: UIView
  )
}

final class BrowserToolbar: UIView {
  weak var toolbarDelegate: BrowserToolbarDelegate?

  private let materialView = AppMaterialView(
    style: .systemUltraThinMaterial,
    fallbackColor: AppColors.chromeFallback
  )
  private let backButton = BrowserChromeButton(symbol: "chevron.backward")
  private let forwardButton = BrowserChromeButton(symbol: "chevron.forward")
  private let sniffButton = BrowserChromeButton(
    symbol: "dot.radiowaves.left.and.right"
  )
  private let tabsButton = BrowserChromeButton(symbol: "square")
  private let moreButton = BrowserChromeButton(symbol: "ellipsis")
  private let tabCountLabel = UILabel()
  private let resourceBadgeLabel = UILabel()
  private let scanIndicator = UIActivityIndicatorView(style: .medium)
  private var isCollapsed = false
  private var isPrivateMode = false
  private var snifferActivationState: SniffingActivationState = .disabled

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

  func update(canGoBack: Bool, canGoForward: Bool, tabCount: Int) {
    backButton.isEnabled = canGoBack
    forwardButton.isEnabled = canGoForward
    tabCountLabel.text = tabCount > 99 ? "99+" : "\(max(1, tabCount))"
    tabsButton.accessibilityLabel = "标签页，共 \(max(1, tabCount)) 个"
  }

  func setSnifferState(
    resourceCount: Int,
    activationState: SniffingActivationState
  ) {
    snifferActivationState = activationState
    let count = max(0, resourceCount)
    resourceBadgeLabel.text = count > 99 ? "99+" : "\(count)"
    resourceBadgeLabel.isHidden = count == 0 || activationState != .active
    let isStarting = activationState == .starting
    scanIndicator.isHidden = !isStarting
    isStarting ? scanIndicator.startAnimating() : scanIndicator.stopAnimating()
    switch activationState {
    case .disabled:
      sniffButton.accessibilityLabel = "开启资源嗅探"
      sniffButton.accessibilityValue = nil
      sniffButton.tintColor = AppColors.secondaryText
    case .starting:
      sniffButton.accessibilityLabel = "资源嗅探"
      sniffButton.accessibilityValue = "正在开启"
    case .active:
      sniffButton.accessibilityLabel = "当前页面资源"
      sniffButton.accessibilityValue = count == 0
        ? "嗅探已开启，未发现资源"
        : "嗅探已开启，发现 \(count) 项资源"
    case .stopping:
      sniffButton.accessibilityLabel = "资源嗅探"
      sniffButton.accessibilityValue = "正在停止"
    case .failed:
      sniffButton.accessibilityLabel = "重新开启资源嗅探"
      sniffButton.accessibilityValue = "开启失败"
      sniffButton.tintColor = AppColors.danger
    }
    if activationState == .active || activationState == .starting {
      sniffButton.tintColor = isPrivateMode
        ? AppColors.privateBrowsingAccent
        : AppColors.accent
    }
  }

  func setPrivateMode(_ isPrivate: Bool) {
    guard isPrivateMode != isPrivate else { return }
    isPrivateMode = isPrivate
    overrideUserInterfaceStyle = isPrivate ? .dark : .unspecified
    materialView.contentView.backgroundColor = isPrivate
      ? AppColors.privateBrowsingSurface.withAlphaComponent(0.68)
      : .clear
    updateResolvedColors()
  }

  func setCollapsed(_ collapsed: Bool, animated: Bool) {
    guard collapsed != isCollapsed else { return }
    isCollapsed = collapsed
    accessibilityElementsHidden = collapsed
    isUserInteractionEnabled = !collapsed
    let changes = {
      self.transform = collapsed
        && !UIAccessibility.isReduceMotionEnabled
        ? CGAffineTransform(translationX: 0, y: AppMetrics.toolbarHeight + AppSpacing.lg)
        : .identity
      self.alpha = collapsed ? 0 : 1
    }
    guard animated else {
      changes()
      return
    }
    AppAppearance.animate(duration: 0.24, animations: changes)
  }

  private func configure() {
    translatesAutoresizingMaskIntoConstraints = false
    materialView.translatesAutoresizingMaskIntoConstraints = false
    materialView.layer.cornerCurve = .continuous
    materialView.layer.cornerRadius = 20
    materialView.layer.borderWidth = 0.5
    materialView.clipsToBounds = true
    addSubview(materialView)
    AppShadow.floating.apply(to: self)

    let definitions: [
      (button: BrowserChromeButton, action: BrowserToolbarAction, label: String)
    ] = [
      (backButton, .back, "后退"),
      (forwardButton, .forward, "前进"),
      (sniffButton, .sniff, "当前页面资源"),
      (tabsButton, .tabs, "标签页"),
      (moreButton, .more, "更多"),
    ]
    definitions.forEach { definition in
      definition.button.tintColor = AppColors.primaryText
      definition.button.accessibilityLabel = definition.label
      definition.button.widthAnchor.constraint(
        greaterThanOrEqualToConstant: AppMetrics.minimumTapSize
      ).isActive = true
      definition.button.heightAnchor.constraint(
        greaterThanOrEqualToConstant: AppMetrics.minimumTapSize
      ).isActive = true
      definition.button.addAction(
        UIAction { [weak self, weak button = definition.button] _ in
          guard let self, let button else { return }
          self.toolbarDelegate?.browserToolbar(
            self,
            didSelect: definition.action,
            sourceView: button
          )
        },
        for: .touchUpInside
      )
    }
    sniffButton.tintColor = AppColors.accent

    tabCountLabel.translatesAutoresizingMaskIntoConstraints = false
    tabCountLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
    tabCountLabel.textColor = AppColors.primaryText
    tabCountLabel.textAlignment = .center
    tabCountLabel.isAccessibilityElement = false
    tabsButton.addSubview(tabCountLabel)
    NSLayoutConstraint.activate([
      tabCountLabel.centerXAnchor.constraint(equalTo: tabsButton.centerXAnchor),
      tabCountLabel.centerYAnchor.constraint(equalTo: tabsButton.centerYAnchor),
      tabCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
    ])

    resourceBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
    resourceBadgeLabel.font = .monospacedDigitSystemFont(ofSize: 9, weight: .bold)
    resourceBadgeLabel.textColor = .white
    resourceBadgeLabel.backgroundColor = AppColors.accent
    resourceBadgeLabel.layer.cornerRadius = 8
    resourceBadgeLabel.clipsToBounds = true
    resourceBadgeLabel.textAlignment = .center
    resourceBadgeLabel.isHidden = true
    resourceBadgeLabel.isAccessibilityElement = false
    sniffButton.addSubview(resourceBadgeLabel)

    scanIndicator.translatesAutoresizingMaskIntoConstraints = false
    scanIndicator.color = AppColors.accent
    scanIndicator.isHidden = true
    sniffButton.addSubview(scanIndicator)

    NSLayoutConstraint.activate([
      resourceBadgeLabel.centerXAnchor.constraint(
        equalTo: sniffButton.centerXAnchor,
        constant: 13
      ),
      resourceBadgeLabel.centerYAnchor.constraint(
        equalTo: sniffButton.centerYAnchor,
        constant: -12
      ),
      resourceBadgeLabel.heightAnchor.constraint(equalToConstant: 16),
      resourceBadgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 16),
      scanIndicator.centerXAnchor.constraint(equalTo: sniffButton.centerXAnchor),
      scanIndicator.centerYAnchor.constraint(equalTo: sniffButton.centerYAnchor),
    ])

    let stack = UIStackView(
      arrangedSubviews: definitions.map(\.button)
    )
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .horizontal
    stack.alignment = .fill
    stack.distribution = .equalCentering
    materialView.contentView.addSubview(stack)
    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: AppMetrics.toolbarHeight),
      materialView.topAnchor.constraint(equalTo: topAnchor),
      materialView.leadingAnchor.constraint(equalTo: leadingAnchor),
      materialView.trailingAnchor.constraint(equalTo: trailingAnchor),
      materialView.bottomAnchor.constraint(equalTo: bottomAnchor),
      stack.topAnchor.constraint(equalTo: materialView.contentView.topAnchor),
      stack.leadingAnchor.constraint(
        equalTo: materialView.contentView.leadingAnchor,
        constant: AppSpacing.sm
      ),
      stack.trailingAnchor.constraint(
        equalTo: materialView.contentView.trailingAnchor,
        constant: -AppSpacing.sm
      ),
      stack.bottomAnchor.constraint(equalTo: materialView.contentView.bottomAnchor),
    ])
    updateResolvedColors()
    registerForTraitChanges([
      UITraitUserInterfaceStyle.self,
      UITraitAccessibilityContrast.self,
    ]) { (view: BrowserToolbar, _) in
      view.updateResolvedColors()
    }
    update(canGoBack: false, canGoForward: false, tabCount: 1)
    setSnifferState(resourceCount: 0, activationState: .disabled)
  }

  private func updateResolvedColors() {
    materialView.layer.borderColor = (
      isPrivateMode
        ? UIColor.white.withAlphaComponent(0.16)
        : AppColors.separator.resolvedColor(with: traitCollection)
    ).cgColor
    let primary = isPrivateMode ? UIColor.white : AppColors.primaryText
    [backButton, forwardButton, tabsButton, moreButton].forEach {
      $0.tintColor = primary
    }
    switch snifferActivationState {
    case .disabled, .stopping:
      sniffButton.tintColor = AppColors.secondaryText
    case .failed:
      sniffButton.tintColor = AppColors.danger
    case .starting, .active:
      sniffButton.tintColor = isPrivateMode
        ? AppColors.privateBrowsingAccent
        : AppColors.accent
    }
    tabCountLabel.textColor = primary
    scanIndicator.color = isPrivateMode
      ? AppColors.privateBrowsingAccent
      : AppColors.accent
    layer.shadowColor = UIColor.black.cgColor
  }
}

private final class BrowserChromeButton: UIButton {
  init(symbol: String) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    setImage(
      UIImage(
        systemName: symbol,
        withConfiguration: UIImage.SymbolConfiguration(
          pointSize: AppMetrics.navigationIconSize,
          weight: .regular
        )
      ),
      for: .normal
    )
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  override var isHighlighted: Bool {
    didSet {
      let changes = {
        self.alpha = self.isHighlighted ? 0.58 : 1
        self.transform = self.isHighlighted
          ? CGAffineTransform(scaleX: 0.96, y: 0.96)
          : .identity
      }
      guard !UIAccessibility.isReduceMotionEnabled else {
        changes()
        return
      }
      UIView.animate(
        withDuration: 0.16,
        delay: 0,
        options: [.beginFromCurrentState, .allowUserInteraction],
        animations: changes
      )
    }
  }
}
