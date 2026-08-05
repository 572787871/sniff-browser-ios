import Darwin
import Foundation

/// 唯一媒体处理入口：FFmpeg 作为完整 Media Engine。
///
/// 所有媒体后处理统一经过这里：容器转封装、音视频合成、远程清单直处理、
/// 元数据（ffprobe）、封面，以及未来的裁剪/转码。下载模块与 Media Pipeline
/// 不直接依赖 FFmpeg；新增媒体格式时只扩展本协议与实现。
protocol FFmpegProcessor {
    /// 无损容器转封装（-c copy）：HLS 播放列表、TS、FLV、MKV、WebM、MOV 等 → 目标容器。
    func remux(source: URL, output: URL, container: String) async throws

    /// 合并独立视频轨与音频轨（DASH 音视频流）→ 目标容器。
    func mux(video: URL, audio: URL?, output: URL, container: String) async throws

    /// 远程清单直接处理（HLS/DASH URL）：FFmpeg 下载并封装为最终文件。
    func processRemote(source: URL, output: URL, container: String) async throws

    /// ffprobe 提取时长、码率、分辨率、大小。
    func extractMetadata(from url: URL) async throws -> MediaAssetInfo

    /// 生成封面。
    func generateThumbnail(from url: URL, output: URL) async throws
}

/// 使用 App 内捆绑的 ffmpeg / ffprobe（GitHub Actions 集成 XCFramework 时
/// 由 FFmpegLibraryProcessor 替换本实现，接口不变）。
struct BundledFFmpegProcessor: FFmpegProcessor {
    let ffmpegURL: URL
    let ffprobeURL: URL?

    func remux(source: URL, output: URL, container: String) async throws {
        try await run([
            "-y",
            "-i", source.path,
            "-c", "copy",
            "-movflags", "+faststart",
            output.path,
        ], outputURL: output)
        guard FileManager.default.fileExists(atPath: output.path) else {
            throw MediaProcessError.remuxFailed
        }
    }

    func mux(video: URL, audio: URL?, output: URL, container: String) async throws {
        var arguments = ["-y", "-i", video.path]
        if let audio, FileManager.default.fileExists(atPath: audio.path) {
            arguments += ["-i", audio.path]
        }
        arguments += [
            "-c", "copy",
            "-movflags", "+faststart",
            output.path,
        ]
        try await run(arguments, outputURL: output)
        guard FileManager.default.fileExists(atPath: output.path) else {
            throw MediaProcessError.muxFailed
        }
    }

    func processRemote(source: URL, output: URL, container: String) async throws {
        try await run([
            "-y",
            "-i", source.absoluteString,
            "-c", "copy",
            "-movflags", "+faststart",
            output.path,
        ], outputURL: output)
        guard FileManager.default.fileExists(atPath: output.path) else {
            throw MediaProcessError.remuxFailed
        }
    }

