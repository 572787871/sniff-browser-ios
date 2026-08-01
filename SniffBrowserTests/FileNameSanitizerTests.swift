import XCTest
@testable import SniffBrowser

final class FileNameSanitizerTests: XCTestCase {
  func testRemovesEveryIllegalFileNameCharacter() {
    let result = FileNameSanitizer.sanitize(
      "视频/片段\\测试?%*|\"<>:最终版.mp4"
    )
    let illegalCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")

    XCTAssertNil(result.rangeOfCharacter(from: illegalCharacters))
    XCTAssertTrue(result.hasSuffix("最终版.mp4"))
    XCTAssertFalse(result.contains("__"))
  }

  func testRemovesControlCharactersAndNewlines() {
    let result = FileNameSanitizer.sanitize("第一行\n第二行\u{0007}.mp4")

    XCTAssertFalse(result.contains("\n"))
    XCTAssertNil(result.rangeOfCharacter(from: .controlCharacters))
    XCTAssertEqual(result, "第一行_第二行_.mp4")
  }

  func testHonorsMaximumLengthBySwiftCharacters() {
    let result = FileNameSanitizer.sanitize(
      "一二三四五六七八九十十一十二",
      maximumLength: 8
    )

    XCTAssertEqual(result, "一二三四五六七八")
    XCTAssertEqual(result.count, 8)
  }

  func testPreservesExtensionWhenTruncatingLongFileName() {
    let result = FileNameSanitizer.sanitize(
      "这是一个非常非常长的视频文件名称.mp4",
      maximumLength: 12
    )

    XCTAssertEqual(result.count, 12)
    XCTAssertTrue(result.hasSuffix(".mp4"))
  }

  func testFallsBackToUnnamedFileForOnlyInvalidContent() {
    XCTAssertEqual(FileNameSanitizer.sanitize("..."), "未命名文件")
    XCTAssertEqual(FileNameSanitizer.sanitize("   "), "未命名文件")
  }

  func testTrimsLeadingAndTrailingDotsAndSpaces() {
    XCTAssertEqual(
      FileNameSanitizer.sanitize("  .示例视频.mp4.  "),
      "示例视频.mp4"
    )
  }
}
