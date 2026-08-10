import Foundation
import UIKit

struct WebPageThemeColor: Equatable, Sendable {
  let red: Double
  let green: Double
  let blue: Double
  let alpha: Double

  init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
    self.red = min(max(red, 0), 1)
    self.green = min(max(green, 0), 1)
    self.blue = min(max(blue, 0), 1)
    self.alpha = min(max(alpha, 0), 1)
  }

  @MainActor
  var uiColor: UIColor {
    UIColor(
      red: CGFloat(red),
      green: CGFloat(green),
      blue: CGFloat(blue),
      alpha: CGFloat(alpha)
    )
  }
}

enum BrowserChromeForegroundStyle: Equatable, Sendable {
  case light
  case dark

  @MainActor
  var color: UIColor {
    switch self {
    case .light: return .white
    case .dark: return .black
    }
  }

  @MainActor
  var statusBarStyle: UIStatusBarStyle {
    switch self {
    case .light: return .lightContent
    case .dark: return .darkContent
    }
  }
}

enum ContrastColorResolver {
  static func foregroundStyle(
    for color: WebPageThemeColor
  ) -> BrowserChromeForegroundStyle {
    let luminance = relativeLuminance(of: color)
    let whiteContrast = contrastRatio(luminance, 1)
    let blackContrast = contrastRatio(luminance, 0)
    return whiteContrast >= blackContrast ? .light : .dark
  }

  static func relativeLuminance(of color: WebPageThemeColor) -> Double {
    func linearize(_ component: Double) -> Double {
      component <= 0.04045
        ? component / 12.92
        : pow((component + 0.055) / 1.055, 2.4)
    }

    return 0.2126 * linearize(color.red)
      + 0.7152 * linearize(color.green)
      + 0.0722 * linearize(color.blue)
  }

  private static func contrastRatio(
    _ firstLuminance: Double,
    _ secondLuminance: Double
  ) -> Double {
    let lighter = max(firstLuminance, secondLuminance)
    let darker = min(firstLuminance, secondLuminance)
    return (lighter + 0.05) / (darker + 0.05)
  }
}

/// Keeps browser chrome coherent with the selected app appearance while still
/// allowing dark websites to extend their color into the surrounding chrome.
enum BrowserChromeThemeResolver {
  static func effectivePageTheme(
    _ color: WebPageThemeColor?,
    interfaceStyle: UIUserInterfaceStyle
  ) -> WebPageThemeColor? {
    guard let color else { return nil }
    guard interfaceStyle == .dark else { return color }

    // A light page theme inside dark appearance would turn only the address
    // bar light while the surrounding inset remains dark. Keep all chrome dark
    // in that case; genuinely dark page themes are still adopted.
    return ContrastColorResolver.foregroundStyle(for: color) == .light
      ? color
      : nil
  }
}
