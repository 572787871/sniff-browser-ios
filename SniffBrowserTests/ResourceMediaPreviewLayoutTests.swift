import UIKit
import XCTest
@testable import SniffBrowser

final class ResourceMediaPreviewLayoutTests: XCTestCase {
    @MainActor
    func testCustomHeaderIsSeparatedFromSystemPlayerArea() throws {
        let playbackURL = try XCTUnwrap(
            URL(string: "http://127.0.0.1:12345/sample.m3u8")
        )
        let controller = ResourceMediaPreviewViewController(
            title: "very-long-resource-name-that-must-truncate-in-the-header.m3u8",
            playbackURL: playbackURL,
            downloadTitle: "下载视频",
            onDownload: {}
        )

        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let header = try XCTUnwrap(
            controller.view.descendant(
                accessibilityIdentifier: "resource.media-preview.header"
            )
        )
        let player = try XCTUnwrap(
            controller.view.descendant(
                accessibilityIdentifier: "resource.media-preview.player"
            )
        )
        let download = try XCTUnwrap(
            controller.view.descendant(
                accessibilityIdentifier: "resource.media-preview.download"
            )
        )
        let close = try XCTUnwrap(
            controller.view.descendant(
                accessibilityIdentifier: "resource.media-preview.close"
            )
        )

        let headerFrame = header.convert(header.bounds, to: controller.view)
        let playerFrame = player.convert(player.bounds, to: controller.view)
        let downloadFrame = download.convert(download.bounds, to: controller.view)
        let closeFrame = close.convert(close.bounds, to: controller.view)

        XCTAssertLessThanOrEqual(headerFrame.maxY, playerFrame.minY + 0.5)
        XCTAssertLessThanOrEqual(downloadFrame.maxX, closeFrame.minX + 0.5)
        XCTAssertGreaterThanOrEqual(downloadFrame.height, 44)
        XCTAssertGreaterThanOrEqual(closeFrame.width, 44)
    }
}

private extension UIView {
    func descendant(accessibilityIdentifier identifier: String) -> UIView? {
        if accessibilityIdentifier == identifier {
            return self
        }
        for subview in subviews {
            if let match = subview.descendant(
                accessibilityIdentifier: identifier
            ) {
                return match
            }
        }
        return nil
    }
}
