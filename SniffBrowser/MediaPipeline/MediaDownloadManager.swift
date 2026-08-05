import Foundation

/// 统一下载入口：下载模块只面向 MediaDownloadManager，
/// 媒体后处理统一由 Media Pipeline 负责，下载侧不直接调用 FFmpeg。
@MainActor
final class MediaDownloadManager: DownloadManaging {
    static let shared = MediaDownloadManager()

    private let center = DownloadCenter.shared

    var tasks: [DownloadTaskModel] {
        center.tasks
    }

    var onTasksChanged: (() -> Void)? {
        get { center.onTasksChanged }
        set { center.onTasksChanged = newValue }
    }

    func reloadTasks() async {
        await center.reloadTasks()
    }

    func createDownload(
        resource: DetectedResource,
        context: DownloadRequestContext
    ) async throws -> DownloadCreationResult {
        try await center.createDownload(resource: resource, context: context)
    }

    func pauseTask(id: UUID) async throws {
        try await center.pauseTask(id: id)
    }

    func resumeTask(id: UUID) async throws {
        try await center.resumeTask(id: id)
    }

    func restartTaskFromBeginning(id: UUID) async throws {
        try await center.restartTaskFromBeginning(id: id)
    }

    func cancelTask(id: UUID) async throws {
        try await center.cancelTask(id: id)
    }

    func retryTask(id: UUID) async throws {
        try await center.retryTask(id: id)
    }

    func deleteTask(id: UUID, deleteFile: Bool) async throws {
        try await center.deleteTask(id: id, deleteFile: deleteFile)
    }

    func fileURL(for taskID: UUID) -> URL? {
        center.fileURL(for: taskID)
    }
}
