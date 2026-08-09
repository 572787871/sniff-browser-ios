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
    [regular, privateView].forEach {
      $0.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    }
    regular.setPrivateMode(false)
    privateView.setPrivateMode(true)
    [regular, privateView].forEach {
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
    XCTAssertTrue(sameLightColor(
      regularLogo.backgroundColor,
      privateLogo.backgroundColor
    ))
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

  private func sameLightColor(_ lhs: UIColor?, _ rhs: UIColor?) -> Bool {
    guard let lhs, let rhs else { return false }
    let traits = UITraitCollection(userInterfaceStyle: .light)
    return lhs.resolvedColor(with: traits).isEqual(
      rhs.resolvedColor(with: traits)
    )
  }
}
