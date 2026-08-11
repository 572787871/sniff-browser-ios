import UIKit

@MainActor
final class TabOverviewViewController: BaseViewController {
    var onSelectTab: ((UUID) -> Void)?
    var onCloseTab: ((UUID) -> Void)?
    var onNewTab: ((Bool) -> Void)?

    var onCloseOtherTabs: ((UUID) -> Void)?
    var onCloseAllNormalTabs: (() -> Void)?
    var onCloseAllTabs: ((Bool) -> Void)?
    var onCopyTabURL: ((UUID, URL) -> Void)?
    var onShareTab: ((UUID, URL?) -> Void)?
    var favoriteActionStateProvider: ((URL?) -> FavoriteActionState)?
    var onToggleFavorite: ((UUID) -> Void)?
    var onModeChanged: ((Bool) -> Void)?
    var onDone: (() -> Void)?

    private struct PendingTransition {
        let mode: TabOverviewMode
        let animated: Bool
        let notifyDelegate: Bool
    }

    private var allItems: [TabOverviewItem]
    private var pagingState: TabOverviewPagingState
    private var isPageTransitionInFlight = false
    private var queuedTransition: PendingTransition?
    private var selectedTransitionItemID: UUID?
    private var selectedTransitionFrameInWindow: CGRect?
    private var usesSpatialTransition = true

