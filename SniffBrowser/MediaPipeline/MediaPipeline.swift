import Foundation

/// 统一媒体处理管线：所有格式的下载完成后都经过这里，
/// 只对外暴露最终视频文件与封面，隐藏一切底层细节。
@MainActor
final class MediaPipeline {
    static let shared = MediaPipeline()

    private let processors = FFmpegMediaProcessors(
        processor: FFmpegProcessorProvider.current
    )
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
            if type == .unknown, !sourceIsDirectory {
                return nil
            }

            var finalSource = sourceURL
            var finalExtension = type.preferredFileExtension

            if type == .hls, sourceIsDirectory {
                // 自包含 HLS 包（.sniffhls）→ 单个 MP4。
                let remuxed = workDirectory
                    .appendingPathComponent("\(UUID().uuidString).mp4")
                let indexURL = sourceURL.appendingPathComponent("index.m3u8")
                let ffmpegSucceeded = (try? await processors.remux(
                    source: indexURL,
                    output: remuxed,
                    container: "mp4"
                )) != nil
                guard ffmpegSucceeded,
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
            case .ts, .flv, .hls, .mkv, .webm, .mov, .m4v:
                // 无损 passthrough 转封装为 MP4；失败则保留原文件。
                let remuxed = workDirectory
                    .appendingPathComponent("\(UUID().uuidString).mp4")
                let remuxSucceeded = (try? await processors.remux(
                    source: sourceURL,
                    output: remuxed,
                    container: "mp4"
                )) != nil
                if remuxSucceeded,
                   FileManager.default.fileExists(atPath: remuxed.path) {
                    finalSource = remuxed
                    finalExtension = "mp4"
                } else if type == .mov || type == .m4v {
                    finalExtension = type.rawValue
                }
            case .dash:
                // DASH：FFmpeg 直接处理 MPD（下载并封装）；本地 MPD 走转封装。
                let remuxed = workDirectory
                    .appendingPathComponent("\(UUID().uuidString).mp4")
                let isRemote = ["http", "https"].contains(
                    sourceURL.scheme?.lowercased() ?? ""
                )
                let succeeded: Bool
                if isRemote {
                    succeeded = (try? await processors.processRemote(
                        source: sourceURL,
                        output: remuxed,
                        container: "mp4"
                    )) != nil
                } else {
                    succeeded = (try? await processors.remux(
                        source: sourceURL,
                        output: remuxed,
                        container: "mp4"
                    )) != nil
                }
                if succeeded, FileManager.default.fileExists(atPath: remuxed.path) {
                    finalSource = remuxed
                    finalExtension = "mp4"
                }
            case .mp4:
                // 直接可播，无需转封装。
                finalExtension = "mp4"
            case .audio:
                finalExtension = type.preferredFileExtension
            case .unknown:
                break
                }
            }

            let info = await extractMetadata(from: finalSource)
            let thumbnail = await generateThumbnail(
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

    /// 元数据统一走 FFmpegProcessor；失败时不阻塞最终文件产出。
    private func extractMetadata(from url: URL) async -> MediaAssetInfo {
        let size: Int64 = (try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        return (try? await processors.extract(from: url)) ?? MediaAssetInfo(
            duration: 0,
            width: 0,
            height: 0,
            estimatedBitrate: 0,
            fileSizeBytes: size
        )
    }

    private func generateThumbnail(
        from url: URL,
        taskID: UUID
    ) async -> (data: Data, relativePath: String)? {
        let directory = thumbnailsDirectory
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let output = directory.appendingPathComponent("\(taskID.uuidString).jpg")
        _ = try? await processors.generate(from: url, output: output)
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
