import Foundation

enum DownloadState: String, Codable, CaseIterable, Sendable {
    case waiting
    case downloading
    case paused
    case completed
    case failed
    case cancelled

    var localizedTitle: String {
        switch self {
        case .waiting: return "等待中"
        case .downloading: return "下载中"
        case .paused: return "已暂停"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }
}

struct DownloadTaskModel: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let sourceURL: URL
    var fileName: String
    var state: DownloadState
    var expectedSize: Int64?
    var downloadedSize: Int64
    var createdAt: Date
    var updatedAt: Date
    var destinationRelativePath: String?
    var errorDescription: String?

    var progress: Double? {
        guard let expectedSize, expectedSize > 0 else { return nil }
        return min(max(Double(downloadedSize) / Double(expectedSize), 0), 1)
    }

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        fileName: String,
        state: DownloadState = .waiting,
        expectedSize: Int64? = nil,
        downloadedSize: Int64 = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        destinationRelativePath: String? = nil,
        errorDescription: String? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.fileName = fileName
        self.state = state
        self.expectedSize = expectedSize
        self.downloadedSize = downloadedSize
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.destinationRelativePath = destinationRelativePath
        self.errorDescription = errorDescription
    }
}

@MainActor
protocol DownloadManaging: AnyObject {
    var tasks: [DownloadTaskModel] { get }

    func reloadTasks() async
    func pauseTask(id: UUID) async throws
    func resumeTask(id: UUID) async throws
    func cancelTask(id: UUID) async throws
    func retryTask(id: UUID) async throws
}
