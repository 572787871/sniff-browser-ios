import Foundation

/// 统一媒体处理管线：所有格式的下载完成后都经过这里，
/// 只对外暴露最终视频文件与封面，隐藏一切底层细节。
@MainActor
final class MediaPipeline {
    static let shared = MediaPipeline()

    private let remuxer = AVFoundationRemuxProcessor()
    private let muxer = AVFoundationMuxProcessor()
    private let metadataExtractor = MetadataExtractor()
    private let thumbnailGenerator = ThumbnailGenerator()
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
        ), !isDirectory.boolValue
        else {
            return nil
        }

        do {
            let workDirectory = try cache.makeWorkDirectory(taskID: taskID)
            let type = preferredType != .unknown
                ? preferredType
                : MediaTypeDetector.detect(url: sourceURL, contentType: nil)

            var finalSource = sourceURL
            var finalExtension = type.preferredFileExtension

            switch type {
            case .mp4, .m4v, .mov, .ts, .flv, .hls, .dash:
                // 无损 passthrough 转封装为 MP4；失败则保留原文件。
                let remuxed = workDirectory
                    .appendingPathComponent("\(UUID().uuidString).mp4")
                let remuxSucceeded = (try? await remuxer.remuxToMP4(
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

            let info = try await metadataExtractor.extract(from: finalSource)
            let thumbnail = try? await thumbnailGenerator.generate(from: finalSource)
            let stored = try fileStorage.storeFinalFile(
                from: finalSource,
                fileName: fileName,
                extension: finalExtension
            )
            cache.removeWorkDirectory(taskID: taskID)
            return FinalMedia(
                url: stored,
                fileName: stored.lastPathComponent,
                thumbnailData: thumbnail,
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
}
