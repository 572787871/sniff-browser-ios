import Foundation
import XCTest
@testable import SniffBrowser

final class ImageProtectionTests: XCTestCase {

    func testDecryptsKnownProtectedImage() throws {
        let data = try XCTUnwrap(
            encryptedFixtureData()
        )

        let decrypted = ImageProtection.decryptedImageData(
            from: data,
            sourceHost: "pic.uforxk.cn"
        )

        XCTAssertNotNil(decrypted)
        XCTAssertTrue(ImageProtection.isRecognizedImage(try XCTUnwrap(decrypted)))
        XCTAssertEqual([UInt8](try XCTUnwrap(decrypted).prefix(6)), [
            0x47, 0x49, 0x46, 0x38, 0x39, 0x61, // GIF89a
        ])
    }

    func testSubdomainHostAlsoMatches() throws {
        let data = try XCTUnwrap(encryptedFixtureData())
        XCTAssertNotNil(
            ImageProtection.decryptedImageData(
                from: data,
                sourceHost: "cdn.pic.uforxk.cn"
            )
        )
    }

    func testValidImageIsLeftUntouched() {
        let gif = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x00, 0x00])
        XCTAssertNil(
            ImageProtection.decryptedImageData(
                from: gif,
                sourceHost: "pic.uforxk.cn"
            )
        )
    }

    func testUnknownHostIsNotDecrypted() throws {
        let data = try XCTUnwrap(encryptedFixtureData())
        XCTAssertNil(
            ImageProtection.decryptedImageData(
                from: data,
                sourceHost: "example.com"
            )
        )
    }

    func testRecognizesCommonImageMagicBytes() {
        XCTAssertTrue(ImageProtection.isRecognizedImage(
            Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        ))
        XCTAssertTrue(ImageProtection.isRecognizedImage(
            Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        ))
        XCTAssertTrue(ImageProtection.isRecognizedImage(
            Data("GIF89a".utf8)
        ))
        XCTAssertTrue(ImageProtection.isRecognizedImage(
            Data([0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00,
                  0x57, 0x45, 0x42, 0x50])
        ))
        XCTAssertTrue(ImageProtection.isRecognizedImage(
            Data("<svg xmlns=\"http://www.w3.org/2000/svg\">".utf8)
        ))
        XCTAssertFalse(ImageProtection.isRecognizedImage(
            Data("not an image".utf8)
        ))
    }

    private func encryptedFixtureData() -> Data? {
        guard let url = Bundle(for: Self.self).url(
            forResource: "encrypted-sample",
            withExtension: "gif",
            subdirectory: "Fixtures"
        ) else {
            return nil
        }
        return try? Data(contentsOf: url)
    }
}
