import UIKit

extension Notification.Name {
  static let newTabBackgroundDidChange = Notification.Name(
    "com.sniffbrowser.newTabBackgroundDidChange"
  )
}

enum NewTabBackgroundPreset: String, CaseIterable, Hashable, Sendable {
  case aurora
  case ocean
  case dawn
  case mist

  var title: String {
    switch self {
    case .aurora: return "夜间极光"
    case .ocean: return "深海微光"
    case .dawn: return "日出云霞"
      case .mist: return "远山晨雾"
    }
  }
}

enum NewTabBackgroundSelection: Equatable, Hashable, Sendable {
  case none
  case preset(NewTabBackgroundPreset)
  case custom

  var title: String {
    switch self {
    case .none: return "默认纸张"
    case let .preset(preset): return preset.title
    case .custom: return "自定义照片"
    }
  }
}

/// 新标签页背景的本地存储与内置背景渲染器。
/// 自定义照片仅保存在应用沙盒；内置背景由本地矢量图形即时生成。
@MainActor
final class NewTabBackgroundStore {
  static let shared = NewTabBackgroundStore()

  enum StoreError: Error {
    case invalidImage
    case encodingFailed
  }

  private static let selectionDefaultsKey = "newTab.background.selection.v2"

  private let fileManager: FileManager
  private let directoryURL: URL
  private let fileURL: URL
  private let userDefaults: UserDefaults
  private var cachedCustomImage: UIImage?
  private var cachedPresetImage: (preset: NewTabBackgroundPreset, image: UIImage)?

  private(set) var selection: NewTabBackgroundSelection

  init(
    fileManager: FileManager = .default,
    directoryURL: URL? = nil,
    userDefaults: UserDefaults = .standard
  ) {
    self.fileManager = fileManager
    self.userDefaults = userDefaults
    let resolvedDirectory: URL
    if let directoryURL {
      resolvedDirectory = directoryURL
    } else {
      let applicationSupport = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first ?? fileManager.temporaryDirectory
      resolvedDirectory = applicationSupport.appendingPathComponent(
        "NewTabAppearance",
        isDirectory: true
      )
    }
    self.directoryURL = resolvedDirectory
    fileURL = resolvedDirectory.appendingPathComponent("background.jpg")

    let hasCustomFile = fileManager.fileExists(atPath: fileURL.path)
    selection = Self.decodeSelection(
      userDefaults.string(forKey: Self.selectionDefaultsKey),
      hasCustomFile: hasCustomFile
    )
  }

  var hasImage: Bool {
    switch selection {
    case .none: return false
    case .preset: return true
    case .custom: return hasCustomImage
    }
  }

  var hasCustomImage: Bool {
    cachedCustomImage != nil || fileManager.fileExists(atPath: fileURL.path)
  }

  func image() -> UIImage? {
    switch selection {
    case .none:
      return nil
    case .custom:
      return customImage()
    case let .preset(preset):
      if cachedPresetImage?.preset == preset {
        return cachedPresetImage?.image
      }
      let image = Self.renderPreset(
        preset,
        size: CGSize(width: 720, height: 1_560)
      )
      cachedPresetImage = (preset, image)
      return image
    }
  }

  func customImage() -> UIImage? {
    if let cachedCustomImage {
      return cachedCustomImage
    }
    guard let image = UIImage(contentsOfFile: fileURL.path) else { return nil }
    cachedCustomImage = image
    return image
  }

  func previewImage(
    for selection: NewTabBackgroundSelection,
    size: CGSize
  ) -> UIImage? {
    switch selection {
    case .none:
      return nil
    case .custom:
      return customImage()
    case let .preset(preset):
      return Self.renderPreset(preset, size: size)
    }
  }

  func selectDefault() {
    updateSelection(.none)
  }

  func selectPreset(_ preset: NewTabBackgroundPreset) {
    updateSelection(.preset(preset))
  }

  @discardableResult
  func selectCustomImage() -> Bool {
    guard hasCustomImage else { return false }
    updateSelection(.custom)
    return true
  }

  func save(_ image: UIImage) throws {
    guard image.size.width > 0, image.size.height > 0 else {
      throw StoreError.invalidImage
    }
    let preparedImage = resizedImage(image, maximumDimension: 2_400)
    guard let data = preparedImage.jpegData(compressionQuality: 0.86) else {
      throw StoreError.encodingFailed
    }
    try fileManager.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    try data.write(to: fileURL, options: .atomic)
    cachedCustomImage = preparedImage
    persistSelection(.custom)
    NotificationCenter.default.post(name: .newTabBackgroundDidChange, object: self)
  }

  func remove() throws {
    let wasSelected = selection == .custom
    let hadImage = hasCustomImage
    cachedCustomImage = nil
    if fileManager.fileExists(atPath: fileURL.path) {
      try fileManager.removeItem(at: fileURL)
    }
    if wasSelected {
      persistSelection(.none)
    }
    if hadImage || wasSelected {
      NotificationCenter.default.post(
        name: .newTabBackgroundDidChange,
        object: self
      )
    }
  }

  private func updateSelection(_ selection: NewTabBackgroundSelection) {
    guard self.selection != selection else { return }
    persistSelection(selection)
    NotificationCenter.default.post(name: .newTabBackgroundDidChange, object: self)
  }

  private func persistSelection(_ selection: NewTabBackgroundSelection) {
    self.selection = selection
    cachedPresetImage = nil
    userDefaults.set(Self.encodeSelection(selection), forKey: Self.selectionDefaultsKey)
  }

