import UIKit
import XCTest
@testable import SniffBrowser

final class DesignSystemTests: XCTestCase {
  func testSemanticBackgroundResolvesForLightAndDarkAppearance() {
    let lightTraits = UITraitCollection(userInterfaceStyle: .light)
    let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

    let light = AppColors.background.resolvedColor(with: lightTraits)
    let dark = AppColors.background.resolvedColor(with: darkTraits)

    XCTAssertFalse(light.isEqual(dark))
    XCTAssertGreaterThan(relativeLuminance(of: light), relativeLuminance(of: dark))
  }

  func testElevatedSurfaceUsesDocumentedDynamicAlpha() {
    let light = AppColors.elevatedSurface.resolvedColor(
      with: UITraitCollection(userInterfaceStyle: .light)
    )
    let dark = AppColors.elevatedSurface.resolvedColor(
      with: UITraitCollection(userInterfaceStyle: .dark)
    )

    XCTAssertEqual(alpha(of: light), 0.92, accuracy: 0.01)
    XCTAssertEqual(alpha(of: dark), 0.88, accuracy: 0.01)
  }

  func testDefaultAccentUsesAppleBlueHue() {
    let accent = AppColors.accent.resolvedColor(
      with: UITraitCollection(userInterfaceStyle: .light)
    )
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0

    XCTAssertTrue(
      accent.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    )
    XCTAssertGreaterThan(blue, red)
    XCTAssertGreaterThanOrEqual(green, red)
    XCTAssertEqual(alpha, 1, accuracy: 0.01)
  }

  func testThemeTraitProducesDistinctGlobalAccentColors() {
    let colors = AppThemeColor.allCases.map { theme in
      let traits = UITraitCollection { mutableTraits in
        mutableTraits.userInterfaceStyle = .light
        mutableTraits.appThemeColor = theme
      }
      return AppColors.accent.resolvedColor(with: traits)
    }

    XCTAssertEqual(Set(colors.map(\.description)).count, AppThemeColor.allCases.count)
  }

  func testThemeAccentContentAdaptsForLightAndDarkSurfaces() {
    let lightOcean = UITraitCollection { mutableTraits in
      mutableTraits.userInterfaceStyle = .light
      mutableTraits.appThemeColor = .ocean
    }
    let darkOcean = UITraitCollection { mutableTraits in
      mutableTraits.userInterfaceStyle = .dark
      mutableTraits.appThemeColor = .ocean
    }

    let lightContent = AppColors.accentContent.resolvedColor(with: lightOcean)
    let darkContent = AppColors.accentContent.resolvedColor(with: darkOcean)

    XCTAssertGreaterThan(relativeLuminance(of: lightContent), relativeLuminance(of: darkContent))
  }

  @MainActor
  func testScanApertureBrandImageRendersAtRequestedSize() {
    let image = AppIconography.scanApertureImage(pointSize: 24)

    XCTAssertEqual(image.size.width, 24, accuracy: 0.01)
    XCTAssertEqual(image.size.height, 24, accuracy: 0.01)
    XCTAssertEqual(image.renderingMode, .alwaysTemplate)
  }

  @MainActor
  func testAppIconMarkImageRendersAtRequestedSize() {
    let image = AppIconography.appIconMarkImage(pointSize: 24)

    XCTAssertEqual(image.size.width, 24, accuracy: 0.01)
    XCTAssertEqual(image.size.height, 24, accuracy: 0.01)
    XCTAssertEqual(image.renderingMode, .alwaysTemplate)
  }

  @MainActor
  func testTabStackImageRendersAtRequestedSize() {
    let image = AppIconography.tabStackImage(pointSize: 22)

    XCTAssertEqual(image.size.width, 22, accuracy: 0.01)
    XCTAssertEqual(image.size.height, 22, accuracy: 0.01)
    XCTAssertEqual(image.renderingMode, .alwaysTemplate)
  }

