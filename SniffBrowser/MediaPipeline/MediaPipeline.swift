import Foundation

/// 统一媒体处理管线：所有格式的下载完成后都经过这里，
/// 只对外暴露最终视频文件与封面，隐藏一切底层细节。
@MainActor
final class MediaPipeline {
    static let shared = MediaPipeline()

    private let processors = FFmpegMediaProcessors(
        processor: FFmpegProcessorProvider.current
    )
    private let avFallback = AVFoundationMediaProcessors()
    private let hlsAVRemuxer = HLSBundleAVRemuxer()
    private let fileStorage = FileStorageManager.shared
    private let cache = CacheManager.shared

    /// 对已下载的源执行统一后处理：
    /// 检测 → 需要时无损转封装 MP4 → 提取元数据与封面 → 移到 Videos → 清缓存。
    /// 返回最终媒体；无法处理时保留原文件并返回 nil（下载仍算完成）。
    func postProcess(
        taskID: UUID,
        sourceURL: URL,
        preferredType: MediaType,
        fileName: String
    ) async -> FinalMedia? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: sourceURL.path,
            isDirectory: &isDirectory
        ) else {
            return nil
        }
        let sourceIsDirectory = isDirectory.boolValue
        if sourceIsDirectory, preferredType != .hls {
            return nil
        }

        do {
            let workDirectory = try cache.makeWorkDirectory(taskID: taskID)
            let type = preferredType != .unknown
                ? preferredType
                : MediaTypeDetector.detect(url: sourceURL, contentType: nil)

            var finalSource = sourceURL
            var finalExtension = type.preferredFileExtension

            if type == .hls, sourceIsDirectory {
                // 自包含 HLS 包（.sniffhls）→ 单个 MP4。
                let remuxed = workDirectory
                    .appendingPathComponent("\(UUID().uuidString).mp4")
                let indexURL = sourceURL.appendingPathComponent("index.m3u8")
                let ffmpegSucceeded = (try? await processors.remuxToMP4(
                    source: indexURL,
                    output: remuxed
                )) != nil
                let avSucceeded = ffmpegSucceeded
                    ? false
                    : (try? await hlsAVRemuxer.remuxHLSBundle(
                        directory: sourceURL,
                        output: remuxed
                    )) != nil
                guard (ffmpegSucceeded || avSucceeded),
                      FileManager.default.fileExists(atPath: remuxed.path)
                else {
                    cache.removeWorkDirectory(taskID: taskID)
                    return nil
                }
                finalSource = remuxed
                finalExtension = "mp4"
                try? FileManager.default.removeItem(at: sourceURL)
            } else {
                switch type {
            case .mp4, .m4v, .mov, .ts, .flv, .hls, .dash:
                // 无损 passthrough 转封装为 MP4；失败则保留原文件。
                let remuxed = workDirectory
                    .appendingPathComponent("\(UUID().uuidString).mp4")
                let remuxSucceeded = (try? await processors.remuxToMP4(
                    source: sourceURL,
                    output: remuxed
                )) != nil
                if remuxSucceeded,
                   FileManager.default.fileExists(atPath: remuxed.path) {
                    finalSource = remuxed
                    finalExtension = "mp4"
                } else if type == .mov || type == .m4v {
                    finalExtension = type.rawValue
                }
            case .mkv, .webm:
                // AVFoundation 无法读取时保留原文件，App 内不可预览如实降级。
                finalExtension = type.rawValue
            case .audio, .unknown:
                finalExtension = type.preferredFileExtension
                }
            }

            let info = try await extractMetadata(from: finalSource)
            let thumbnail = try await generateThumbnail(
                from: finalSource,
                taskID: taskID
            )
            let stored = try fileStorage.storeFinalFile(
                from: finalSource,
                fileName: fileName,
                extension: finalExtension
            )
            cache.removeWorkDirectory(taskID: taskID)
            return FinalMedia(
                url: stored,
                fileName: stored.lastPathComponent,
                thumbnailData: thumbnail?.data,
                thumbnailLocalPath: thumbnail?.relativePath,
                info: info
            )
        } catch {
            cache.removeWorkDirectory(taskID: taskID)
            return nil
        }
    }

    /// 启动时清理遗留工作目录（任务已不存在或已完成的）。
    func sweepLeftoverWorkDirectories(activeTaskIDs: Set<UUID>) {
        cache.sweepLeftovers(activeTaskIDs: activeTaskIDs)
    }

    /// 元数据：优先 FFmpeg，不可用时 AVFoundation 兜底（MP4/MOV/M4V 均可用）。
    private func extractMetadata(from url: URL) async throws -> MediaAssetInfo {
        if let info = try? await processors.extract(from: url) {
            return info
        }
        return try await avFallback.extract(from: url)
    }

    private func generateThumbnail(
        from url: URL,
        taskID: UUID
    ) async throws -> (data: Data, relativePath: String)? {
        let directory = thumbnailsDirectory
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let output = directory.appendingPathComponent("\(taskID.uuidString).jpg")
        if (try? await processors.generate(from: url, output: output)) == nil {
            try? await avFallback.generate(from: url, output: output)
        }
        guard let data = try? Data(contentsOf: output) else { return nil }
        return (data, "Thumbnails/\(output.lastPathComponent)")
    }

    private var thumbnailsDirectory: URL {
        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        return documents.appendingPathComponent("Thumbnails", isDirectory: true)
    }
}
