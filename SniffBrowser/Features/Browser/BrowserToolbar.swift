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
    style: .systemChromeMaterial,
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

  func setMoreMenu(_ menu: UIMenu) {
    moreButton.menu = menu
    moreButton.showsMenuAsPrimaryAction = true
  }

  private func configure() {
    translatesAutoresizingMaskIntoConstraints = false
    materialView.translatesAutoresizingMaskIntoConstraints = false
    materialView.layer.cornerCurve = .continuous
    materialView.layer.cornerRadius = AppRadius.card
    materialView.layer.borderWidth = 0.5
    materialView.clipsToBounds = true
    addSubview(materialView)

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
      if case .more = definition.action {
        definition.button.showsMenuAsPrimaryAction = true
      } else {
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

    let stack = UIStackView(
      arrangedSubviews: definitions.map(\.button)
    )
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .horizontal
    stack.alignment = .fill
    stack.distribution = .equalSpacing
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
  }

  private func updateResolvedColors() {
    materialView.layer.borderColor = AppColors.separator
      .resolvedColor(with: traitCollection)
      .cgColor
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
          pointSize: 20,
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
