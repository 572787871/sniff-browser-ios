import Foundation

enum DownloadKind: String, Codable, Sendable {
    case regularFile
    case hlsAsset
}

enum DownloadState: String, Codable, CaseIterable, Sendable {
    case waiting
    case preparing
    case downloading
    case paused
    case retrying
    case finalizing
    case completed
    case failed
    case cancelled

    var localizedTitle: String {
        switch self {
        case .waiting: return "等待中"
        case .preparing: return "正在准备"
        case .downloading: return "下载中"
        case .paused: return "已暂停"
        case .retrying: return "正在重试"
        case .finalizing: return "正在保存"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }

    var isInProgress: Bool {
        [.preparing, .downloading, .retrying, .finalizing].contains(self)
    }
}

typealias DownloadTaskState = DownloadState

struct DownloadTaskModel: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let resourceID: UUID?
    let sourceURL: URL
    let displayURL: String
    let thumbnailURL: URL?
    var fileName: String
    var fileExtension: String?
    var resourceType: ResourceType
    var downloadKind: DownloadKind
    var state: DownloadState
    var expectedSize: Int64?
    var downloadedSize: Int64
    var progressFraction: Double?
    var speedBytesPerSecond: Double?
    var estimatedRemainingTime: TimeInterval?
    var createdAt: Date
    var startedAt: Date?
    var updatedAt: Date
    var completedAt: Date?
    var destinationRelativePath: String?
    var errorCode: String?
    var errorDescription: String?
    var retryCount: Int
    var resumeDataRelativePath: String?
    var isHiddenFromDownloadHistory: Bool?

    var receivedBytes: Int64 {
        get { downloadedSize }
        set { downloadedSize = newValue }
    }

    var localRelativePath: String? {
        get { destinationRelativePath }
        set { destinationRelativePath = newValue }
    }

    var progress: Double? {
        if let progressFraction {
            return min(max(progressFraction, 0), 1)
        }
        guard let expectedSize, expectedSize > 0 else { return nil }
        return min(max(Double(downloadedSize) / Double(expectedSize), 0), 1)
    }

    init(
        id: UUID = UUID(),
        resourceID: UUID? = nil,
        sourceURL: URL,
        displayURL: String? = nil,
        thumbnailURL: URL? = nil,
        fileName: String,
        fileExtension: String? = nil,
        resourceType: ResourceType = .other,
        downloadKind: DownloadKind = .regularFile,
        state: DownloadState = .waiting,
        expectedSize: Int64? = nil,
        downloadedSize: Int64 = 0,
        progressFraction: Double? = nil,
        speedBytesPerSecond: Double? = nil,
        estimatedRemainingTime: TimeInterval? = nil,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        destinationRelativePath: String? = nil,
        errorCode: String? = nil,
        errorDescription: String? = nil,
        retryCount: Int = 0,
        resumeDataRelativePath: String? = nil,
        isHiddenFromDownloadHistory: Bool? = nil
    ) {
        self.id = id
        self.resourceID = resourceID
        self.sourceURL = sourceURL
        self.displayURL = displayURL ?? Self.safeDisplayURL(sourceURL)
        self.thumbnailURL = thumbnailURL
        self.fileName = fileName
        let inferredExtension = sourceURL.pathExtension.lowercased()
        self.fileExtension = fileExtension
            ?? (inferredExtension.isEmpty ? nil : inferredExtension)
        self.resourceType = resourceType
        self.downloadKind = downloadKind
        self.state = state
        self.expectedSize = expectedSize
        self.downloadedSize = downloadedSize
        self.progressFraction = progressFraction
        self.speedBytesPerSecond = speedBytesPerSecond
        self.estimatedRemainingTime = estimatedRemainingTime
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.destinationRelativePath = destinationRelativePath
        self.errorCode = errorCode
        self.errorDescription = errorDescription
        self.retryCount = retryCount
        self.resumeDataRelativePath = resumeDataRelativePath
        self.isHiddenFromDownloadHistory = isHiddenFromDownloadHistory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        resourceID = try container.decodeIfPresent(UUID.self, forKey: .resourceID)
        sourceURL = try container.decode(URL.self, forKey: .sourceURL)
        displayURL = try container.decodeIfPresent(String.self, forKey: .displayURL)
            ?? Self.safeDisplayURL(sourceURL)
        thumbnailURL = try container.decodeIfPresent(URL.self, forKey: .thumbnailURL)
        fileName = try container.decode(String.self, forKey: .fileName)

        let inferredExtension = sourceURL.pathExtension.lowercased()
        fileExtension = try container.decodeIfPresent(String.self, forKey: .fileExtension)
            ?? (inferredExtension.isEmpty ? nil : inferredExtension)
        resourceType = try container.decodeIfPresent(ResourceType.self, forKey: .resourceType)
            ?? Self.inferredResourceType(fileExtension: inferredExtension)
        downloadKind = try container.decodeIfPresent(DownloadKind.self, forKey: .downloadKind)
            ?? (inferredExtension == "m3u8" ? .hlsAsset : .regularFile)
        state = try container.decode(DownloadState.self, forKey: .state)
        expectedSize = try container.decodeIfPresent(Int64.self, forKey: .expectedSize)
        downloadedSize = try container.decodeIfPresent(Int64.self, forKey: .downloadedSize) ?? 0
        progressFraction = try container.decodeIfPresent(Double.self, forKey: .progressFraction)
        speedBytesPerSecond = try container.decodeIfPresent(
            Double.self,
            forKey: .speedBytesPerSecond
        )
        estimatedRemainingTime = try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .estimatedRemainingTime
        )
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        if completedAt == nil, state == .completed {
            completedAt = updatedAt
        }
        destinationRelativePath = try container.decodeIfPresent(
            String.self,
            forKey: .destinationRelativePath
        )
        errorCode = try container.decodeIfPresent(String.self, forKey: .errorCode)
        errorDescription = try container.decodeIfPresent(
            String.self,
            forKey: .errorDescription
        )
        retryCount = try container.decodeIfPresent(Int.self, forKey: .retryCount) ?? 0
        resumeDataRelativePath = try container.decodeIfPresent(
            String.self,
            forKey: .resumeDataRelativePath
        )
        isHiddenFromDownloadHistory = try container.decodeIfPresent(
            Bool.self,
            forKey: .isHiddenFromDownloadHistory
        )
    }

    private static func safeDisplayURL(_ url: URL) -> String {
        guard let host = url.host else { return url.scheme ?? "资源" }
        return host
    }

    private static func inferredResourceType(fileExtension: String) -> ResourceType {
        switch fileExtension {
        case "mp4", "mov", "m4v", "webm", "ts", "mpeg", "mpg", "mkv":
            return .video
        case "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus":
            return .audio
        case "m3u8":
            return .hls
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "avif", "svg":
            return .image
        case "vtt", "srt", "ass":
            return .subtitle
        case "zip", "rar", "7z", "tar", "gz":
            return .archive
        case "pdf", "txt", "epub", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "json", "xml":
            return .document
        default:
            return .other
        }
    }
}

