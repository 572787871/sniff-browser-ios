import Foundation

enum WebPageThemeColorParser {
  static let minimumUsableAlpha = 0.85

  static func parse(_ rawValue: String?) -> WebPageThemeColor? {
    guard let rawValue else { return nil }
    let value = rawValue
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    guard !value.isEmpty, value != "transparent" else { return nil }

    if value.hasPrefix("#") {
      return parseHex(String(value.dropFirst()))
    }
    if value.hasPrefix("rgb("), value.hasSuffix(")") {
      return parseFunctionalColor(value, includesAlpha: false)
    }
    if value.hasPrefix("rgba("), value.hasSuffix(")") {
      return parseFunctionalColor(value, includesAlpha: true)
    }
    return nil
  }

  static func parseUsable(_ rawValue: String?) -> WebPageThemeColor? {
    guard let color = parse(rawValue),
          color.alpha >= minimumUsableAlpha
    else {
      return nil
    }
    return WebPageThemeColor(
      red: color.red,
      green: color.green,
      blue: color.blue
    )
  }

  static func firstUsable(
    in candidates: [String]
  ) -> WebPageThemeColor? {
    candidates.lazy.compactMap { parseUsable($0) }.first
  }

  private static func parseHex(_ value: String) -> WebPageThemeColor? {
    let expanded: String
    switch value.count {
    case 3, 4:
      expanded = value.map { "\($0)\($0)" }.joined()
    case 6, 8:
      expanded = value
    default:
      return nil
    }

    guard let integer = UInt64(expanded, radix: 16) else { return nil }
    let hasAlpha = expanded.count == 8
    let redShift = hasAlpha ? 24 : 16
    let greenShift = hasAlpha ? 16 : 8
    let blueShift = hasAlpha ? 8 : 0
    let alpha = hasAlpha ? Double(integer & 0xFF) / 255 : 1

    return WebPageThemeColor(
      red: Double((integer >> redShift) & 0xFF) / 255,
      green: Double((integer >> greenShift) & 0xFF) / 255,
      blue: Double((integer >> blueShift) & 0xFF) / 255,
      alpha: alpha
    )
  }

  private static func parseFunctionalColor(
    _ value: String,
    includesAlpha: Bool
  ) -> WebPageThemeColor? {
    guard let openingParenthesis = value.firstIndex(of: "("),
          let closingParenthesis = value.lastIndex(of: ")")
    else {
      return nil
    }

    let arguments = value[value.index(after: openingParenthesis)..<closingParenthesis]
      .split(separator: ",", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    let expectedCount = includesAlpha ? 4 : 3
    guard arguments.count == expectedCount,
          let red = parseRGBComponent(arguments[0]),
          let green = parseRGBComponent(arguments[1]),
          let blue = parseRGBComponent(arguments[2])
    else {
      return nil
    }

    let alpha: Double
    if includesAlpha {
      guard let parsedAlpha = parseAlphaComponent(arguments[3]) else {
        return nil
      }
      alpha = parsedAlpha
    } else {
      alpha = 1
    }

    return WebPageThemeColor(
      red: red,
      green: green,
      blue: blue,
      alpha: alpha
    )
  }

  private static func parseRGBComponent(_ value: String) -> Double? {
    if value.hasSuffix("%") {
      guard let percentage = Double(value.dropLast()),
            (0...100).contains(percentage)
      else {
        return nil
      }
      return percentage / 100
    }
    guard let component = Double(value),
          (0...255).contains(component)
    else {
      return nil
    }
    return component / 255
  }

  private static func parseAlphaComponent(_ value: String) -> Double? {
    if value.hasSuffix("%") {
      guard let percentage = Double(value.dropLast()),
            (0...100).contains(percentage)
      else {
        return nil
      }
      return percentage / 100
    }
    guard let component = Double(value),
          (0...1).contains(component)
    else {
      return nil
    }
    return component
  }
}