    private let privacyTintView = UIView()
    private let modeControl = UISegmentedControl(
        items: TabOverviewMode.allCases.map(\.title)
    )
    private let bottomBar = TabOverviewBottomBar()
    private lazy var standardPage = makePage(for: .standard)
    private lazy var privatePage = makePage(for: .privateBrowsing)
    private lazy var pageViewController = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .horizontal,
        options: [.interPageSpacing: NSNumber(value: 0)]
    )

    init(items: [TabOverviewItem]) {
        allItems = items
        let initialMode: TabOverviewMode =
            items.first(where: \.isSelected)?.isPrivate == true
                ? .privateBrowsing
                : .standard
        pagingState = TabOverviewPagingState(selectedMode: initialMode)
        super.init(title: "标签页", prefersLargeTitle: false)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigation()
        configureBackground()
        configureBottomBar()
        configurePageController()
        registerForEnvironmentChanges()
        updatePages(animated: false)
        applyModeAppearance(animated: false)
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        saveScrollOffset(for: pagingState.selectedMode)
        coordinator.animate { [weak self] _ in
            self?.standardPage.invalidateGridLayout()
            self?.privatePage.invalidateGridLayout()
        } completion: { [weak self] _ in
            guard let self else { return }
            self.restoreScrollOffset(for: self.pagingState.selectedMode)
        }
    }

    func update(items: [TabOverviewItem]) {
        allItems = items
        guard isViewLoaded else { return }
        updatePages(animated: true)
        updateBottomBarTabCount()
    }

    func selectMode(isPrivate: Bool, animated: Bool = true) {
        let mode: TabOverviewMode = isPrivate ? .privateBrowsing : .standard
        guard isViewLoaded else {
            pagingState.selectMode(mode)
            return
        }
        requestMode(
            mode,
            animated: animated,
            notifyDelegate: false
        )
    }

    var transitionItemID: UUID? {
        guard usesSpatialTransition else { return nil }
        return selectedTransitionItemID
            ?? allItems.first(where: \.isSelected)?.id
    }

    func disableNextSpatialTransition() {
        usesSpatialTransition = false
    }

    func transitionImage(for itemID: UUID) -> UIImage? {
        allItems.first(where: { $0.id == itemID })?.thumbnail
    }

    func transitionFrame(
        for itemID: UUID,
        in coordinateSpace: UIView,
        ensureVisible: Bool
    ) -> CGRect? {
        if !ensureVisible,
           itemID == selectedTransitionItemID,
           let selectedTransitionFrameInWindow,
           let window = view.window {
            return window.convert(
                selectedTransitionFrameInWindow,
                to: coordinateSpace
            )
        }
        guard let item = allItems.first(where: { $0.id == itemID }) else {
            return nil
        }
        let mode: TabOverviewMode = item.isPrivate
            ? .privateBrowsing
            : .standard
        guard visiblePageMode == mode else { return nil }
        view.layoutIfNeeded()
        return page(for: mode).transitionFrame(
            for: itemID,
            in: coordinateSpace,
            ensureVisible: ensureVisible
        )
    }

    func setTransitionItemHidden(_ itemID: UUID, hidden: Bool) {
        guard let item = allItems.first(where: { $0.id == itemID }) else {
            return
        }
        page(for: item.isPrivate ? .privateBrowsing : .standard)
            .setTransitionItemHidden(itemID, hidden: hidden)
    }

    func debugLogTransitionState(
        _ phase: String,
        itemID: UUID,
        in coordinateSpace: UIView
    ) {
        #if DEBUG
        guard let item = allItems.first(where: { $0.id == itemID }) else {
            AppLogger(.navigation).debug(
                "\(phase) item=\(itemID.uuidString) overviewItem=nil"
            )
            return
        }
        page(for: item.isPrivate ? .privateBrowsing : .standard)
            .debugLogTransitionState(
                phase,
                itemID: itemID,
                in: coordinateSpace
            )
        #endif
    }

    /// 在导航控制器改变安全区之前保存用户实际点击位置。
    func captureCurrentTransitionFrameIfNeeded() {
        guard selectedTransitionFrameInWindow == nil,
              let itemID = transitionItemID
        else { return }
        selectedTransitionItemID = itemID
        captureTransitionFrame(for: itemID)
    }

    private func captureTransitionFrame(for itemID: UUID) {
        selectedTransitionFrameInWindow = nil
        guard isViewLoaded,
              let item = allItems.first(where: { $0.id == itemID }),
              let window = view.window
        else { return }
        let mode: TabOverviewMode = item.isPrivate
            ? .privateBrowsing
            : .standard
        guard visiblePageMode == mode else { return }
        view.layoutIfNeeded()
        guard let frame = page(for: mode).transitionFrame(
            for: itemID,
            in: window,
            ensureVisible: false
        ), frame.intersects(window.bounds)
        else { return }
        selectedTransitionFrameInWindow = frame
    }

    /// 将总览的辅助层拆开，以便主网页快照独立完成空间转场。
    func prepareSpatialTransition(enteringOverview: Bool) {
        loadViewIfNeeded()
        view.layoutIfNeeded()
        standardPage.resetTransitionPresentationState()
        privatePage.resetTransitionPresentationState()
        view.backgroundColor = .clear
        privacyTintView.backgroundColor = AppColors.background
        privacyTintView.alpha = enteringOverview ? 0 : 1
        pageViewController.view.alpha = enteringOverview ? 0 : 1
        bottomBar.alpha = enteringOverview ? 0 : 1
        bottomBar.transform = enteringOverview
            ? CGAffineTransform(translationX: 0, y: 24)
            : .identity
    }

    func animateSpatialTransition(enteringOverview: Bool) {
        privacyTintView.alpha = enteringOverview ? 1 : 0
        pageViewController.view.alpha = enteringOverview ? 1 : 0
        bottomBar.alpha = enteringOverview ? 1 : 0
        bottomBar.transform = enteringOverview
            ? .identity
            : CGAffineTransform(translationX: 0, y: 24)
    }

    func completeSpatialTransition() {
        view.backgroundColor = AppColors.background
        privacyTintView.alpha = 0
        pageViewController.view.alpha = 1
        bottomBar.alpha = 1
        bottomBar.transform = .identity
        standardPage.resetTransitionPresentationState()
        privatePage.resetTransitionPresentationState()
        selectedTransitionFrameInWindow = nil
        selectedTransitionItemID = nil
    }

    private func configureNavigation() {
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.backButtonDisplayMode = .minimal
        navigationItem.rightBarButtonItem = makeMoreMenuButton()
        modeControl.selectedSegmentIndex = pagingState.selectedMode.rawValue
        modeControl.selectedSegmentTintColor = AppColors.elevatedSurface
        modeControl.setTitleTextAttributes(
            [
                .font: AppTypography.subheadline,
                .foregroundColor: AppColors.secondaryText
            ],
            for: .normal
        )
        modeControl.setTitleTextAttributes(
            [
                .font: AppTypography.subheadline,
                .foregroundColor: AppColors.primaryText
            ],
            for: .selected
        )
        modeControl.addTarget(
            self,
            action: #selector(modeControlChanged),
            for: .valueChanged
        )
        modeControl.accessibilityLabel = "普通与无痕标签组"
        modeControl.accessibilityIdentifier = "tabs.modeControl"
        navigationItem.titleView = modeControl
    }

    private func makeMoreMenuButton() -> UIBarButtonItem {
        let button = UIButton(type: .system)
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 19, weight: .medium)
        button.setImage(UIImage(systemName: "ellipsis", withConfiguration: symbolConfig), for: .normal)
        button.tintColor = AppColors.accent
        button.menu = makeMoreMenu()
        button.showsMenuAsPrimaryAction = true
        button.accessibilityLabel = "更多操作"
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: AppMetrics.minimumTapSize),
            button.heightAnchor.constraint(equalToConstant: AppMetrics.minimumTapSize)
        ])
        return UIBarButtonItem(customView: button)
    }

    private func makeMoreMenu() -> UIMenu {
        let isPrivate = pagingState.selectedMode.isPrivate
        let currentCount = allItems.filter { $0.isPrivate == isPrivate }.count

        let selectAction = UIAction(
            title: "选择标签页",
            image: UIImage(systemName: "checkmark.circle")
        ) { _ in
            // Placeholder — no action yet
        }

        let groupAction = UIAction(
            title: "按网站分组",
            image: UIImage(systemName: "square.grid.2x2")
        ) { _ in
            // Placeholder — no action yet
        }

        let closeAllAction = UIAction(
            title: "关闭全部标签页",
            image: UIImage(systemName: "trash"),
            attributes: currentCount > 0 ? [.destructive] : [.disabled, .destructive]
        ) { [weak self] _ in
            self?.showCloseAllConfirmation()
        }

        let groupMenu = UIMenu(options: .displayInline, children: [selectAction, groupAction])
        let closeMenu = UIMenu(options: .displayInline, children: [closeAllAction])

        return UIMenu(children: [groupMenu, closeMenu])
    }

    private func showCloseAllConfirmation() {
        let isPrivate = pagingState.selectedMode.isPrivate
        let currentCount = allItems.filter { $0.isPrivate == isPrivate }.count

        guard currentCount > 1 else {
            performCloseAllTabs(isPrivate: isPrivate)
            return
        }

        let modeName = isPrivate ? "无痕" : "普通"
        let alert = UIAlertController(
            title: "关闭全部标签页？",
            message: "这将关闭当前分组中的全部 \(currentCount) 个\(modeName)标签页。",
            preferredStyle: .actionSheet
        )

        let closeAction = UIAlertAction(
            title: "关闭全部",
            style: .destructive
        ) { [weak self] _ in
            self?.performCloseAllTabs(isPrivate: isPrivate)
        }
        alert.addAction(closeAction)

        let cancelAction = UIAlertAction(title: "取消", style: .cancel)
        alert.addAction(cancelAction)

        // For iPad: set popover source
        if let popover = alert.popoverPresentationController {
            if let rightBarButton = navigationItem.rightBarButtonItem {
                popover.barButtonItem = rightBarButton
            }
        }

        present(alert, animated: true)
    }

    private func performCloseAllTabs(isPrivate: Bool) {
        guard allItems.contains(where: { $0.isPrivate == isPrivate }) else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        allItems.removeAll { $0.isPrivate == isPrivate }
        updatePages(animated: true)
        updateBottomBarTabCount()
        onCloseAllTabs?(isPrivate)
    }

    private func configureBackground() {
        privacyTintView.backgroundColor = AppColors.background
        privacyTintView.accessibilityIdentifier = "tabs.transitionBackground"
        privacyTintView.isUserInteractionEnabled = false
        privacyTintView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(privacyTintView)

        NSLayoutConstraint.activate([
            privacyTintView.topAnchor.constraint(equalTo: contentView.topAnchor),
            privacyTintView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            privacyTintView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            privacyTintView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func configureBottomBar() {
        bottomBar.accessibilityIdentifier = "tabs.bottomBar"
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bottomBar)
        bottomBar.mode = pagingState.selectedMode
        bottomBar.onNewTab = { [weak self] mode in
            self?.createTab(isPrivate: mode.isPrivate)
        }
        bottomBar.onDone = { [weak self] in
            self?.finish()
        }

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(
                equalTo: view.layoutMarginsGuide.leadingAnchor
            ),
            bottomBar.trailingAnchor.constraint(
                equalTo: view.layoutMarginsGuide.trailingAnchor
            ),
            bottomBar.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -AppSpacing.sm
            )
        ])
    }

    private func configurePageController() {
        pageViewController.dataSource = self
        pageViewController.delegate = self
        pageViewController.view.backgroundColor = .clear
        pageViewController.view.accessibilityIdentifier = "tabs.pageContainer"
        pageViewController.view.clipsToBounds = true
        pageViewController.view.directionalLayoutMargins = .zero
        pageViewController.view.insetsLayoutMarginsFromSafeArea = false

        addChild(pageViewController)
        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(pageViewController.view)
        NSLayoutConstraint.activate([
            pageViewController.view.topAnchor.constraint(
                equalTo: contentView.safeAreaLayoutGuide.topAnchor
            ),
            pageViewController.view.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor
            ),
            pageViewController.view.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor
            ),
            pageViewController.view.bottomAnchor.constraint(
                equalTo: bottomBar.topAnchor,
                constant: -AppSpacing.xs
            )
        ])
        pageViewController.didMove(toParent: self)
        pageViewController.setViewControllers(
            [page(for: pagingState.selectedMode)],
            direction: .forward,
            animated: false
        )

        pageViewController.view.subviews
            .compactMap { $0 as? UIScrollView }
            .forEach {
                $0.isDirectionalLockEnabled = true
                $0.showsHorizontalScrollIndicator = false
                $0.contentInset = .zero
                $0.scrollIndicatorInsets = .zero
                $0.clipsToBounds = true
            }
        pageViewController.viewControllers?.forEach {
            $0.view.clipsToBounds = true
        }
        contentView.bringSubviewToFront(bottomBar)
    }

    private func makePage(
        for mode: TabOverviewMode
    ) -> TabOverviewPageViewController {
        let controller = TabOverviewPageViewController(mode: mode)
        controller.onSelectItem = { [weak self] itemID in
            guard let self else { return }
            self.usesSpatialTransition = true
            self.beginSpatialTransition(for: itemID)
            self.captureTransitionFrame(for: itemID)
            self.onSelectTab?(itemID)
        }
        controller.onCloseItem = { [weak self] itemID in
            self?.close(itemID: itemID)
        }
        controller.contextMenuProvider = {
            [weak self] item, sourceView, sourceRect in
            self?.makeContextMenu(
                for: item,
                sourceView: sourceView,
                sourceRect: sourceRect
            )
        }
        controller.onScrollOffsetChange = { [weak self] offset in
            self?.pagingState.saveScrollOffset(offset, for: mode)
        }
        return controller
    }

    private func beginSpatialTransition(for itemID: UUID) {
        // A controller normally performs one navigation transition before it
        // is removed. Clear any stale context anyway so a cancelled/fallback
        // transition cannot donate its frame to a later selection.
        selectedTransitionFrameInWindow = nil
        selectedTransitionItemID = itemID
    }

    private func page(
        for mode: TabOverviewMode
    ) -> TabOverviewPageViewController {
        mode.isPrivate ? privatePage : standardPage
    }

    private func updatePages(animated: Bool) {
        standardPage.update(
            items: allItems.filter { !$0.isPrivate },
            animated: animated
        )
        privatePage.update(
            items: allItems.filter(\.isPrivate),
            animated: animated
        )
    }

    private func requestMode(
        _ mode: TabOverviewMode,
        animated: Bool,
        notifyDelegate: Bool
    ) {
        guard mode != pagingState.selectedMode || isPageTransitionInFlight else {
            applyModeAppearance(animated: false)
            return
        }

        if isPageTransitionInFlight {
            queuedTransition = PendingTransition(
                mode: mode,
                animated: animated,
                notifyDelegate: notifyDelegate
            )
            bottomBar.mode = pagingState.selectedMode
            return
        }

        saveScrollOffset(for: pagingState.selectedMode)
        let direction: UIPageViewController.NavigationDirection =
            mode.rawValue > pagingState.selectedMode.rawValue
                ? .forward
                : .reverse
        let shouldAnimate = animated && !UIAccessibility.isReduceMotionEnabled

        guard shouldAnimate else {
            pageViewController.setViewControllers(
                [page(for: mode)],
                direction: direction,
                animated: false
            )
            commitMode(mode, notifyDelegate: notifyDelegate)
            drainQueuedTransitionIfNeeded()
            return
        }

        isPageTransitionInFlight = true
        bottomBar.mode = mode
        pageViewController.setViewControllers(
            [page(for: mode)],
            direction: direction,
            animated: true
        ) { [weak self] completed in
            guard let self else { return }
            self.isPageTransitionInFlight = false
            let visibleMode = self.visiblePageMode
            if completed, visibleMode == mode {
                self.commitMode(mode, notifyDelegate: notifyDelegate)
            } else {
                self.showSelectedPageWithoutAnimation()
                self.applyModeAppearance(animated: false)
            }
            self.drainQueuedTransitionIfNeeded()
        }
    }

    private func commitMode(
        _ mode: TabOverviewMode,
        notifyDelegate: Bool
    ) {
        let didChange = pagingState.selectMode(mode)
        restoreScrollOffset(for: mode)
        applyModeAppearance(animated: true)
        if didChange, notifyDelegate {
            onModeChanged?(mode.isPrivate)
        }
    }

    private func drainQueuedTransitionIfNeeded() {
        guard let queuedTransition else { return }
        self.queuedTransition = nil
        requestMode(
            queuedTransition.mode,
            animated: queuedTransition.animated,
            notifyDelegate: queuedTransition.notifyDelegate
        )
    }

    private var visiblePageMode: TabOverviewMode? {
        (pageViewController.viewControllers?.first as? TabOverviewPageViewController)?
            .mode
    }

    private func saveScrollOffset(for mode: TabOverviewMode) {
        guard isViewLoaded else { return }
        pagingState.saveScrollOffset(page(for: mode).scrollOffsetY, for: mode)
    }

    private func restoreScrollOffset(for mode: TabOverviewMode?) {
        guard let mode else { return }
        page(for: mode).restoreScrollOffset(
            pagingState.scrollOffset(for: mode)
        )
    }

    private func showSelectedPageWithoutAnimation() {
        pageViewController.setViewControllers(
            [page(for: pagingState.selectedMode)],
            direction: .forward,
            animated: false
        )
        restoreScrollOffset(for: pagingState.selectedMode)
    }

    private func applyModeAppearance(animated: Bool) {
        let mode = pagingState.selectedMode
        modeControl.selectedSegmentIndex = mode.rawValue
        bottomBar.mode = mode
        modeControl.backgroundColor = nil
        modeControl.selectedSegmentTintColor = AppColors.elevatedSurface
        modeControl.setTitleTextAttributes(
            [
                .font: AppTypography.subheadline,
                .foregroundColor: AppColors.secondaryText
            ],
            for: .normal
        )
        modeControl.setTitleTextAttributes(
            [
                .font: AppTypography.subheadline,
                .foregroundColor: AppColors.primaryText
            ],
            for: .selected
        )

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = AppColors.background
        navAppearance.shadowColor = AppColors.separator
        navAppearance.titleTextAttributes = [
            .foregroundColor: AppColors.primaryText,
            .font: AppTypography.headline
        ]
        navAppearance.largeTitleTextAttributes = [
            .foregroundColor: AppColors.primaryText,
            .font: AppTypography.largeTitle
        ]
        navigationController?.navigationBar.tintColor = AppColors.accent
        navigationController?.navigationBar.standardAppearance = navAppearance
        navigationController?.navigationBar.compactAppearance = navAppearance
        navigationController?.navigationBar.scrollEdgeAppearance = navAppearance
        updateBottomBarTabCount()
        let changes = {
            self.privacyTintView.alpha = 0
            self.contentView.backgroundColor = .clear
        }
        if animated {
            AppAppearance.animate(animations: changes)
        } else {
            changes()
        }
    }

    private func registerForEnvironmentChanges() {
        registerForTraitChanges([
            UITraitPreferredContentSizeCategory.self
        ]) { (controller: TabOverviewViewController, _) in
            controller.standardPage.invalidateGridLayout()
            controller.privatePage.invalidateGridLayout()
        }
    }

    private func updateBottomBarTabCount() {
        let isPrivate = pagingState.selectedMode.isPrivate
        bottomBar.tabCount = allItems.filter { $0.isPrivate == isPrivate }.count
    }

    private func createTab(isPrivate: Bool) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onNewTab?(isPrivate)
    }

    private func close(itemID: UUID) {
        guard allItems.contains(where: { $0.id == itemID }) else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        allItems.removeAll { $0.id == itemID }
        updatePages(animated: true)
        updateBottomBarTabCount()
        onCloseTab?(itemID)
    }

    private func closeOtherTabs(keeping item: TabOverviewItem) {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        allItems.removeAll {
            $0.isPrivate == item.isPrivate && $0.id != item.id
        }
        updatePages(animated: true)
        updateBottomBarTabCount()
        onCloseOtherTabs?(item.id)
    }

    private func closeAllNormalTabs() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        allItems.removeAll { !$0.isPrivate }
        updatePages(animated: true)
        updateBottomBarTabCount()
        onCloseAllNormalTabs?()
    }

    private func closeAllTabs(isPrivate: Bool) {
        // Legacy method — delegates to the new confirmation flow
        showCloseAllConfirmation()
    }

    private func copyURL(for item: TabOverviewItem) {
        guard let url = item.url else { return }
        UIPasteboard.general.url = url
        onCopyTabURL?(item.id, url)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func share(
        _ item: TabOverviewItem,
        sourceView: UIView,
        sourceRect: CGRect
    ) {
        if let onShareTab {
            onShareTab(item.id, item.url)
            return
        }
        guard let url = item.url else { return }
        let activityController = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        activityController.popoverPresentationController?.sourceView = sourceView
        activityController.popoverPresentationController?.sourceRect = sourceRect
        present(activityController, animated: true)
    }

    private func toggleFavorite(_ item: TabOverviewItem) {
        onToggleFavorite?(item.id)
    }

    private func makeContextMenu(
        for item: TabOverviewItem,
        sourceView: UIView,
        sourceRect: CGRect
    ) -> UIMenu {
        let copy = UIAction(
            title: "复制链接",
            image: UIImage(systemName: "doc.on.doc"),
            attributes: item.url == nil ? [.disabled] : []
        ) { [weak self] _ in
            self?.copyURL(for: item)
        }
        let share = UIAction(
            title: "分享",
            image: UIImage(systemName: "square.and.arrow.up"),
            attributes: item.url == nil ? [.disabled] : []
        ) { [weak self, weak sourceView] _ in
            guard let self, let sourceView else { return }
            self.share(
                item,
                sourceView: sourceView,
                sourceRect: sourceRect
            )
        }
        let favoriteState = favoriteActionStateProvider?(item.url)
            ?? FavoriteActionState(
                isEnabled: false,
                isFavorite: false
            )
        let favorite = UIAction(
            title: favoriteState.title,
            image: UIImage(systemName: favoriteState.systemImageName),
            attributes: favoriteState.isEnabled && onToggleFavorite != nil
                ? []
                : [.disabled]
        ) { [weak self] _ in
            self?.toggleFavorite(item)
        }

        let closeCurrent = UIAction(
            title: "关闭标签页",
            image: UIImage(systemName: "xmark"),
            attributes: [.destructive]
        ) { [weak self] _ in
            self?.close(itemID: item.id)
        }
        let sameModeCount = allItems.lazy.filter {
            $0.isPrivate == item.isPrivate
        }.count
        let closeOthers = UIAction(
            title: "关闭其他标签页",
            image: UIImage(systemName: "square.on.square.dashed"),
            attributes: sameModeCount > 1
                ? [.destructive]
                : [.disabled, .destructive]
        ) { [weak self] _ in
            self?.closeOtherTabs(keeping: item)
        }
        let normalCount = allItems.lazy.filter { !$0.isPrivate }.count
        let closeAllNormal = UIAction(
            title: "关闭全部普通标签页",
            image: UIImage(systemName: "rectangle.stack.badge.minus"),
            attributes: normalCount > 0
                ? [.destructive]
                : [.disabled, .destructive]
        ) { [weak self] _ in
            self?.closeAllNormalTabs()
        }

        return UIMenu(children: [
            UIMenu(options: .displayInline, children: [copy, share, favorite]),
            UIMenu(
                options: .displayInline,
                children: [closeCurrent, closeOthers, closeAllNormal]
            )
        ])
    }

    private func finish() {
        captureCurrentTransitionFrameIfNeeded()
        if let onDone {
            onDone()
        } else if presentingViewController != nil {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    @objc
    private func modeControlChanged() {
        guard let mode = TabOverviewMode(
            rawValue: modeControl.selectedSegmentIndex
        ) else {
            return
        }
        requestMode(
            mode,
            animated: !UIAccessibility.isReduceMotionEnabled,
            notifyDelegate: true
        )
    }
}

extension TabOverviewViewController: UIPageViewControllerDataSource {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard
            let page = viewController as? TabOverviewPageViewController,
            page.mode == .privateBrowsing
        else {
            return nil
        }
        return standardPage
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard
            let page = viewController as? TabOverviewPageViewController,
            page.mode == .standard
        else {
            return nil
        }
        return privatePage
    }
}

extension TabOverviewViewController: UIPageViewControllerDelegate {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        willTransitionTo pendingViewControllers: [UIViewController]
    ) {
        guard
            let pendingPage = pendingViewControllers.first
                as? TabOverviewPageViewController
        else {
            return
        }
        isPageTransitionInFlight = true
        saveScrollOffset(for: pagingState.selectedMode)
        pagingState.beginInteractiveTransition(to: pendingPage.mode)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        let expectedMode = pagingState.pendingInteractiveMode
        let transitionCompleted =
            completed && visiblePageMode == expectedMode
        let didChange = pagingState.finishInteractiveTransition(
            completed: transitionCompleted
        )
        isPageTransitionInFlight = false

        if !transitionCompleted {
            showSelectedPageWithoutAnimation()
        }
        restoreScrollOffset(for: pagingState.selectedMode)
        applyModeAppearance(animated: didChange)
        if didChange {
            onModeChanged?(pagingState.selectedMode.isPrivate)
        }
        drainQueuedTransitionIfNeeded()
    }
}
