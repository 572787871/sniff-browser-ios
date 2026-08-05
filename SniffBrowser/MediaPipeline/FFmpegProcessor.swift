import Darwin
import Foundation

/// 统一媒体处理后端：所有媒体后处理（转封装、合成、元数据、封面）
/// 都通过 FFmpegProcessor 完成。下载模块不直接调用 FFmpeg。
protocol FFmpegProcessor {
    func remuxToMP4(source: URL, output: URL) async throws
    func muxToMP4(video: URL, audio: URL?, output: URL) async throws
    func extractMetadata(from url: URL) async throws -> MediaAssetInfo
    func generateThumbnail(from url: URL, output: URL) async throws
}

/// 使用 App 内捆绑的 ffmpeg 可执行文件（由 GitHub Actions 集成）。
struct BundledFFmpegProcessor: FFmpegProcessor {
    let ffmpegURL: URL

    func remuxToMP4(source: URL, output: URL) async throws {
        try run(
            arguments: [
                "-y",
                "-i", source.path,
                "-c", "copy",
                "-movflags", "+faststart",
                output.path,
            ],
            stdoutURL: output.deletingLastPathComponent()
                .appendingPathComponent("\(UUID().uuidString).log")
        )
        guard FileManager.default.fileExists(atPath: output.path) else {
            throw MediaProcessError.remuxFailed
        }
    }

    func muxToMP4(video: URL, audio: URL?, output: URL) async throws {
        var arguments = ["-y", "-i", video.path]
        if let audio, FileManager.default.fileExists(atPath: audio.path) {
            arguments += ["-i", audio.path]
        }
        arguments += [
            "-c", "copy",
            "-movflags", "+faststart",
            output.path,
        ]
        try run(
            arguments: arguments,
            stdoutURL: output.deletingLastPathComponent()
                .appendingPathComponent("\(UUID().uuidString).log")
        )
        guard FileManager.default.fileExists(atPath: output.path) else {
            throw MediaProcessError.muxFailed
        }
    }

    func extractMetadata(from url: URL) async throws -> MediaAssetInfo {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: logURL) }
        try run(
            arguments: ["-i", url.path],
            stdoutURL: logURL
        )
        let text = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        let size: Int64 = (try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        return parseMetadata(from: text, fileSizeBytes: size)
    }

    func generateThumbnail(from url: URL, output: URL) async throws {
        try run(
            arguments: [
                "-y",
                "-ss", "1",
                "-i", url.path,
                "-frames:v", "1",
                "-vf", "scale=480:-1",
                output.path,
            ],
            stdoutURL: output.deletingLastPathComponent()
                .appendingPathComponent("\(UUID().uuidString).log")
        )
        guard FileManager.default.fileExists(atPath: output.path) else {
            throw MediaProcessError.thumbnailFailed
        }
    }

    private func run(arguments: [String], stdoutURL: URL) throws {
        try Self.runProcess(
            executable: ffmpegURL,
            arguments: arguments,
            stdoutURL: stdoutURL
        )
    }

    private func parseMetadata(
        from text: String,
        fileSizeBytes: Int64
    ) -> MediaAssetInfo {
        var duration: TimeInterval = 0
        if let range = text.range(of: "Duration: "),
           let end = text[range.upperBound...].firstIndex(of: ",") {
            let value = String(text[range.upperBound..<end]).trimmingCharacters(in: .whitespaces)
            duration = Self.parseDuration(value)
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

    /// 通过 posix_spawn 运行 ffmpeg，stdout/stderr 重定向到文件。
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
        // 正常退出且退出码为 0 时 waitpid 返回 status == 0。
        guard status == 0 else {
            throw MediaProcessError.metadataFailed
        }
    }
}

/// 占位实现：当前开发构建未捆绑 FFmpeg 时使用，保证项目可编译。
/// GitHub Actions 捆绑 ffmpeg 后自动替换为 BundledFFmpegProcessor。
struct StubFFmpegProcessor: FFmpegProcessor {
    func remuxToMP4(source: URL, output: URL) async throws {
        throw MediaProcessError.ffmpegUnavailable
    }

    func muxToMP4(video: URL, audio: URL?, output: URL) async throws {
        throw MediaProcessError.ffmpegUnavailable
    }

    func extractMetadata(from url: URL) async throws -> MediaAssetInfo {
        throw MediaProcessError.ffmpegUnavailable
    }

    func generateThumbnail(from url: URL, output: URL) async throws {
        throw MediaProcessError.ffmpegUnavailable
    }
}

/// 选择当前可用的 FFmpeg 实现：App 内捆绑了 ffmpeg 就用真实实现，
/// 否则用 Stub。生产构建（GitHub Actions）会捆绑 ffmpeg，无需改代码。
enum FFmpegProcessorProvider {
    static var current: FFmpegProcessor {
        if let url = Bundle.main.url(forResource: "ffmpeg", withExtension: nil) {
            return BundledFFmpegProcessor(ffmpegURL: url)
        }
        return StubFFmpegProcessor()
    }
}
