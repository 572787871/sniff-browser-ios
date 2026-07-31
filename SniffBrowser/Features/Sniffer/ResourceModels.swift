import Foundation

enum ResourceType: String, CaseIterable, Codable, Sendable {
    case video
    case audio
    case hls
    case image
    case document
    case archive
    case other

    var localizedTitle: String {
        switch self {
        case .video: return "视频"
        case .audio: return "音频"
        case .hls: return "HLS"
        case .image: return "图片"
        case .document: return "文档"
        case .archive: return "压缩包"
        case .other: return "其他"
        }
    }
}

struct DetectedResource: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let originalURL: URL?
    let fileName: String
    let mimeType: String?
    let resourceType: ResourceType
    let estimatedSize: Int64?
    let sourcePageURL: URL?
    let detectedAt: Date

    init(
        id: UUID = UUID(),
        url: URL,
        originalURL: URL? = nil,
        fileName: String,
        mimeType: String? = nil,
        resourceType: ResourceType,
        estimatedSize: Int64? = nil,
        sourcePageURL: URL? = nil,
        detectedAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.originalURL = originalURL
        self.fileName = fileName
        self.mimeType = mimeType
        self.resourceType = resourceType
        self.estimatedSize = estimatedSize
        self.sourcePageURL = sourcePageURL
        self.detectedAt = detectedAt
    }
}

@MainActor
protocol ResourceSniffingService: AnyObject {
    func scanResources(
        forPageURL pageURL: URL?,
        pageTitle: String?
    ) async throws -> [DetectedResource]

    func resetResources(forPageURL pageURL: URL?)
}
