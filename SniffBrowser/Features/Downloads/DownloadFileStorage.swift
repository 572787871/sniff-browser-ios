import Foundation

struct StoredDownloadFile: Sendable {
    let relativePath: String
    let fileURL: URL
    let byteCount: Int64?
}

final class DownloadFileStorage {
    let documentsURL: URL
    let applicationSupportURL: URL

    init(
        fileManager: FileManager = .default,
        documentsURL: URL? = nil,
        applicationSupportURL: URL? = nil
    ) {
        self.documentsURL = documentsURL ?? fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        self.applicationSupportURL = applicationSupportURL ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        try? fileManager.createDirectory(
            at: downloadsRootURL,
            withIntermediateDirectories: true
        )
        try? fileManager.createDirectory(
            at: resumeDataRootURL,
            withIntermediateDirectories: true
        )
    }

    var downloadsRootURL: URL {
        documentsURL.appendingPathComponent("Downloads", isDirectory: true)
    }

    var resumeDataRootURL: URL {
        applicationSupportURL
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent("ResumeData", isDirectory: true)
    }

    func storeDownloadedFile(
        from temporaryURL: URL,
        preferredFileName: String,
        resourceType: ResourceType
    ) throws -> StoredDownloadFile {
        let directory = try categoryDirectory(for: resourceType)
        let fileName = FileNameSanitizer.sanitize(preferredFileName)
        let destination = uniqueDestination(in: directory, fileName: fileName)
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
        } catch {
            // Background URLSession may place its temporary file on a different
            // APFS volume. A cross-volume move fails even though the download is
            // complete, so fall back to a copy before the delegate returns.
            do {
                try FileManager.default.copyItem(at: temporaryURL, to: destination)
                try? FileManager.default.removeItem(at: temporaryURL)
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw DownloadCenterError.fileOperationFailed
            }
        }
        return storedFile(for: destination)
    }

    func storeHLSAssetPackage(
        from temporaryURL: URL,
        preferredFileName: String
    ) throws -> StoredDownloadFile {
        // AVAssetDownloadURLSession owns the asset package. Moving or rewriting it
        // can invalidate its internal references, so keep the system location and
        // persist only a sandbox-relative reference.
        guard FileManager.default.fileExists(atPath: temporaryURL.path) else {
            throw DownloadCenterError.fileOperationFailed
        }
        return try storedFile(forContainerURL: temporaryURL)
    }

    func saveResumeData(_ data: Data, taskID: UUID) throws -> String {
        let url = resumeDataRootURL.appendingPathComponent("\(taskID.uuidString).resume")
        try data.write(to: url, options: .atomic)
        return relativeApplicationSupportPath(for: url)
    }

    func loadResumeData(relativePath: String?) -> Data? {
        guard let relativePath,
              let url = applicationSupportFileURL(relativePath: relativePath)
        else { return nil }
        return try? Data(contentsOf: url)
    }

    func removeResumeData(relativePath: String?) {
        guard let relativePath,
              let url = applicationSupportFileURL(relativePath: relativePath)
        else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func fileURL(relativePath: String?) -> URL? {
        guard let relativePath,
              !relativePath.contains(".."),
              !relativePath.hasPrefix("/")
        else { return nil }
        let url: URL
        let allowedRoot: URL
        if relativePath.hasPrefix("Container/") {
            let suffix = String(relativePath.dropFirst("Container/".count))
            allowedRoot = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            url = allowedRoot.appendingPathComponent(suffix)
        } else {
            allowedRoot = documentsURL
            url = documentsURL.appendingPathComponent(relativePath)
        }
        guard url.standardizedFileURL.path.hasPrefix(
            allowedRoot.standardizedFileURL.path + "/"
        ), FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    func removeFile(relativePath: String?) throws {
        guard let url = fileURL(relativePath: relativePath) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func renameFile(
        relativePath: String?,
        preferredFileName: String
    ) throws -> StoredDownloadFile {
        guard let source = fileURL(relativePath: relativePath) else {
            throw DownloadCenterError.fileOperationFailed
        }
        // System-managed AVAsset packages must remain at the URL supplied by
        // AVFoundation. Their display name is maintained in task metadata.
        if relativePath?.hasPrefix("Container/") == true {
            return try storedFile(forContainerURL: source)
        }
        let safeName = FileNameSanitizer.sanitize(preferredFileName)
        guard !safeName.isEmpty else { throw DownloadCenterError.fileOperationFailed }
        let destination = uniqueDestination(
            in: source.deletingLastPathComponent(),
            fileName: safeName
        )
        try FileManager.default.moveItem(at: source, to: destination)
        return storedFile(for: destination)
    }

    private func categoryDirectory(for type: ResourceType) throws -> URL {
        let name: String
        switch type {
        case .video: name = "Videos"
        case .audio: name = "Audio"
        case .image: name = "Images"
        case .document: name = "Documents"
        case .subtitle: name = "Subtitles"
        case .archive: name = "Archives"
        case .hls: name = "Videos"
        case .other: name = "Other"
        }
        let url = downloadsRootURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func uniqueDestination(in directory: URL, fileName: String) -> URL {
        let safeName = fileName.isEmpty ? "download" : fileName
        let extensionName = (safeName as NSString).pathExtension
        let baseName = (safeName as NSString).deletingPathExtension
        var candidate = directory.appendingPathComponent(safeName)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let suffix = extensionName.isEmpty
                ? "\(baseName) \(index)"
                : "\(baseName) \(index).\(extensionName)"
            candidate = directory.appendingPathComponent(suffix)
            index += 1
        }
        return candidate
    }

    private func storedFile(for url: URL) -> StoredDownloadFile {
        let relative = url.path.replacingOccurrences(
            of: documentsURL.path + "/",
            with: ""
        )
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            .map(Int64.init)
        return StoredDownloadFile(relativePath: relative, fileURL: url, byteCount: size)
    }

    private func storedFile(forContainerURL url: URL) throws -> StoredDownloadFile {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .standardizedFileURL.path
        let standardized = url.standardizedFileURL.path
        guard standardized.hasPrefix(home + "/") else {
            throw DownloadCenterError.fileOperationFailed
        }
        let suffix = String(standardized.dropFirst(home.count + 1))
        let size = recursiveByteCount(at: url)
        return StoredDownloadFile(
            relativePath: "Container/\(suffix)",
            fileURL: url,
            byteCount: size
        )
    }

    private func recursiveByteCount(at url: URL) -> Int64? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        if let values = try? url.resourceValues(forKeys: keys),
           values.isRegularFile == true {
            return Int64(values.fileSize ?? 0)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: nil
        ) else { return nil }
        var total: Int64 = 0
        var foundFile = false
        for case let childURL as URL in enumerator {
            guard let values = try? childURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true
            else { continue }
            total += Int64(values.fileSize ?? 0)
            foundFile = true
        }
        return foundFile ? total : nil
    }

    private func relativeApplicationSupportPath(for url: URL) -> String {
        url.path.replacingOccurrences(
            of: applicationSupportURL.path + "/",
            with: ""
        )
    }

    private func applicationSupportFileURL(relativePath: String) -> URL? {
        guard !relativePath.contains(".."), !relativePath.hasPrefix("/") else {
            return nil
        }
        let url = applicationSupportURL.appendingPathComponent(relativePath)
        guard url.standardizedFileURL.path.hasPrefix(
            applicationSupportURL.standardizedFileURL.path + "/"
        ) else { return nil }
        return url
    }
}