    func extractMetadata(from url: URL) async throws -> MediaAssetInfo {
        if let ffprobeURL {
            let logURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: logURL) }
            try Self.runProcess(
                executable: ffprobeURL,
                arguments: [
                    "-v", "error",
                    "-print_format", "json",
                    "-show_format",
                    "-show_streams",
                    url.path,
                ],
                stdoutURL: logURL
            )
            if let data = try? Data(contentsOf: logURL),
               let info = Self.parseFFprobeJSON(data, fileURL: url) {
                return info
            }
        }

        // 兜底：解析 `ffmpeg -i` 输出。
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: logURL) }
        try Self.runProcess(
            executable: ffmpegURL,
            arguments: ["-i", url.path],
            stdoutURL: logURL
        )
        let text = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        let size: Int64 = (try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        return Self.parseFFmpegInfo(from: text, fileSizeBytes: size)
    }

    func generateThumbnail(from url: URL, output: URL) async throws {
        try await run([
            "-y",
            "-ss", "1",
            "-i", url.path,
            "-frames:v", "1",
            "-vf", "scale=480:-1",
            output.path,
        ], outputURL: output)
        guard FileManager.default.fileExists(atPath: output.path) else {
            throw MediaProcessError.thumbnailFailed
        }
    }

    private func run(_ arguments: [String], outputURL: URL) async throws {
        try Self.runProcess(
            executable: ffmpegURL,
            arguments: arguments,
            stdoutURL: outputURL.deletingLastPathComponent()
                .appendingPathComponent("\(UUID().uuidString).log")
        )
    }

    // MARK: - ffprobe JSON 解析

    private static func parseFFprobeJSON(
        _ data: Data,
        fileURL: URL
    ) -> MediaAssetInfo? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any]
        else {
            return nil
        }
        let format = root["format"] as? [String: Any]
        let duration = (format?["duration"] as? String).flatMap(Double.init) ?? 0
        let bitrate = (format?["bit_rate"] as? String).flatMap(Double.init) ?? 0
        let size: Int64 = (try? FileManager.default
            .attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0

        var width = 0
        var height = 0
        if let streams = root["streams"] as? [[String: Any]] {
            if let video = streams.first(where: { $0["codec_type"] as? String == "video" }) {
                width = (video["width"] as? Int) ?? 0
                height = (video["height"] as? Int) ?? 0
            }
        }
        guard duration > 0 else { return nil }
        return MediaAssetInfo(
            duration: duration,
            width: width,
            height: height,
            estimatedBitrate: bitrate,
            fileSizeBytes: size
        )
    }

    private static func parseFFmpegInfo(
        from text: String,
        fileSizeBytes: Int64
    ) -> MediaAssetInfo {
        var duration: TimeInterval = 0
        if let range = text.range(of: "Duration: "),
           let end = text[range.upperBound...].firstIndex(of: ",") {
            let value = String(text[range.upperBound..<end])
                .trimmingCharacters(in: .whitespaces)
            duration = parseDuration(value)
        }
        var width = 0
        var height = 0
        var bitrate = 0.0
        for line in text.split(separator: "\n") where line.contains("Video:") {
            let content = String(line)
            if let sizeRange = content.range(
                of: #"\b\d{2,5}x\d{2,5}\b"#,
                options: .regularExpression
            ) {
                let size = content[sizeRange].split(separator: "x")
                if size.count == 2 {
                    width = Int(size[0]) ?? 0
                    height = Int(size[1]) ?? 0
                }
            }
            if let bitrateRange = content.range(
                of: #"\b[\d.]+ kb/s\b"#,
                options: .regularExpression
            ) {
                let value = content[bitrateRange]
                    .replacingOccurrences(of: " kb/s", with: "")
                bitrate = (Double(value) ?? 0) * 1_000
            }
        }
        return MediaAssetInfo(
            duration: duration,
            width: width,
            height: height,
            estimatedBitrate: bitrate,
            fileSizeBytes: fileSizeBytes
        )
    }

    private static func parseDuration(_ value: String) -> TimeInterval {
        let parts = value.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 3 else { return 0 }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    // MARK: - 进程执行

    /// 通过 posix_spawn 运行 ffmpeg/ffprobe，stdout/stderr 重定向到文件。
    private static func runProcess(
        executable: URL,
        arguments: [String],
        stdoutURL: URL
    ) throws {
        var argv: [UnsafeMutablePointer<CChar>?] = [strdup(executable.path)]
        argv.append(contentsOf: arguments.map { strdup($0) })
        argv.append(nil)
        defer { argv.forEach { free($0) } }

        let stdoutFD = open(stdoutURL.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard stdoutFD >= 0 else {
            throw MediaProcessError.metadataFailed
        }
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_adddup2(&fileActions, stdoutFD, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, stdoutFD, STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, stdoutFD)

        var pid: pid_t = 0
        let spawnResult = posix_spawn(
            &pid,
            executable.path,
            &fileActions,
            nil,
            argv,
            environ
        )
        posix_spawn_file_actions_destroy(&fileActions)
        close(stdoutFD)
        guard spawnResult == 0 else {
            throw MediaProcessError.metadataFailed
        }
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        guard status == 0 else {
            throw MediaProcessError.metadataFailed
        }
    }
}

/// 占位实现：本地无 FFmpeg 时保证项目可编译；正式构建（GitHub Actions 集成
/// FFmpeg XCFramework）由 FFmpegProcessorProvider 返回真实实现。
struct StubFFmpegProcessor: FFmpegProcessor {
    func remux(source: URL, output: URL, container: String) async throws {
        throw MediaProcessError.ffmpegUnavailable
    }

    func mux(video: URL, audio: URL?, output: URL, container: String) async throws {
        throw MediaProcessError.ffmpegUnavailable
    }

    func processRemote(source: URL, output: URL, container: String) async throws {
        throw MediaProcessError.ffmpegUnavailable
    }

    func extractMetadata(from url: URL) async throws -> MediaAssetInfo {
        throw MediaProcessError.ffmpegUnavailable
    }

    func generateThumbnail(from url: URL, output: URL) async throws {
        throw MediaProcessError.ffmpegUnavailable
    }
}

/// 选择当前可用的 FFmpeg 实现：
/// - 正式构建（FFMPEG_ENABLED，GitHub Actions 集成 libav XCFramework）
///   走 FFmpegLibraryProcessor（libav* C API）；
/// - 本地无 FFmpeg 时用 StubFFmpegProcessor 保证可编译。
enum FFmpegProcessorProvider {
    static var current: FFmpegProcessor {
        #if FFMPEG_ENABLED
        // 正式构建：直接调用捆绑的 libav* API（唯一媒体处理引擎）。
        return FFmpegLibraryProcessor()
        #else
        // 本地开发（无 FFmpeg）：Stub 保证可编译，运行时返回“未集成”错误。
        return StubFFmpegProcessor()
        #endif
    }
}
