import Foundation

actor DownloadRepository {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let defaultDirectory = applicationSupport.appendingPathComponent(
            "Downloads",
            isDirectory: true
        )
        let resolvedURL = fileURL
            ?? defaultDirectory.appendingPathComponent("tasks.json")
        let directory = resolvedURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        self.fileURL = resolvedURL
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> [DownloadTaskModel] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        return try decoder.decode(
            [DownloadTaskModel].self,
            from: Data(contentsOf: fileURL)
        )
    }

    func save(_ tasks: [DownloadTaskModel]) throws {
        try encoder.encode(tasks).write(to: fileURL, options: .atomic)
    }
}
