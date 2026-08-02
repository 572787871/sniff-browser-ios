import UIKit

enum BrowserQuickAction: CaseIterable, Equatable {
  case newTab
  case share
  case favorite
  case reload

  var title: String {
    switch self {
    case .newTab: return "新建标签"
    case .share: return "分享"
    case .favorite: return "添加收藏"
    case .reload: return "刷新"
    }
  }

  var symbolName: String {
    switch self {
    case .newTab: return "plus"
    case .share: return "square.and.arrow.up"
    case .favorite: return "star"
    case .reload: return "arrow.clockwise"
    }
  }
}

enum BrowserMenuDestination: CaseIterable, Equatable {
  case downloads
  case files
  case favorites
  case history
  case userCenter
  case settings

  var title: String {
    switch self {
    case .downloads: return "下载管理"
    case .files: return "文件管理"
    case .favorites: return "收藏夹"
    case .history: return "历史记录"
    case .userCenter: return "用户中心"
    case .settings: return "浏览器设置"
    }
  }

  var symbolName: String {
    switch self {
    case .downloads: return "arrow.down.circle"
    case .files: return "folder"
    case .favorites: return "star"
    case .history: return "clock.arrow.circlepath"
    case .userCenter: return "person.crop.circle"
    case .settings: return "gearshape"
    }
  }
}

struct BrowserMoreMenuState: Equatable {
  var hasCurrentPage: Bool
  var downloadSummary: String?
  var fileSummary: String?
  var accountSummary: String?
  var favoriteActionState = FavoriteActionState(
    isEnabled: false,
    isFavorite: false
  )

  func isEnabled(_ action: BrowserQuickAction) -> Bool {
    switch action {
    case .newTab:
      return true
    case .favorite:
      return favoriteActionState.isEnabled
    case .share, .reload:
      return hasCurrentPage
    }
  }

  func title(for action: BrowserQuickAction) -> String {
    action == .favorite ? favoriteActionState.title : action.title
  }

  func symbolName(for action: BrowserQuickAction) -> String {
    action == .favorite
      ? favoriteActionState.systemImageName
      : action.symbolName
  }

  func detail(for destination: BrowserMenuDestination) -> String? {
    switch destination {
    case .downloads: return downloadSummary
    case .files: return fileSummary
    case .userCenter: return accountSummary
    case .favorites, .history, .settings: return nil
    }
  }
}

@MainActor
final class BrowserMoreMenuViewController: UIViewController {
  var onQuickAction: ((BrowserQuickAction) -> Void)?
  var onSelectDestination: ((BrowserMenuDestination) -> Void)?

  private let state: BrowserMoreMenuState
  private let tableView = UITableView(frame: .zero, style: .insetGrouped)
  private let quickActionsView = BrowserQuickActionsView()
  private let quickActionsHeader = UIView()

  init(state: BrowserMoreMenuState) {
    self.state = state
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .pageSheet
  }

  required init?(coder: NSCoder) {
    return nil
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = AppColors.background
    configureHeader()
    configureTable()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let height: CGFloat = traitCollection.preferredContentSizeCategory
      .isAccessibilityCategory ? 148 : 116
    guard quickActionsHeader.frame.width != tableView.bounds.width
      || quickActionsHeader.frame.height != height
    else {
      return
    }
    quickActionsHeader.frame = CGRect(
      x: 0,
      y: 0,
      width: tableView.bounds.width,
      height: height
    )
    tableView.tableHeaderView = quickActionsHeader
  }

  private func configureHeader() {
    quickActionsHeader.frame = CGRect(x: 0, y: 0, width: 1, height: 116)
    quickActionsView.translatesAutoresizingMaskIntoConstraints = false
    quickActionsView.configure(state: state)
    quickActionsView.onSelect = { [weak self] action in
      self?.dismissAndPerform {
        self?.onQuickAction?(action)
      }
    }
    quickActionsHeader.addSubview(quickActionsView)
    NSLayoutConstraint.activate([
      quickActionsView.topAnchor.constraint(
        equalTo: quickActionsHeader.topAnchor,
        constant: AppSpacing.sm
      ),
      quickActionsView.leadingAnchor.constraint(
        equalTo: quickActionsHeader.leadingAnchor,
        constant: AppSpacing.md
      ),
      quickActionsView.trailingAnchor.constraint(
        equalTo: quickActionsHeader.trailingAnchor,
        constant: -AppSpacing.md
      ),
      quickActionsView.bottomAnchor.constraint(
        equalTo: quickActionsHeader.bottomAnchor,
        constant: -AppSpacing.sm
      ),
    ])
    tableView.tableHeaderView = quickActionsHeader
  }

