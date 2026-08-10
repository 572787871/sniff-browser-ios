import UIKit

extension Notification.Name {
  static let newTabBackgroundDidChange = Notification.Name(
    "com.sniffbrowser.newTabBackgroundDidChange"
  )
}

/// 新标签页背景图的本地存储。仅保存用户通过系统照片选择器明确选中的图片。
@MainActor
final class NewTabBackgroundStore {
  static let shared = NewTabBackgroundStore()

  enum StoreError: Error {
    case invalidImage
    case encodingFailed
  }

  private let fileManager: FileManager
  private let directoryURL: URL
  private let fileURL: URL
  private var cachedImage: UIImage?

  init(
    fileManager: FileManager = .default,
    directoryURL: URL? = nil
  ) {
    self.fileManager = fileManager
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
  }

  var hasImage: Bool {
    cachedImage != nil || fileManager.fileExists(atPath: fileURL.path)
  }

  func image() -> UIImage? {
    if let cachedImage {
      return cachedImage
    }
    guard let image = UIImage(contentsOfFile: fileURL.path) else { return nil }
    cachedImage = image
    return image
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
    cachedImage = preparedImage
    NotificationCenter.default.post(name: .newTabBackgroundDidChange, object: self)
  }

  func remove() throws {
    cachedImage = nil
    guard fileManager.fileExists(atPath: fileURL.path) else { return }
    try fileManager.removeItem(at: fileURL)
    NotificationCenter.default.post(name: .newTabBackgroundDidChange, object: self)
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
}