enum DownloadCreationResult: Equatable {
    case created(UUID)
    case alreadyDownloading(UUID)
    case fileAlreadyExists(UUID)
}

enum DownloadCenterError: LocalizedError, Equatable {
    case invalidURL
    case unsupportedBlob
    case liveHLSUnsupported
    case protectedMediaUnsupported
    case taskUnavailable
    case resumeDataInvalid
    case serverRejected(Int)
    case unexpectedHTML
    case signedURLExpired
    case fileOperationFailed
    case invalidHLSPlaylist
    case invalidHLSKey
    case hlsDecryptionFailed
    case hlsSegmentFailed(Int)
    case hlsMergeFailed
    case hlsFinalizationFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "资源地址无效。"
        case .unsupportedBlob: return "Blob 资源不能直接下载。"
        case .liveHLSUnsupported: return "暂不支持下载直播视频。"
        case .protectedMediaUnsupported: return "不支持受保护媒体下载。"
        case .taskUnavailable: return "下载任务已不存在。"
        case .resumeDataInvalid: return "断点数据已失效，可以选择从头重新下载。"
        case let .serverRejected(code): return "服务器拒绝了下载请求（HTTP \(code)）。"
        case .unexpectedHTML: return "服务器返回了网页而不是目标文件，资源可能已失效。"
        case .signedURLExpired: return "资源链接可能已过期，请返回网页重新识别。"
        case .fileOperationFailed: return "文件保存失败，请检查可用存储空间。"
        case .invalidHLSPlaylist: return "视频资源无效或已过期，请返回网页重新识别。"
        case .invalidHLSKey: return "视频解密信息无效或已过期，请返回网页重新识别。"
        case .hlsDecryptionFailed: return "视频下载失败，该资源可能已过期或使用了不支持的保护格式。"
        case let .hlsSegmentFailed(index): return "第 \(index) 个视频片段下载失败，请重试。"
        case .hlsMergeFailed: return "视频已下载，但保存最终文件失败，请检查存储空间。"
        case .hlsFinalizationFailed: return "视频已下载，但保存最终文件失败，请重试。"
        }
    }
}

@MainActor
protocol DownloadManaging: AnyObject {
    var tasks: [DownloadTaskModel] { get }
    var onTasksChanged: (() -> Void)? { get set }

    func reloadTasks() async
    func pauseTask(id: UUID) async throws
    func resumeTask(id: UUID) async throws
    func restartTaskFromBeginning(id: UUID) async throws
    func cancelTask(id: UUID) async throws
    func retryTask(id: UUID) async throws
    func deleteTask(id: UUID, deleteFile: Bool) async throws
    func fileURL(for taskID: UUID) -> URL?
}
