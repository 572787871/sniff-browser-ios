import Foundation

enum FileNameSanitizer {
  static func sanitize(_ value: String, maximumLength: Int = 120) -> String {
    let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
      .union(.controlCharacters)
      .union(.newlines)
    let pieces = value.components(separatedBy: invalid)
    let joined = pieces.joined(separator: "_")
      .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
    let collapsed = joined.replacingOccurrences(
      of: "_{2,}",
      with: "_",
      options: .regularExpression
    )
    let lengthLimit = max(1, maximumLength)
    let trimmed = collapsed.trimmingCharacters(
      in: CharacterSet(charactersIn: " .")
    )
    guard trimmed.count > lengthLimit else {
      return trimmed.isEmpty ? "未命名文件" : trimmed
    }

    let path = trimmed as NSString
    let pathExtension = path.pathExtension
    let extensionLength = pathExtension.count + 1
    let limited: String
    if !pathExtension.isEmpty, extensionLength < lengthLimit {
      let baseLimit = lengthLimit - extensionLength
      let base = path.deletingPathExtension.trimmingCharacters(
        in: CharacterSet(charactersIn: " .")
      )
      let limitedBase = String(base.prefix(baseLimit)).trimmingCharacters(
        in: CharacterSet(charactersIn: " .")
      )
      limited = limitedBase.isEmpty
        ? String(trimmed.prefix(lengthLimit))
        : "\(limitedBase).\(pathExtension)"
    } else {
      limited = String(trimmed.prefix(lengthLimit))
        .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
    }
    return limited.isEmpty ? "未命名文件" : limited
  }
}