  @MainActor
  func testBrowserToolbarKeepsCenterActionsSquare() throws {
    let toolbar = BrowserToolbar(frame: CGRect(x: 0, y: 0, width: 358, height: 58))
    toolbar.layoutIfNeeded()

    for identifier in ["browser.toolbar.sniffer", "browser.toolbar.tabs"] {
      let button = try identifiedView(identifier, in: toolbar)
      XCTAssertEqual(button.bounds.width, AppMetrics.minimumTapSize, accuracy: 0.5)
      XCTAssertEqual(button.bounds.height, AppMetrics.minimumTapSize, accuracy: 0.5)
    }
  }

  func testSpacingUsesFourPointBaseline() {
    let values = [
      AppSpacing.xxs,
      AppSpacing.xs,
      AppSpacing.sm,
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.xl,
      AppSpacing.xxl
    ]

    XCTAssertEqual(values, [4, 8, 12, 16, 20, 24, 32])
    XCTAssertTrue(values.allSatisfy { $0.truncatingRemainder(dividingBy: 4) == 0 })
  }

  func testRadiusScaleIsOrderedByComponentSize() {
    XCTAssertLessThan(AppRadius.small, AppRadius.control)
    XCTAssertLessThan(AppRadius.control, AppRadius.input)
    XCTAssertLessThan(AppRadius.input, AppRadius.card)
    XCTAssertLessThan(AppRadius.card, AppRadius.sheet)
  }

  func testGroupedListRowsRoundOnlyTheSectionOuterEdges() {
    let single = AppSwiftUIGroupedRowPosition(index: 0, count: 1)
    let first = AppSwiftUIGroupedRowPosition(index: 0, count: 3)
    let middle = AppSwiftUIGroupedRowPosition(index: 1, count: 3)
    let last = AppSwiftUIGroupedRowPosition(index: 2, count: 3)

    XCTAssertTrue(single.roundsTopCorners)
    XCTAssertTrue(single.roundsBottomCorners)
    XCTAssertTrue(first.roundsTopCorners)
    XCTAssertFalse(first.roundsBottomCorners)
    XCTAssertFalse(middle.roundsTopCorners)
    XCTAssertFalse(middle.roundsBottomCorners)
    XCTAssertFalse(last.roundsTopCorners)
    XCTAssertTrue(last.roundsBottomCorners)
  }

  @MainActor
  func testUIKitGroupedListsUseTheSharedPanelRadius() {
    let configuration = AppGroupedListAppearance.cellBackground()

    XCTAssertEqual(configuration.cornerRadius, AppRadius.panel)
    XCTAssertNotNil(configuration.backgroundColor)
  }

  func testMinimumTapTargetMeetsAccessibilityGuideline() {
    XCTAssertGreaterThanOrEqual(AppMetrics.minimumTapSize, 44)
    XCTAssertGreaterThanOrEqual(AppMetrics.addressBarHeight, 44)
  }

  func testTypographyScalesForAccessibilityContentSize() {
    let regularTraits = UITraitCollection(
      preferredContentSizeCategory: .large
    )
    let accessibilityTraits = UITraitCollection(
      preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge
    )
    let regular = UIFontMetrics.default.scaledFont(
      for: AppTypography.body,
      compatibleWith: regularTraits
    )
    let accessibility = UIFontMetrics.default.scaledFont(
      for: AppTypography.body,
      compatibleWith: accessibilityTraits
    )

    XCTAssertGreaterThan(accessibility.pointSize, regular.pointSize)
  }

