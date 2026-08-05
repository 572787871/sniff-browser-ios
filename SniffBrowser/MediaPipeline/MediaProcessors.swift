import Foundation

// MARK: - 处理器协议

/// 无损转封装。统一委托给 FFmpegProcessor，下载模块不直接接触 FFmpeg。
protocol RemuxProcessor {
    func remuxToMP4(source: URL, output: URL) async throws
}

/// 合并独立的视频轨与音频轨（DASH / HLS 分离流）。
protocol MuxProcessor {
    func muxToMP4(video: URL, audio: URL?, output: URL) async throws
}

/// 元数据提取（时长/分辨率/码率/大小）。
protocol MetadataExtractor {
    func extract(from url: URL) async throws -> MediaAssetInfo
}

/// 封面生成。
protocol ThumbnailGenerator {
    func generate(from url: URL, output: URL) async throws
}

/// 唯一实现：四个处理器都通过 FFmpegProcessor 完成。
/// 生产构建只需替换 FFmpegProcessorProvider 的返回值，无需改这里。
struct FFmpegMediaProcessors: RemuxProcessor, MuxProcessor, MetadataExtractor, ThumbnailGenerator {
    let processor: FFmpegProcessor

    func remuxToMP4(source: URL, output: URL) async throws {
        try await processor.remuxToMP4(source: source, output: output)
    }

    func muxToMP4(video: URL, audio: URL?, output: URL) async throws {
        try await processor.muxToMP4(video: video, audio: audio, output: output)
    }

    func extract(from url: URL) async throws -> MediaAssetInfo {
        try await processor.extractMetadata(from: url)
    }

    func generate(from url: URL, output: URL) async throws {
        try await processor.generateThumbnail(from: url, output: output)
    }
}

// MARK: - FileStorageManager

/// 最终文件存储：Documents/Videos（“文件”App 中显示为 SniffBrowser/Videos）。
final class FileStorageManager {
    static let shared = FileStorageManager()

    private let fileManager = FileManager.default

    var videosDirectory: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("Videos", isDirectory: true)
    }

    func uniqueDestination(
        fileName: String,
        preferredExtension: String
    ) -> URL {
        try? fileManager.createDirectory(
            at: videosDirectory,
            withIntermediateDirectories: true
        )
        let cleanBase = fileName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let base = (cleanBase as NSString).deletingPathExtension.isEmpty
            ? "视频"
            : (cleanBase as NSString).deletingPathExtension
        let ext = preferredExtension.lowercased()
        var candidate = videosDirectory.appendingPathComponent("\(base).\(ext)")
        var index = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = videosDirectory.appendingPathComponent(
                "\(base)-\(index).\(ext)"
            )
            index += 1
        }
        return candidate
    }

    /// 把最终文件原子移动到 Videos 目录，返回新位置。
    @discardableResult
    func storeFinalFile(from source: URL, fileName: String, extension ext: String) throws -> URL {
        let destination = uniqueDestination(fileName: fileName, preferredExtension: ext)
        do {
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            try? fileManager.copyItem(at: source, to: destination)
        }
        guard fileManager.fileExists(atPath: destination.path) else {
            throw MediaProcessError.storageFailed
        }
        return destination
    }
}

// MARK: - CacheManager

/// 管线工作目录与缓存清理。处理成功后删除全部临时文件；启动时清扫遗留目录。
final class CacheManager {
    static let shared = CacheManager()

    private let fileManager = FileManager.default

    var pipelineRoot: URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupport.appendingPathComponent(
            "MediaPipeline",
            isDirectory: true
        )
    }

    func makeWorkDirectory(taskID: UUID) throws -> URL {
        let directory = pipelineRoot.appendingPathComponent(
            taskID.uuidString,
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    func workDirectory(for taskID: UUID) -> URL? {
        let directory = pipelineRoot.appendingPathComponent(
            taskID.uuidString,
            isDirectory: true
        )
        return fileManager.fileExists(atPath: directory.path) ? directory : nil
    }

    func removeWorkDirectory(taskID: UUID) {
        guard let directory = workDirectory(for: taskID) else { return }
        try? fileManager.removeItem(at: directory)
    }

    /// 启动时清扫遗留工作目录（任务已不存在的）。
    func sweepLeftovers(activeTaskIDs: Set<UUID>) {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: pipelineRoot,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        for entry in entries {
            guard let taskID = UUID(uuidString: entry.lastPathComponent),
                  !activeTaskIDs.contains(taskID)
            else {
                continue
            }
            try? fileManager.removeItem(at: entry)
        }
    }
}
