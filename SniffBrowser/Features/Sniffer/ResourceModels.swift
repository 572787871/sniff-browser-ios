import Foundation

enum ResourceType: String, CaseIterable, Codable, Sendable {
    case video
    case audio
    case hls
    case image
    case document
    case subtitle
    case archive
    case other

    var localizedTitle: String {
        switch self {
        case .video: return "视频"
        case .audio: return "音频"
        case .hls: return "HLS"
        case .image: return "图片"
        case .document: return "文档"
        case .subtitle: return "字幕"
        case .archive: return "压缩包"
        case .other: return "其他"
        }
    }

    var sortPriority: Int {
        switch self {
        case .video: return 0
        case .hls: return 1
        case .audio: return 2
        case .subtitle: return 3
        case .document: return 4
        case .image: return 5
        case .archive: return 6
        case .other: return 7
        }
    }
}

enum DetectionSource: String, Codable, CaseIterable, Sendable {
    case dom
    case mutationObserver
    case performance
    case fetch
    case xhr
    case mediaEvent
    case navigationResponse
    case manualScan

    var confidence: Int {
        switch self {
        case .navigationResponse: return 8
        case .mediaEvent: return 7
        case .fetch, .xhr: return 6
        case .dom, .mutationObserver: return 5
        case .manualScan: return 4
        case .performance: return 3
        }
    }
}

enum ResourceScanState: String, Codable, Equatable, Sendable {
    case idle
    case installing
    case scanning
    case completed
    case failed

    var localizedTitle: String {
        switch self {
        case .idle: return "等待扫描"
        case .completed: return "扫描完成"
        case .installing: return "正在准备扫描"
        case .scanning: return "正在扫描"
        case .failed: return "扫描失败"
        }
    }
}

enum SniffingActivationState: String, Codable, Equatable, Sendable {
    case disabled
    case starting
    case active
    case stopping
    case failed

    var isEnabled: Bool {
        self == .starting || self == .active
    }
}

struct DetectedResource: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let canonicalURL: URL
    let originalURLString: String
    let sourcePageURL: URL?
    let sourcePageTitle: String?
    let fileName: String
    let fileExtension: String?
    let mimeType: String?
    let resourceType: ResourceType
    let estimatedSize: Int64?
    let duration: Double?
    let width: Int?
    let height: Int?
    let bitrate: Int?
    let detectionSource: DetectionSource
    let detectedAt: Date
    let lastSeenAt: Date
    let tabID: UUID
    let headersHint: [String: String]
    let isPotentiallyDownloadable: Bool
    let limitationReason: String?

    var url: URL { canonicalURL }

    init(
        id: UUID = UUID(),
        canonicalURL: URL,
        originalURLString: String,
        sourcePageURL: URL? = nil,
        sourcePageTitle: String? = nil,
        fileName: String,
        fileExtension: String? = nil,
        mimeType: String? = nil,
        resourceType: ResourceType,
        estimatedSize: Int64? = nil,
        duration: Double? = nil,
        width: Int? = nil,
        height: Int? = nil,
        bitrate: Int? = nil,
        detectionSource: DetectionSource,
        detectedAt: Date = Date(),
        lastSeenAt: Date = Date(),
        tabID: UUID,
        headersHint: [String: String] = [:],
        isPotentiallyDownloadable: Bool = true,
        limitationReason: String? = nil
    ) {
        self.id = id
        self.canonicalURL = canonicalURL
        self.originalURLString = originalURLString
        self.sourcePageURL = sourcePageURL
        self.sourcePageTitle = sourcePageTitle
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.mimeType = mimeType
        self.resourceType = resourceType
        self.estimatedSize = estimatedSize
        self.duration = duration
        self.width = width
        self.height = height
        self.bitrate = bitrate
        self.detectionSource = detectionSource
        self.detectedAt = detectedAt
        self.lastSeenAt = lastSeenAt
        self.tabID = tabID
        self.headersHint = headersHint
        self.isPotentiallyDownloadable = isPotentiallyDownloadable
        self.limitationReason = limitationReason
    }
}

struct TabResourceSnapshot: Equatable, Sendable {
    let tabID: UUID
    let resources: [DetectedResource]
    let scanState: ResourceScanState
    let lastScanAt: Date?
    let errorMessage: String?
    let activationState: SniffingActivationState
}

enum ResourceSniffingError: LocalizedError, Equatable {
    case tabUnavailable
    case webViewUnavailable
    case scriptUnavailable
    case scanTimedOut
    case scriptFailure

    var errorDescription: String? {
        switch self {
        case .tabUnavailable: return "当前标签页不可用。"
        case .webViewUnavailable: return "当前网页已休眠，请返回网页后重试。"
        case .scriptUnavailable: return "资源识别脚本尚未准备完成。"
        case .scanTimedOut: return "扫描等待超时，请确认网页已加载后重试。"
        case .scriptFailure: return "网页资源扫描失败。"
        }
    }
}

@MainActor
protocol ResourceSniffingService: AnyObject {
    func activationState(for tabID: UUID) -> SniffingActivationState
    func enableSniffing(for tabID: UUID) async throws
    func disableSniffing(for tabID: UUID) async
    func scanResources(for tabID: UUID) async throws -> [DetectedResource]
    func resources(for tabID: UUID) -> [DetectedResource]
    func resetResources(for tabID: UUID)
}