  @MainActor
  func testPrivateNewTabKeepsRegularLayoutAndOnlyRestylesPrivacyElements() throws {
    let regular = NewTabView()
    let privateView = NewTabView()
    let regularHost = fixedSizeHost(containing: regular)
    let privateHost = fixedSizeHost(containing: privateView)
    regular.setPrivateMode(false)
    privateView.setPrivateMode(true)
    [regularHost, privateHost].forEach {
      $0.setNeedsLayout()
      $0.layoutIfNeeded()
    }

    let regularTitle = try identifiedView("newTab.title", in: regular)
    let privateTitle = try identifiedView("newTab.title", in: privateView)
    let regularLogo = try identifiedView("newTab.logo", in: regular)
    let privateLogo = try identifiedView("newTab.logo", in: privateView)
    let regularDescription = try identifiedView(
      "newTab.description",
      in: regular
    )
    let privateDescription = try identifiedView(
      "newTab.description",
      in: privateView
    )
    let regularDate = try identifiedView("newTab.date", in: regular)
    let privateDate = try identifiedView("newTab.date", in: privateView)
    let regularSearch = try identifiedView("newTab.searchSurface", in: regular)
    let privateSearch = try identifiedView(
      "newTab.searchSurface",
      in: privateView
    )

    XCTAssertEqual(regular.overrideUserInterfaceStyle, .unspecified)
    XCTAssertEqual(privateView.overrideUserInterfaceStyle, .unspecified)
    XCTAssertEqual(regularLogo.frame, privateLogo.frame)
    XCTAssertEqual(regularTitle.frame, privateTitle.frame)
    XCTAssertEqual(regularSearch.frame, privateSearch.frame)
    XCTAssertTrue(sameLightColor(regular.backgroundColor, privateView.backgroundColor))
    let regularLogoImage = regularLogo.subviews
      .compactMap { $0 as? UIImageView }
      .first?
      .image
    let privateLogoImage = privateLogo.subviews
      .compactMap { $0 as? UIImageView }
      .first?
      .image
    XCTAssertNotNil(regularLogoImage)
    XCTAssertNotNil(privateLogoImage)
    XCTAssertEqual(regularLogoImage, privateLogoImage)
    XCTAssertTrue(sameLightColor(
      (regularDate as? UILabel)?.textColor,
      (privateDate as? UILabel)?.textColor
    ))
    XCTAssertFalse(sameLightColor(
      (regularTitle as? UILabel)?.textColor,
      (privateTitle as? UILabel)?.textColor
    ))
    XCTAssertFalse(sameLightColor(
      (regularDescription as? UILabel)?.textColor,
      (privateDescription as? UILabel)?.textColor
    ))
    XCTAssertFalse(sameLightColor(
      regularSearch.backgroundColor,
      privateSearch.backgroundColor
    ))
  }

  @MainActor
  func testNewTabFavoritesUseTheSameFourColumnRhythmAsQuickActions() throws {
    let view = NewTabView()
    let favorites = [
      FavoriteItem(
        title: "每日大赛之真实的反差情侣合集",
        url: try XCTUnwrap(URL(string: "about:blank")),
        host: "example.test"
      ),
      FavoriteItem(
        title: "示例二",
        url: try XCTUnwrap(URL(string: "about:srcdoc")),
        host: "second.test"
      ),
    ]
    view.updateFavorites(favorites)
    let host = fixedSizeHost(containing: view)
    host.layoutIfNeeded()

    let title = try identifiedView("newTab.favoritesTitle", in: view)
    let stack = try XCTUnwrap(
      try identifiedView("newTab.favorites", in: view) as? UIStackView
    )
    let buttons = stack.arrangedSubviews.compactMap { $0 as? UIButton }

    XCTAssertFalse(title.isHidden)
    XCTAssertFalse(stack.isHidden)
    XCTAssertEqual(stack.arrangedSubviews.count, 4)
    XCTAssertEqual(buttons.count, 2)
    XCTAssertEqual(
      buttons.compactMap { $0.configuration?.title },
      ["每日大赛之真实的反差情侣合集", "示例二"]
    )
    let firstFavoriteButton = try XCTUnwrap(buttons.first)
    view.updateFavorites(favorites)
    let retainedFavoriteButton = try XCTUnwrap(
      stack.arrangedSubviews.first as? UIButton
    )
    XCTAssertTrue(firstFavoriteButton === retainedFavoriteButton)
    XCTAssertEqual(stack.distribution, .fillEqually)
    XCTAssertEqual(stack.bounds.height, 88, accuracy: 0.5)
    XCTAssertTrue(buttons.allSatisfy { $0.titleLabel?.numberOfLines == 2 })

    firstFavoriteButton.isHighlighted = true
    firstFavoriteButton.setNeedsUpdateConfiguration()
    firstFavoriteButton.updateConfiguration()
    firstFavoriteButton.layoutIfNeeded()
    XCTAssertEqual(firstFavoriteButton.titleLabel?.numberOfLines, 2)
    XCTAssertEqual(
      firstFavoriteButton.titleLabel?.lineBreakMode,
      .byTruncatingTail
    )
    XCTAssertGreaterThan(
      firstFavoriteButton.titleLabel?.bounds.height ?? 0,
      (firstFavoriteButton.titleLabel?.font.lineHeight ?? 0) * 1.5
    )
  }

