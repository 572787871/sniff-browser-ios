import Foundation
import OSLog

struct AppLogger {
  enum Category: String {
    case application
    case browser
    case navigation
    case sniffer
    case download
    case files
    case authentication
    case privacy
  }

  private let logger: Logger

  init(_ category: Category) {
    logger = Logger(
      subsystem: Bundle.main.bundleIdentifier ?? "com.example.SniffBrowser",
      category: category.rawValue
    )
  }

  func debug(_ message: String) {
    #if DEBUG
    logger.debug("\(message, privacy: .public)")
    #endif
  }

  func notice(_ message: String) {
    logger.notice("\(message, privacy: .public)")
  }

  func error(_ message: String) {
    logger.error("\(message, privacy: .public)")
  }
}
