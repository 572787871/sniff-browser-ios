import XCTest
@testable import SniffBrowser

// 仅在正式构建（FFMPEG_ENABLED）下编译运行：使用真实 libav 媒体引擎验证
// 各格式的转封装、合并、元数据与封面。本地无 FFmpeg 时该文件为空。
#if FFMPEG_ENABLED

final class FFmpegPipelineIntegrationTests: XCTestCase {

    private var processor: FFmpegLibraryProcessor!
    private var workDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        processor = FFmpegLibraryProcessor()
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FFmpegIntegration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: workDirectory.path) {
            try FileManager.default.removeItem(at: workDirectory)
        }
        workDirectory = nil
        try super.tearDownWithError()
    }

    private func fixture(
        _ name: String,
        _ ext: String,
        subdirectory: String? = nil
    ) -> URL {
        guard let url = Bundle(for: Self.self).url(
            forResource: name,
            withExtension: ext,
            subdirectory: subdirectory ?? "Fixtures"
        ) else {
            XCTFail("缺少测试样本：\(name).\(ext)")
            return URL(fileURLWithPath: "/nonexistent")
        }
        return url
    }

    private func output(_ name: String) -> URL {
        workDirectory.appendingPathComponent(name)
    }

    private func assertRemuxSucceeds(
        source: URL,
        outputName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let output = output(outputName)
        do {
            try await processor.remux(
                source: source,
                output: output,
                container: "mp4"
            )
        } catch {
            XCTFail("remux 失败：\(error.localizedDescription)", file: file, line: line)
            return
        }
        guard let size = try? FileManager.default
            .attributesOfItem(atPath: output.path)[.size] as? Int64
        else {
            XCTFail("remux 未生成输出文件", file: file, line: line)
            return
        }
        XCTAssertGreaterThan(size, 1_000, file: file, line: line)
    }

    func testRemuxMP4() async {
        await assertRemuxSucceeds(source: fixture("fixture", "mp4"), outputName: "out.mp4")
    }

    func testRemuxMOV() async {
        await assertRemuxSucceeds(source: fixture("fixture", "mov"), outputName: "out-mov.mp4")
    }

    func testRemuxTS() async {
        await assertRemuxSucceeds(source: fixture("fixture", "ts"), outputName: "out-ts.mp4")
    }

    func testRemuxMKV() async {
        await assertRemuxSucceeds(source: fixture("fixture", "mkv"), outputName: "out-mkv.mp4")
    }

    func testRemuxWebM() async {
        await assertRemuxSucceeds(
            source: fixture("fixture-webm-opus", "webm"),
            outputName: "out-webm.mp4"
        )
    }

    func testRemuxWebMVorbisIsGraceful() async {
        // vorbis 音轨无法无损封装进 MP4：允许优雅失败（管线保留原 WebM），
        // 不允许崩溃或挂起。
        let output = output("out-webm-vorbis.mp4")
        do {
            try await processor.remux(
                source: fixture("fixture-webm-vorbis", "webm"),
                output: output,
                container: "mp4"
            )
            if FileManager.default.fileExists(atPath: output.path) {
                XCTAssertGreaterThan(
                    (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int64) ?? 0,
                    1_000
                )
            }
        } catch {
            // 优雅失败是预期行为。
        }
    }

    func testRemuxFLV() async {
        await assertRemuxSucceeds(source: fixture("fixture", "flv"), outputName: "out-flv.mp4")
    }

    func testRemuxHLS() async {
        let playlist = fixture("index", "m3u8", subdirectory: "Fixtures/hls")
        await assertRemuxSucceeds(source: playlist, outputName: "out-hls.mp4")
    }

    func testRemuxDASH() async {
        let mpd = fixture("stream", "mpd", subdirectory: "Fixtures/dash")
        await assertRemuxSucceeds(source: mpd, outputName: "out-dash.mp4")
    }

    func testMuxVideoAndAudio() async {
        let output = output("out-mux.mp4")
        do {
            try await processor.mux(
                video: fixture("video-only", "mp4"),
                audio: fixture("audio-only", "m4a"),
                output: output,
                container: "mp4"
            )
        } catch {
            XCTFail("mux 失败：\(error.localizedDescription)")
            return
        }
        guard let size = try? FileManager.default
            .attributesOfItem(atPath: output.path)[.size] as? Int64
        else {
            XCTFail("mux 未生成输出文件")
            return
        }
        XCTAssertGreaterThan(size, 1_000)
    }

    func testExtractMetadata() async throws {
        let info = try await processor.extractMetadata(from: fixture("fixture", "mp4"))
        XCTAssertGreaterThan(info.duration, 1)
        XCTAssertEqual(info.width, 320)
        XCTAssertEqual(info.height, 180)
        XCTAssertGreaterThan(info.fileSizeBytes, 0)
    }

    func testGenerateThumbnail() async throws {
        let output = output("thumb.jpg")
        try await processor.generateThumbnail(
            from: fixture("fixture", "mp4"),
            output: output
        )
        guard let data = try? Data(contentsOf: output) else {
            XCTFail("封面文件缺失")
            return
        }
        // JPEG 魔数：FF D8 FF
        XCTAssertTrue(data.count > 100)
        XCTAssertEqual([UInt8](data.prefix(3)), [0xFF, 0xD8, 0xFF])
    }
}

#endif
