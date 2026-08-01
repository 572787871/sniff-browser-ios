import Foundation

struct ResourceCandidate: Equatable, Sendable {
    let originalURLString: String
    let pageURLString: String?
    let pageTitle: String?
    let mimeType: String?
    let estimatedSize: Int64?
    let duration: Double?
    let width: Int?
    let height: Int?
    let bitrate: Int?
    let thumbnailURLString: String?
    let detectionSource: DetectionSource
    let elementType: String?
    let headersHint: [String: String]
}

struct ResourceMessageBatch: Equatable, Sendable {
    enum Kind: String, Sendable {
        case batch
        case scanComplete
        case scriptReady
        case scanFailed
    }

    let kind: Kind
    let scanID: UUID?
    let pageURLString: String?
    let pageTitle: String?
    let candidates: [ResourceCandidate]
}
