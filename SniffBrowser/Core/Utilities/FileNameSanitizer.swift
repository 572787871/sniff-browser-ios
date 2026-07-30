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
    let limited = String(collapsed.prefix(max(1, maximumLength)))
      .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
    return limited.isEmpty ? "未命名文件" : limited
  }
}