  private func configureTable() {
    tableView.translatesAutoresizingMaskIntoConstraints = false
    tableView.backgroundColor = .clear
    tableView.separatorColor = AppColors.separator
    tableView.rowHeight = 56
    tableView.dataSource = self
    tableView.delegate = self
    tableView.register(
      UITableViewCell.self,
      forCellReuseIdentifier: "BrowserMenuRow"
    )
    view.addSubview(tableView)
    NSLayoutConstraint.activate([
      tableView.topAnchor.constraint(equalTo: view.topAnchor),
      tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
  }

  private func dismissAndPerform(_ action: @escaping () -> Void) {
    dismiss(animated: true, completion: action)
  }
}

extension BrowserMoreMenuViewController: UITableViewDataSource, UITableViewDelegate {
  func numberOfSections(in tableView: UITableView) -> Int {
    2
  }

  func tableView(
    _ tableView: UITableView,
    numberOfRowsInSection section: Int
  ) -> Int {
    section == 0 ? 4 : 2
  }

  func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  ) -> UITableViewCell {
    let destinations: [[BrowserMenuDestination]] = [
      [.downloads, .files, .favorites, .history],
      [.userCenter, .settings],
    ]
    let destination = destinations[indexPath.section][indexPath.row]
    let cell = tableView.dequeueReusableCell(
      withIdentifier: "BrowserMenuRow",
      for: indexPath
    )
    var content = UIListContentConfiguration.valueCell()
    content.text = destination.title
    content.secondaryText = state.detail(for: destination)
    content.image = UIImage(systemName: destination.symbolName)
    content.imageProperties.tintColor = AppColors.accent
    content.textProperties.font = AppTypography.body
    content.secondaryTextProperties.font = AppTypography.subheadline
    content.secondaryTextProperties.color = AppColors.secondaryText
    cell.contentConfiguration = content
    cell.accessoryType = .disclosureIndicator
    cell.backgroundColor = AppColors.surface
    cell.accessibilityHint = "打开\(destination.title)"
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    let destinations: [[BrowserMenuDestination]] = [
      [.downloads, .files, .favorites, .history],
      [.userCenter, .settings],
    ]
    let destination = destinations[indexPath.section][indexPath.row]
    dismissAndPerform { [weak self] in
      self?.onSelectDestination?(destination)
    }
  }
}

private final class BrowserQuickActionsView: UIView {
  var onSelect: ((BrowserQuickAction) -> Void)?

  private let stackView = UIStackView()

  override init(frame: CGRect) {
    super.init(frame: frame)
    configureView()
  }

  required init?(coder: NSCoder) {
    return nil
  }

  func configure(state: BrowserMoreMenuState) {
    stackView.arrangedSubviews.forEach {
      stackView.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }
    BrowserQuickAction.allCases.forEach { action in
      let button = BrowserQuickActionButton(
        action: action,
        title: state.title(for: action),
        symbolName: state.symbolName(for: action)
      )
      button.isEnabled = state.isEnabled(action)
      button.addAction(
        UIAction { [weak self] _ in
          self?.onSelect?(action)
        },
        for: .touchUpInside
      )
      stackView.addArrangedSubview(button)
    }
  }

  private func configureView() {
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.axis = .horizontal
    stackView.alignment = .top
    stackView.distribution = .fillEqually
    stackView.spacing = AppSpacing.xs
    addSubview(stackView)
    NSLayoutConstraint.activate([
      stackView.topAnchor.constraint(equalTo: topAnchor),
      stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
      stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
      stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }
}

private final class BrowserQuickActionButton: UIControl {
  private let action: BrowserQuickAction
  private let symbolBackground = UIView()
  private let imageView = UIImageView()
  private let titleLabel = UILabel()

  init(
    action: BrowserQuickAction,
    title: String,
    symbolName: String
  ) {
    self.action = action
    super.init(frame: .zero)
    configureView(title: title, symbolName: symbolName)
  }

  required init?(coder: NSCoder) {
    return nil
  }

  override var isEnabled: Bool {
    didSet {
      alpha = isEnabled ? 1 : 0.38
      accessibilityTraits = isEnabled ? [.button] : [.button, .notEnabled]
    }
  }

  override var isHighlighted: Bool {
    didSet {
      let changes = {
        self.transform = self.isHighlighted
          ? CGAffineTransform(scaleX: 0.96, y: 0.96)
          : .identity
        self.alpha = self.isEnabled
          ? (self.isHighlighted ? 0.68 : 1)
          : 0.38
      }
      if UIAccessibility.isReduceMotionEnabled {
        changes()
      } else {
        UIView.animate(
          withDuration: AppAppearance.quickAnimationDuration,
          delay: 0,
          options: [.beginFromCurrentState, .allowUserInteraction],
          animations: changes
        )
      }
    }
  }

  private func configureView(title: String, symbolName: String) {
    isAccessibilityElement = true
    accessibilityLabel = title
    accessibilityTraits = .button

    symbolBackground.translatesAutoresizingMaskIntoConstraints = false
    symbolBackground.backgroundColor = AppColors.tertiarySurface
    symbolBackground.layer.cornerRadius = AppRadius.control
    symbolBackground.layer.cornerCurve = .continuous
    symbolBackground.isUserInteractionEnabled = false

    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.image = UIImage(
      systemName: symbolName,
      withConfiguration: UIImage.SymbolConfiguration(
        pointSize: AppMetrics.navigationIconSize,
        weight: .medium
      )
    )
    imageView.tintColor = AppColors.accent
    imageView.contentMode = .scaleAspectFit

    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.text = title
    titleLabel.font = AppTypography.caption
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.textColor = AppColors.primaryText
    titleLabel.textAlignment = .center
    titleLabel.numberOfLines = 2

    addSubview(symbolBackground)
    symbolBackground.addSubview(imageView)
    addSubview(titleLabel)

    NSLayoutConstraint.activate([
      heightAnchor.constraint(greaterThanOrEqualToConstant: 88),
      symbolBackground.topAnchor.constraint(equalTo: topAnchor),
      symbolBackground.centerXAnchor.constraint(equalTo: centerXAnchor),
      symbolBackground.widthAnchor.constraint(equalToConstant: 48),
      symbolBackground.heightAnchor.constraint(equalTo: symbolBackground.widthAnchor),
      imageView.centerXAnchor.constraint(equalTo: symbolBackground.centerXAnchor),
      imageView.centerYAnchor.constraint(equalTo: symbolBackground.centerYAnchor),
      imageView.widthAnchor.constraint(equalToConstant: 22),
      imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor),
      titleLabel.topAnchor.constraint(
        equalTo: symbolBackground.bottomAnchor,
        constant: AppSpacing.xs
      ),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
      titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
      titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
    ])
  }
}
