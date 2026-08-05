import AVFoundation
import Foundation
import UIKit

// MARK: - RemuxProcessor

/// 无损转封装协议。默认实现使用 AVFoundation passthrough；
/// 未来可替换为 FFmpeg 后端而不影响调用方。
protocol RemuxProcessor {
    func remuxToMP4(source: URL, output: URL) async throws
}

struct AVFoundationRemuxProcessor: RemuxProcessor {
    func remuxToMP4(source: URL, output: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw MediaProcessError.remuxFailed
        }
        session.outputURL = output
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = false
        try await session.export()
        guard FileManager.default.fileExists(atPath: output.path) else {
            throw MediaProcessError.remuxFailed
        }
    }
}

// MARK: - MuxProcessor

/// 合并独立的视频轨与音频轨（DASH / HLS 分离流）后无损导出 MP4。
protocol MuxProcessor {
    func muxToMP4(video: URL, audio: URL?, output: URL) async throws
}

struct AVFoundationMuxProcessor: MuxProcessor {
    func muxToMP4(video: URL, audio: URL?, output: URL) async throws {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: video)
        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              )
        else {
            throw MediaProcessError.muxFailed
        }
        let videoDuration = try await videoAsset.load(.duration)
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: videoDuration),
            of: videoTrack,
            at: .zero
        )

        if let audio,
           FileManager.default.fileExists(atPath: audio.path) {
            let audioAsset = AVURLAsset(url: audio)
            if let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
               let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                let audioDuration = try await audioAsset.load(.duration)
                try compositionAudioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: audioDuration),
                    of: audioTrack,
                    at: .zero
                )
            }
        }

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw MediaProcessError.muxFailed
        }
        session.outputURL = output
        session.outputFileType = .mp4
        try await session.export()
        guard FileManager.default.fileExists(atPath: output.path) else {
            throw MediaProcessError.muxFailed
        }
    }
}

// MARK: - MetadataExtractor

struct MetadataExtractor {
    func extract(from url: URL) async throws -> MediaAssetInfo {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let size: Int64 = (try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0

        var width = 0
        var height = 0
        var bitrate = 0.0
        if let track = tracks.first {
            let naturalSize = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let rotated = transform.a == 0 && transform.b != 0
            width = Int(rotated ? naturalSize.height : naturalSize.width)
            height = Int(rotated ? naturalSize.width : naturalSize.height)
            let dataRate: Float = try await track.load(.estimatedDataRate)
            bitrate = Double(dataRate)
        }
        guard !duration.isNaN, duration > 0 else {
            throw MediaProcessError.metadataFailed
        }
        return MediaAssetInfo(
            duration: duration,
            width: width,
            height: height,
            estimatedBitrate: bitrate,
            fileSizeBytes: size
        )
    }
}

// MARK: - ThumbnailGenerator

struct ThumbnailGenerator {
    func generate(from url: URL, at time: CMTime = CMTime(seconds: 1, preferredTimescale: 600))
        async throws -> Data {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
        guard let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8) else {
            throw MediaProcessError.thumbnailFailed
        }
        return data
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

    /// 启动时清扫遗留工作目录（异常退出后由恢复逻辑接管，这里只清空不再需要的）。
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
