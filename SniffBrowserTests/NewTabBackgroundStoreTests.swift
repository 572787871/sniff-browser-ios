import UIKit
import XCTest
@testable import SniffBrowser

final class NewTabBackgroundStoreTests: XCTestCase {
  @MainActor
  func testSaveLoadAndRemoveBackgroundImage() throws {
    let directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("NewTabBackgroundStoreTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    let store = NewTabBackgroundStore(directoryURL: directoryURL)
    let image = UIGraphicsImageRenderer(
      size: CGSize(width: 48, height: 32)
    ).image { context in
      UIColor.systemTeal.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 48, height: 32))
    }

    XCTAssertFalse(store.hasImage)
    XCTAssertNil(store.image())

    try store.save(image)

    XCTAssertTrue(store.hasImage)
    XCTAssertNotNil(store.image())

    try store.remove()

    XCTAssertFalse(store.hasImage)
    XCTAssertNil(store.image())
  }
}