  @MainActor
  func testTabOverviewPreviewFillsCardAndMetadataIconAlignsWithTitle() throws {
    let cell = TabOverviewCell(frame: CGRect(x: 0, y: 0, width: 173, height: 302))
    let image = UIGraphicsImageRenderer(
      size: CGSize(width: 390, height: 844)
    ).image { context in
      UIColor.systemBlue.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 390, height: 844))
    }
    cell.configure(with: TabOverviewItem(
      title: "新标签页",
      url: nil,
      thumbnail: image
    ))
    cell.setNeedsLayout()
    cell.layoutIfNeeded()

    let preview = try XCTUnwrap(
      try identifiedView("tabs.previewImage", in: cell) as? TabPageSnapshotView
    )
    let icon = try identifiedView("tabs.metadataIcon", in: cell)
    let title = try identifiedView("tabs.title", in: cell)
    let iconFrame = icon.convert(icon.bounds, to: cell)
    let titleFrame = title.convert(title.bounds, to: cell)

    XCTAssertEqual(preview.renderedImageFrame.minY, 0, accuracy: 0.001)
    XCTAssertGreaterThan(preview.renderedImageFrame.maxY, preview.bounds.maxY)
    XCTAssertEqual(
      preview.renderedImageFrame.width / image.size.width,
      preview.renderedImageFrame.height / image.size.height,
      accuracy: 0.000_1
    )
    XCTAssertEqual(preview.transform, .identity)
    XCTAssertTrue(CATransform3DIsIdentity(preview.layer.transform))
    XCTAssertGreaterThan(iconFrame.minY, titleFrame.minY)
    XCTAssertLessThan(iconFrame.minY, titleFrame.midY)
  }

  @MainActor
  func testTabOverviewCellClearsTransitionPresentationStateBeforeReuse() throws {
    let cell = TabOverviewCell(frame: CGRect(x: 0, y: 0, width: 173, height: 302))
    let image = UIGraphicsImageRenderer(
      size: CGSize(width: 390, height: 844)
    ).image { context in
      UIColor.systemBlue.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 390, height: 844))
    }
    cell.configure(with: TabOverviewItem(
      title: "示例网页",
      url: URL(string: "https://example.com"),
      thumbnail: image
    ))
    cell.setNeedsLayout()
    cell.layoutIfNeeded()

    let preview = try XCTUnwrap(
      try identifiedView("tabs.previewImage", in: cell) as? TabPageSnapshotView
    )
    cell.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
    cell.layer.transform = CATransform3DMakeScale(0.5, 0.5, 1)
    cell.contentView.transform = CGAffineTransform(translationX: 12, y: 8)
    preview.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
    preview.layer.transform = CATransform3DMakeScale(0.4, 0.4, 1)
    cell.setTransitionPreviewHidden(true)

    XCTAssertEqual(cell.transform, .identity)
    XCTAssertTrue(CATransform3DIsIdentity(cell.layer.transform))
    XCTAssertEqual(cell.contentView.transform, .identity)
    XCTAssertEqual(preview.transform, .identity)
    XCTAssertTrue(CATransform3DIsIdentity(preview.layer.transform))
    XCTAssertEqual(cell.alpha, 1)
    XCTAssertEqual(cell.contentView.alpha, 1)
    XCTAssertEqual(preview.alpha, 1)

    cell.prepareForReuse()

    XCTAssertEqual(cell.transform, .identity)
    XCTAssertTrue(CATransform3DIsIdentity(cell.layer.transform))
    XCTAssertEqual(cell.contentView.transform, .identity)
    XCTAssertEqual(cell.alpha, 1)
    XCTAssertEqual(cell.contentView.alpha, 1)
  }

  @MainActor
  func testTransitionSnapshotResizeKeepsIdentityAndImageAspect() {
    let image = UIGraphicsImageRenderer(
      size: CGSize(width: 390, height: 844)
    ).image { context in
      UIColor.systemBlue.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 390, height: 844))
    }
    let snapshot = TabPageSnapshotView(image: image)
    snapshot.translatesAutoresizingMaskIntoConstraints = true
    snapshot.bounds = CGRect(
      origin: .zero,
      size: CGSize(width: 170, height: 260)
    )
    snapshot.center = CGPoint(x: 85, y: 130)
    snapshot.layoutIfNeeded()

    snapshot.bounds = CGRect(
      origin: .zero,
      size: CGSize(width: 390, height: 620)
    )
    snapshot.center = CGPoint(x: 195, y: 310)
    snapshot.layoutIfNeeded()

    XCTAssertEqual(snapshot.transform, .identity)
    XCTAssertTrue(CATransform3DIsIdentity(snapshot.layer.transform))
    XCTAssertTrue(snapshot.constraints.isEmpty)
    XCTAssertEqual(
      snapshot.renderedImageFrame.width / image.size.width,
      snapshot.renderedImageFrame.height / image.size.height,
      accuracy: 0.000_1
    )
  }

  @MainActor
  func testTabTransitionUsesTheStoredPreviewImageInBothDirections() throws {
    let image = UIGraphicsImageRenderer(
      size: CGSize(width: 390, height: 844)
    ).image { context in
      UIColor.systemGreen.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 390, height: 844))
    }
    let itemID = UUID()
    let controller = TabOverviewViewController(items: [
      TabOverviewItem(
        id: itemID,
        title: "示例网页",
        url: URL(string: "https://example.com"),
        thumbnail: image,
        isSelected: true
      )
    ])

    XCTAssertTrue(controller.transitionImage(for: itemID) === image)
    XCTAssertEqual(controller.transitionItemID, itemID)
    controller.disableNextSpatialTransition()
    XCTAssertNil(controller.transitionItemID)
  }

  @MainActor
  func testTabOverviewSpatialTransitionAnimatesAuxiliaryLayersSeparately() throws {
    let controller = TabOverviewViewController(items: [
      TabOverviewItem(title: "新标签页", url: nil, isSelected: true)
    ])
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    controller.view.layoutIfNeeded()
    let background = try identifiedView(
      "tabs.transitionBackground",
      in: controller.view
    )
    let page = try identifiedView("tabs.pageContainer", in: controller.view)
    let bottomBar = try identifiedView("tabs.bottomBar", in: controller.view)

    controller.prepareSpatialTransition(enteringOverview: true)
    XCTAssertEqual(background.alpha, 0)
    XCTAssertEqual(page.alpha, 0)
    XCTAssertEqual(bottomBar.alpha, 0)
    XCTAssertGreaterThan(bottomBar.transform.ty, 0)

    controller.animateSpatialTransition(enteringOverview: true)
    XCTAssertEqual(background.alpha, 1)
    XCTAssertEqual(page.alpha, 1)
    XCTAssertEqual(bottomBar.alpha, 1)
    XCTAssertEqual(bottomBar.transform, .identity)

    controller.prepareSpatialTransition(enteringOverview: false)
    controller.animateSpatialTransition(enteringOverview: false)
    XCTAssertEqual(background.alpha, 0)
    XCTAssertEqual(page.alpha, 0)
    XCTAssertEqual(bottomBar.alpha, 0)
    XCTAssertGreaterThan(bottomBar.transform.ty, 0)

    controller.completeSpatialTransition()
    XCTAssertEqual(page.alpha, 1)
    XCTAssertEqual(bottomBar.alpha, 1)
    XCTAssertEqual(bottomBar.transform, .identity)
  }

  @MainActor
  func testBrowserTransitionCoverMatchesTheAnimatedVisibleContentFrame() throws {
    let controller = BrowserViewController(
      viewModel: BrowserViewModel(),
      tabManager: BrowserTabManager(restoresSession: false),
      favoriteService: .shared,
      historyService: .shared,
      contentBlockerService: .shared,
      resourceStore: TabResourceStore(),
      downloadCenter: .shared
    )
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    controller.view.setNeedsLayout()
    controller.view.layoutIfNeeded()
    let image = UIGraphicsImageRenderer(
      size: CGSize(width: 390, height: 844)
    ).image { _ in }

    controller.installTabTransitionCover(image: image)
    let cover = try XCTUnwrap(controller.tabTransitionCoverView)
    let expectedFrame = controller.tabTransitionContentFrame(
      in: controller.contentView
    )
    let fullSnapshotFrame = controller.tabTransitionSnapshotFullFrame(
      in: controller.contentView
    )
    let expectedImageFrame = TabOverviewTransitionGeometry.clippedPageFrame(
      contentSize: image.size,
      fullContainerFrame: fullSnapshotFrame,
      clippedTo: expectedFrame
    )

    XCTAssertTrue(cover.superview === controller.contentView)
    XCTAssertEqual(cover.frame, expectedFrame)
    XCTAssertEqual(cover.renderedImageFrame, expectedImageFrame)
    controller.removeTabTransitionCover(animated: false)
    XCTAssertNil(controller.tabTransitionCoverView)
  }

  @MainActor
  func testBrowserTransitionSnapshotFreezesCurrentContentCoordinates() throws {
    let controller = BrowserViewController(
      viewModel: BrowserViewModel(),
      tabManager: BrowserTabManager(restoresSession: false),
      favoriteService: .shared,
      historyService: .shared,
      contentBlockerService: .shared,
      resourceStore: TabResourceStore(),
      downloadCenter: .shared
    )
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    controller.view.layoutIfNeeded()
    let fallback = UIGraphicsImageRenderer(
      size: CGSize(width: 390, height: 844)
    ).image { _ in }

    let snapshot = try XCTUnwrap(controller.makeTabTransitionSnapshot(
      in: controller.view,
      fallbackImage: fallback
    ))
    let frames = try XCTUnwrap(snapshot.frames(in: controller.view))

    XCTAssertEqual(
      frames.full,
      controller.tabTransitionFullContentFrame(in: controller.view)
    )
    XCTAssertEqual(
      frames.visible,
      controller.tabTransitionContentFrame(in: controller.view)
    )
    XCTAssertGreaterThan(snapshot.contentSize.width, 0)
    XCTAssertGreaterThan(snapshot.contentSize.height, 0)
    XCTAssertEqual(
      snapshot.contentView.accessibilityIdentifier,
      "browser.tabTransitionSnapshot"
    )
  }

  @MainActor
  func testReattachingSelectedWebViewDoesNotAccumulateConstraints() throws {
    let controller = BrowserViewController(
      viewModel: BrowserViewModel(),
      tabManager: BrowserTabManager(restoresSession: false),
      favoriteService: .shared,
      historyService: .shared,
      contentBlockerService: .shared,
      resourceStore: TabResourceStore(),
      downloadCenter: .shared
    )
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)

    let webView = try XCTUnwrap(controller.activeWebView)
    for _ in 0..<10 {
      controller.attachSelectedTab()
    }
    controller.view.setNeedsLayout()
    controller.view.layoutIfNeeded()

    let constraints = controller.contentView.constraints.filter { constraint in
      (constraint.firstItem as AnyObject?) === webView
        || (constraint.secondItem as AnyObject?) === webView
    }
    XCTAssertEqual(constraints.count, 4)
    XCTAssertTrue(webView.superview === controller.contentView)
  }

  @MainActor
  func testTabTransitionNormalizationRestoresTheRealBrowserLayout() throws {
    let controller = BrowserViewController(
      viewModel: BrowserViewModel(),
      tabManager: BrowserTabManager(restoresSession: false),
      favoriteService: .shared,
      historyService: .shared,
      contentBlockerService: .shared,
      resourceStore: TabResourceStore(),
      downloadCenter: .shared
    )
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    window.layoutIfNeeded()
    defer {
      window.isHidden = true
      window.rootViewController = nil
    }

    let webView = try XCTUnwrap(controller.activeWebView)
    controller.view.transform = CGAffineTransform(scaleX: 0.42, y: 0.42)
    controller.contentView.transform = CGAffineTransform(
      translationX: -24,
      y: 18
    )
    webView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
    webView.scrollView.transform = CGAffineTransform(translationX: 12, y: 0)
    controller.addressBar.setCompact(true, animated: false)
    controller.toolbar.setCollapsed(true, animated: false)

    controller.normalizeTabTransitionBrowserState()

    XCTAssertEqual(controller.view.transform, .identity)
    XCTAssertTrue(CATransform3DIsIdentity(controller.view.layer.transform))
    XCTAssertEqual(controller.contentView.transform, .identity)
    XCTAssertTrue(
      CATransform3DIsIdentity(controller.contentView.layer.transform)
    )
    XCTAssertEqual(webView.transform, .identity)
    XCTAssertTrue(CATransform3DIsIdentity(webView.layer.transform))
    XCTAssertEqual(webView.scrollView.transform, .identity)
    XCTAssertEqual(
      webView.frame.width,
      controller.contentView.bounds.width,
      accuracy: 0.5
    )
    XCTAssertEqual(
      webView.frame.height,
      controller.contentView.bounds.height
        - webView.frame.minY,
      accuracy: 0.5
    )
  }

  @MainActor
  func testNativeNewTabTransitionUsesAStableRenderedImage() throws {
    let controller = BrowserViewController(
      viewModel: BrowserViewModel(),
      tabManager: BrowserTabManager(restoresSession: false),
      favoriteService: .shared,
      historyService: .shared,
      contentBlockerService: .shared,
      resourceStore: TabResourceStore(),
      downloadCenter: .shared
    )
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    window.setNeedsLayout()
    window.layoutIfNeeded()
    defer {
      window.isHidden = true
      window.rootViewController = nil
    }

    let tabID = try XCTUnwrap(controller.activeTab?.id)
    let fallback = UIGraphicsImageRenderer(
      size: CGSize(width: 390, height: 844)
    ).image { _ in }
    let snapshot = try XCTUnwrap(controller.makeTabTransitionSnapshot(
      in: controller.view,
      fallbackImage: fallback
    ))
    let image = try XCTUnwrap(controller.makeTabTransitionImage(
      for: tabID,
      fallbackImage: fallback
    ))

    XCTAssertTrue(snapshot.contentView is TabPageSnapshotView)
    XCTAssertGreaterThan(image.size.width, 0)
    XCTAssertGreaterThan(image.size.height, 0)
  }

  @MainActor
  func testEveryNativeNewTabReceivesAReusableOverviewSnapshot() throws {
    let manager = BrowserTabManager(restoresSession: false)
    let controller = BrowserViewController(
      viewModel: BrowserViewModel(),
      tabManager: manager,
      favoriteService: .shared,
      historyService: .shared,
      contentBlockerService: .shared,
      resourceStore: TabResourceStore(),
      downloadCenter: .shared
    )
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    controller.view.setNeedsLayout()
    controller.view.layoutIfNeeded()
    XCTAssertTrue(controller.openNewTab())

    controller.refreshNewTabSnapshotsForOverview()

    XCTAssertEqual(manager.tabs.count, 2)
    XCTAssertTrue(manager.tabs.allSatisfy { $0.snapshot != nil })
  }

  @MainActor
  func testBrowserConfigurationAllowsScriptedPlaybackContinuation() {
    let configurations = [
      BrowserConfiguration.makeWebViewConfiguration(isPrivate: false),
      BrowserConfiguration.makeWebViewConfiguration(isPrivate: true),
    ]

    for configuration in configurations {
      XCTAssertTrue(configuration.allowsInlineMediaPlayback)
      XCTAssertTrue(
        configuration.mediaTypesRequiringUserActionForPlayback.isEmpty
      )
    }
  }

  @MainActor
  func testPrivateBrowserSuggestionsUseTheRegularCanvasAppearance() throws {
    let controller = BrowserViewController(
      viewModel: BrowserViewModel(),
      tabManager: BrowserTabManager(restoresSession: false),
      favoriteService: .shared,
      historyService: .shared,
      contentBlockerService: .shared,
      resourceStore: TabResourceStore(),
      downloadCenter: .shared
    )
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    XCTAssertTrue(controller.openNewTab(isPrivate: true))
    controller.addressBarDidBeginEditing(controller.addressBar)
    controller.view.setNeedsLayout()
    controller.view.layoutIfNeeded()

    let history = try identifiedView(
      "browser.searchHistory",
      in: controller.view
    )
    let favorites = try identifiedView(
      "browser.searchFavorites",
      in: controller.view
    )

    XCTAssertEqual(history.overrideUserInterfaceStyle, .unspecified)
    XCTAssertEqual(favorites.overrideUserInterfaceStyle, .unspecified)
    XCTAssertEqual(controller.toolbar.overrideUserInterfaceStyle, .unspecified)
    XCTAssertEqual(controller.addressBar.overrideUserInterfaceStyle, .dark)
    XCTAssertEqual(
      favorites.frame.minY,
      controller.addressBar.frame.maxY,
      accuracy: 0.5
    )
    XCTAssertEqual(history.frame.minY, favorites.frame.maxY, accuracy: 0.5)
    XCTAssertTrue(sameLightColor(
      controller.view.backgroundColor,
      AppColors.background
    ))
  }

  private func alpha(of color: UIColor) -> CGFloat {
    var alpha: CGFloat = 0
    XCTAssertTrue(color.getRed(nil, green: nil, blue: nil, alpha: &alpha))
    return alpha
  }

  private func relativeLuminance(of color: UIColor) -> CGFloat {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    XCTAssertTrue(
      color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    )
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue
  }

  private func identifiedView(
    _ identifier: String,
    in view: UIView
  ) throws -> UIView {
    if view.accessibilityIdentifier == identifier {
      return view
    }
    for subview in view.subviews {
      if let match = try? identifiedView(identifier, in: subview) {
        return match
      }
    }
    throw NSError(
      domain: "DesignSystemTests",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Missing view: \(identifier)"]
    )
  }

  @MainActor
  private func fixedSizeHost(containing view: UIView) -> UIView {
    let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    view.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(view)
    NSLayoutConstraint.activate([
      view.topAnchor.constraint(equalTo: host.topAnchor),
      view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
      view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
      view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
    ])
    return host
  }

  private func sameLightColor(_ lhs: UIColor?, _ rhs: UIColor?) -> Bool {
    guard let lhs, let rhs else { return false }
    let traits = UITraitCollection(userInterfaceStyle: .light)
    return lhs.resolvedColor(with: traits).isEqual(
      rhs.resolvedColor(with: traits)
    )
  }
}
