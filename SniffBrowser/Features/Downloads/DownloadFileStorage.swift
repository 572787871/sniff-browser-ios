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
            at: resumeDataRootURL,
            withIntermediateDirectories: true
        )
    }

    /// 分类目录直接位于 Documents 根下（“文件”App 中不再出现多余的
    /// Downloads 包装层）。视频与媒体管线共用 Documents/Videos。
    var categoryRootURL: URL {
        documentsURL
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

    /// Stores a self-contained, decrypted VOD package. The package keeps the
    /// media fragments and a rewritten local playlist together so AVPlayer can
    /// consume the original codec without exposing a concatenated MPEG-TS file.
    func storeHLSVideoPackage(
        from workingDirectory: URL,
        preferredFileName: String
    ) throws -> StoredDownloadFile {
        guard FileManager.default.fileExists(
            atPath: workingDirectory.appendingPathComponent("index.m3u8").path
        ) else { throw DownloadCenterError.fileOperationFailed }
        let directory = try categoryDirectory(for: .video)
        let sanitized = FileNameSanitizer.sanitize(preferredFileName)
        let baseName = (sanitized as NSString).deletingPathExtension
        let packageName = "\(baseName.isEmpty ? "下载视频" : baseName).sniffhls"
        let destination = uniqueDestination(in: directory, fileName: packageName)
        do {
            try FileManager.default.moveItem(at: workingDirectory, to: destination)
        } catch {
            do {
                try FileManager.default.copyItem(at: workingDirectory, to: destination)
                try? FileManager.default.removeItem(at: workingDirectory)
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw DownloadCenterError.fileOperationFailed
            }
        }
        return storedFile(for: destination)
    }

    // MARK: - 旧布局迁移

    /// 把旧版 `Documents/Downloads/<分类>/*` 与 `Documents/Thumbnails/*`
    /// 迁移到新布局（分类直接放 Documents 根、缩略图移入 Application Support），
    /// 并删除空目录。幂等，可重复调用。
    func migrateLegacyLayoutIfNeeded() {
        let fileManager = FileManager.default
        let legacyDownloads = documentsURL.appendingPathComponent(
            "Downloads",
            isDirectory: true
        )
        if fileManager.fileExists(atPath: legacyDownloads.path) {
            for name in ["Videos", "Audio", "Images", "Documents",
                         "Subtitles", "Archives", "Other"] {
                let source = legacyDownloads.appendingPathComponent(
                    name,
                    isDirectory: true
                )
                guard fileManager.fileExists(atPath: source.path) else { continue }
                let destination = documentsURL.appendingPathComponent(
                    name,
                    isDirectory: true
                )
                try? fileManager.createDirectory(
                    at: destination,
                    withIntermediateDirectories: true
                )
                if let entries = try? fileManager.contentsOfDirectory(
                    atPath: source.path
                ) {
                    for entry in entries {
                        let from = source.appendingPathComponent(entry)
                        let to = destination.appendingPathComponent(entry)
                        if !fileManager.fileExists(atPath: to.path) {
                            try? fileManager.moveItem(at: from, to: to)
                        }
                    }
                }
                try? fileManager.removeItem(at: source)
            }
            try? fileManager.removeItem(at: legacyDownloads)
        }

        let legacyThumbnails = documentsURL.appendingPathComponent(
            "Thumbnails",
            isDirectory: true
        )
        if fileManager.fileExists(atPath: legacyThumbnails.path) {
            let destination = applicationSupportURL.appendingPathComponent(
                "Thumbnails",
                isDirectory: true
            )
            try? fileManager.createDirectory(
                at: destination,
                withIntermediateDirectories: true
            )
            if let entries = try? fileManager.contentsOfDirectory(
                atPath: legacyThumbnails.path
            ) {
                for entry in entries {
                    let from = legacyThumbnails.appendingPathComponent(entry)
                    let to = destination.appendingPathComponent(entry)
                    if !fileManager.fileExists(atPath: to.path) {
                        try? fileManager.moveItem(at: from, to: to)
                    }
                }
            }
            try? fileManager.removeItem(at: legacyThumbnails)
        }

    }

    /// 把旧版相对路径 `Downloads/Videos/x.mp4` 重写为 `Videos/x.mp4`。
    func migratedRelativePath(_ path: String) -> String {
        if path.hasPrefix("Downloads/") {
            return String(path.dropFirst("Downloads/".count))
        }
        return path
    }

    /// 把旧版缩略图路径 `Thumbnails/x.jpg` 重写为 `AppSupport/Thumbnails/x.jpg`。
    func migratedThumbnailPath(_ path: String?) -> String? {
        guard let path else { return nil }
        if path.hasPrefix("Thumbnails/") {
            return "AppSupport/\(path)"
        }
        return path
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
        } else if relativePath.hasPrefix("AppSupport/") {
            let suffix = String(relativePath.dropFirst("AppSupport/".count))
            allowedRoot = applicationSupportURL
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
        let url = categoryRootURL.appendingPathComponent(name, isDirectory: true)
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
        let size = recursiveByteCount(at: url)
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
