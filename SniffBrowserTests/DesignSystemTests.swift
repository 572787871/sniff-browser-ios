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
}