  private static func encodeSelection(
    _ selection: NewTabBackgroundSelection
  ) -> String {
    switch selection {
    case .none: return "none"
    case .custom: return "custom"
    case let .preset(preset): return "preset.\(preset.rawValue)"
    }
  }

  private static func decodeSelection(
    _ rawValue: String?,
    hasCustomFile: Bool
  ) -> NewTabBackgroundSelection {
    guard let rawValue else {
      // 兼容旧版本：已有背景文件时继续使用，不让升级清空用户选择。
      return hasCustomFile ? .custom : .none
    }
    if rawValue == "custom" {
      return hasCustomFile ? .custom : .none
    }
    if rawValue == "none" {
      return .none
    }
    let presetValue = rawValue.replacingOccurrences(of: "preset.", with: "")
    guard rawValue.hasPrefix("preset."),
          let preset = NewTabBackgroundPreset(rawValue: presetValue)
    else {
      return .none
    }
    return .preset(preset)
  }

  private func resizedImage(
    _ image: UIImage,
    maximumDimension: CGFloat
  ) -> UIImage {
    let largestDimension = max(image.size.width, image.size.height)
    let scale = min(1, maximumDimension / largestDimension)
    let targetSize = CGSize(
      width: max(1, (image.size.width * scale).rounded()),
      height: max(1, (image.size.height * scale).rounded())
    )
    let format = UIGraphicsImageRendererFormat.preferred()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
      UIColor.black.setFill()
      context.fill(CGRect(origin: .zero, size: targetSize))
      image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
  }

  private static func renderPreset(
    _ preset: NewTabBackgroundPreset,
    size: CGSize
  ) -> UIImage {
    let safeSize = CGSize(width: max(1, size.width), height: max(1, size.height))
    let format = UIGraphicsImageRendererFormat.preferred()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: safeSize, format: format).image { context in
      let cgContext = context.cgContext
      let palette = colors(for: preset)
      let colors = palette.map(\.cgColor) as CFArray
      if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors,
        locations: [0, 0.52, 1]
      ) {
        cgContext.drawLinearGradient(
          gradient,
          start: CGPoint(x: safeSize.width * 0.12, y: 0),
          end: CGPoint(x: safeSize.width * 0.88, y: safeSize.height),
          options: []
        )
      }
      drawAtmosphere(for: preset, in: cgContext, size: safeSize)
    }
  }

  private static func colors(for preset: NewTabBackgroundPreset) -> [UIColor] {
    switch preset {
    case .aurora:
      return [
        UIColor(red: 0.020, green: 0.055, blue: 0.120, alpha: 1),
        UIColor(red: 0.035, green: 0.265, blue: 0.290, alpha: 1),
        UIColor(red: 0.505, green: 0.285, blue: 0.390, alpha: 1),
      ]
    case .ocean:
      return [
        UIColor(red: 0.020, green: 0.100, blue: 0.180, alpha: 1),
        UIColor(red: 0.025, green: 0.345, blue: 0.400, alpha: 1),
        UIColor(red: 0.340, green: 0.655, blue: 0.640, alpha: 1),
      ]
    case .dawn:
      return [
        UIColor(red: 0.155, green: 0.205, blue: 0.340, alpha: 1),
        UIColor(red: 0.690, green: 0.390, blue: 0.420, alpha: 1),
        UIColor(red: 0.945, green: 0.675, blue: 0.470, alpha: 1),
      ]
    case .mist:
      return [
        UIColor(red: 0.155, green: 0.230, blue: 0.225, alpha: 1),
        UIColor(red: 0.330, green: 0.445, blue: 0.405, alpha: 1),
        UIColor(red: 0.680, green: 0.665, blue: 0.555, alpha: 1),
      ]
    }
  }

  private static func drawAtmosphere(
    for preset: NewTabBackgroundPreset,
    in context: CGContext,
    size: CGSize
  ) {
    context.saveGState()
    context.setBlendMode(.screen)

    let glowColor: UIColor
    switch preset {
    case .aurora: glowColor = UIColor(red: 0.40, green: 0.95, blue: 0.74, alpha: 0.18)
    case .ocean: glowColor = UIColor(red: 0.68, green: 0.94, blue: 0.95, alpha: 0.16)
    case .dawn: glowColor = UIColor(red: 1.00, green: 0.82, blue: 0.58, alpha: 0.22)
    case .mist: glowColor = UIColor(red: 0.88, green: 0.88, blue: 0.72, alpha: 0.15)
    }
    context.setFillColor(glowColor.cgColor)
    context.fillEllipse(in: CGRect(
      x: -size.width * 0.30,
      y: size.height * 0.08,
      width: size.width * 1.10,
      height: size.width * 0.78
    ))
    context.fillEllipse(in: CGRect(
      x: size.width * 0.46,
      y: size.height * 0.46,
      width: size.width * 0.78,
      height: size.width * 0.78
    ))

    context.setStrokeColor(UIColor.white.withAlphaComponent(0.13).cgColor)
    context.setLineWidth(max(1, size.width * 0.008))
    for index in 0..<4 {
      let y = size.height * (0.62 + CGFloat(index) * 0.07)
      let path = UIBezierPath()
      path.move(to: CGPoint(x: -size.width * 0.08, y: y))
      path.addCurve(
        to: CGPoint(x: size.width * 1.08, y: y + size.height * 0.025),
        controlPoint1: CGPoint(x: size.width * 0.22, y: y - size.height * 0.055),
        controlPoint2: CGPoint(x: size.width * 0.72, y: y + size.height * 0.070)
      )
      context.addPath(path.cgPath)
      context.strokePath()
    }
    context.restoreGState()
  }
}
