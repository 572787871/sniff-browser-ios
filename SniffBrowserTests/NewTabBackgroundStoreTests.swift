import UIKit
import XCTest
@testable import SniffBrowser

final class NewTabBackgroundStoreTests: XCTestCase {
  @MainActor
  func testSaveLoadAndRemoveBackgroundImage() throws {
    let suiteName = "NewTabBackgroundStoreTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    let directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("NewTabBackgroundStoreTests-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: directoryURL)
      defaults.removePersistentDomain(forName: suiteName)
    }

    let store = NewTabBackgroundStore(
      directoryURL: directoryURL,
      userDefaults: defaults
    )
    let image = UIGraphicsImageRenderer(
      size: CGSize(width: 48, height: 32)
    ).image { context in
      UIColor.systemTeal.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 48, height: 32))
    }

    XCTAssertFalse(store.hasImage)
    XCTAssertFalse(store.hasCustomImage)
    XCTAssertEqual(store.selection, .none)
    XCTAssertNil(store.image())

    try store.save(image)

    XCTAssertTrue(store.hasImage)
    XCTAssertTrue(store.hasCustomImage)
    XCTAssertEqual(store.selection, .custom)
    XCTAssertNotNil(store.image())

    try store.remove()

    XCTAssertFalse(store.hasImage)
    XCTAssertFalse(store.hasCustomImage)
    XCTAssertEqual(store.selection, .none)
    XCTAssertNil(store.image())
  }

  @MainActor
  func testBuiltInPresetRendersAndPersistsSelection() throws {
    let suiteName = "NewTabBackgroundPresetTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    let directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("NewTabBackgroundPresetTests-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: directoryURL)
      defaults.removePersistentDomain(forName: suiteName)
    }

    let store = NewTabBackgroundStore(
      directoryURL: directoryURL,
      userDefaults: defaults
    )
    store.selectPreset(.aurora)

    XCTAssertEqual(store.selection, .preset(.aurora))
    XCTAssertTrue(store.hasImage)
    let image = try XCTUnwrap(store.image())
    XCTAssertEqual(image.size.width, 720, accuracy: 0.001)
    XCTAssertEqual(image.size.height, 1_560, accuracy: 0.001)

    let restoredStore = NewTabBackgroundStore(
      directoryURL: directoryURL,
      userDefaults: defaults
    )
    XCTAssertEqual(restoredStore.selection, .preset(.aurora))
    XCTAssertNotNil(restoredStore.image())

    restoredStore.selectDefault()
    XCTAssertEqual(restoredStore.selection, .none)
    XCTAssertNil(restoredStore.image())
  }
}
