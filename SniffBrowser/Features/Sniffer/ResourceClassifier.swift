import Foundation

struct ResourceClassifier: Sendable {
    private static let standaloneFragmentExtensions: Set<String> = [
        "m4s", "cmfv", "cmfa", "ts"
    ]
    private static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "webm", "mpeg", "mpg", "mkv"
    ]
    private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus"
    ]
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "avif", "svg"
    ]
    private static let documentExtensions: Set<String> = [
        "pdf", "txt", "epub", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
        "json", "xml"
    ]
    private static let subtitleExtensions: Set<String> = ["vtt", "srt", "ass"]
    private static let archiveExtensions: Set<String> = [
        "zip", "rar", "7z", "tar", "gz"
    ]

    func classify(
        mimeType: String?,
        url: URL,
        elementType: String?
    ) -> ResourceType? {
        let mime = normalizedMIME(mimeType)
        if isHLS(mime: mime, fileExtension: url.pathExtension) {
            return .hls
        }
        if mime.hasPrefix("video/") {
            return .video
        }
        if mime.hasPrefix("audio/") {
            return .audio
        }
        if mime == "text/vtt" || mime == "application/subrip" {
            return .subtitle
        }
        if mime.hasPrefix("image/") {
            return .image
        }
        if isDocumentMIME(mime) {
            return .document
        }
        if isArchiveMIME(mime) {
            return .archive
        }

        let fileExtension = inferredExtension(from: url)
        if fileExtension == "m3u8" {
            return .hls
        }
        if Self.videoExtensions.contains(fileExtension) {
            return .video
        }
        if Self.audioExtensions.contains(fileExtension) {
            return .audio
        }
        if Self.subtitleExtensions.contains(fileExtension) {
            return .subtitle
        }
        if Self.imageExtensions.contains(fileExtension) {
            return .image
        }
        if Self.documentExtensions.contains(fileExtension) {
            return .document
        }
        if Self.archiveExtensions.contains(fileExtension) {
            return .archive
        }

        let element = elementType?.lowercased() ?? ""
        if ["video", "source-video"].contains(element) {
            return .video
        }
        if ["audio", "source-audio"].contains(element) {
            return .audio
        }
        if element == "track" {
            return .subtitle
        }
        if element == "img" || element == "image" {
            return .image
        }
        if mime == "application/octet-stream" {
            return .other
        }
        return nil
    }

    func makeResource(
        from candidate: ResourceCandidate,
        tabID: UUID,
        now: Date = Date()
    ) -> DetectedResource? {
        guard let rawURL = URL(string: candidate.originalURLString),
              let canonicalURL = ResourceDeduplicator.canonicalURL(for: rawURL),
              let type = classify(
                mimeType: candidate.mimeType,
                url: canonicalURL,
                elementType: candidate.elementType
              ),
              shouldDisplay(type: type, candidate: candidate, url: canonicalURL)
        else {
            return nil
        }

        let fileExtension = inferredExtension(from: canonicalURL)
        let scheme = canonicalURL.scheme?.lowercased()
        let rawName = canonicalURL.lastPathComponent
            .removingPercentEncoding ?? canonicalURL.lastPathComponent
        let fallbackName = type.localizedTitle + (fileExtension.isEmpty
            ? ""
            : ".\(fileExtension)")
        let inferredName = rawName.isEmpty
            ? fallbackName
            : (canonicalURL.pathExtension.isEmpty && !fileExtension.isEmpty
                ? "\(rawName).\(fileExtension)"
                : rawName)
        let displayName: String
        if type == .hls, Self.isGenericHLSName(inferredName) {
            let title = HLSResourceMetadataResolver.readableTitle(
                pageTitle: candidate.pageTitle,
                existingName: inferredName
            )
            displayName = "\(title).m3u8"
        } else {
            displayName = inferredName
        }
        let fileName = scheme == "blob" || scheme == "data"
            ? fallbackName
            : FileNameSanitizer.sanitize(displayName)
        let isBlob = scheme == "blob"
        let isFile = scheme == "file"
        let isData = scheme == "data"
        let limitation: String?
        if isBlob {
            limitation = "Blob 地址仅在当前网页会话中有效，暂不能直接下载。"
        } else if isData {
            limitation = "内联图片仅在当前页面会话中可预览。"
        } else if isFile {
            limitation = "本地网页资源受 App 沙盒权限限制。"
        } else {
            limitation = nil
        }

        return DetectedResource(
            canonicalURL: canonicalURL,
            originalURLString: candidate.originalURLString,
            sourcePageURL: candidate.pageURLString.flatMap(URL.init(string:)),
            sourcePageTitle: candidate.pageTitle,
            fileName: fileName,
            fileExtension: fileExtension.isEmpty ? nil : fileExtension,
            mimeType: normalizedMIME(candidate.mimeType).nilIfEmpty,
            resourceType: type,
            // Content-Length for HLS is only the playlist text (often a few
            // KB), not the size of the video segments. Keep it unknown until
            // the system offline asset has completed and can be measured.
            estimatedSize: type == .hls ? nil : candidate.estimatedSize,
            duration: candidate.duration,
            width: candidate.width,
            height: candidate.height,
            bitrate: candidate.bitrate,
            thumbnailURL: candidate.thumbnailURLString.flatMap(URL.init(string:)),
            detectionSource: candidate.detectionSource,
            detectedAt: now,
            lastSeenAt: now,
            tabID: tabID,
            headersHint: candidate.headersHint,
            isPotentiallyDownloadable: !isBlob && !isFile && !isData,
            limitationReason: limitation
        )
    }

    private func shouldDisplay(
        type: ResourceType,
        candidate: ResourceCandidate,
        url: URL
    ) -> Bool {
        // A blob URL is a page-local playback handle, not a requestable media
        // file. The scanner separately discovers the backing MP4/HLS URL; do
        // not present this unusable duplicate as the first video result.
        if url.scheme?.lowercased() == "blob", type != .image {
            return false
        }
        // HLS/DASH media fragments are implementation details of a stream, not
        // independently playable videos. Keeping them would bury the actual
        // MP4/HLS entry and invite downloads that can never form a full video.
        if Self.standaloneFragmentExtensions.contains(inferredExtension(from: url)) {
            return false
        }
        // The main document can be reported as a video by players that attach
        // a video MIME hint to their page URL (for example view_video.php).
        // It is still HTML, not a downloadable media response.
        if [.video, .audio].contains(type),
           let pageURL = candidate.pageURLString.flatMap(URL.init(string:)),
           ResourceDeduplicator.canonicalURL(for: pageURL)
            == ResourceDeduplicator.canonicalURL(for: url),
           Self.looksLikeHTMLDocument(pageURL) {
            return false
        }
        if type == .image {
            if let width = candidate.width, let height = candidate.height,
               width <= 2, height <= 2 {
                return false
            }
            let path = url.path.lowercased()
            if path.contains("favicon") || path.contains("apple-touch-icon") {
                return false
            }
        }
        return !looksLikeTrackingResource(url)
    }

    private func looksLikeTrackingResource(_ url: URL) -> Bool {
        let value = "\(url.host ?? "")\(url.path)".lowercased()
        return [
            "/pixel", "tracking", "analytics", "doubleclick", "/beacon"
        ].contains { value.contains($0) }
    }

    private static func isGenericHLSName(_ name: String) -> Bool {
        let base = (name as NSString).deletingPathExtension.lowercased()
        return ["master", "index", "playlist", "video", "stream", "hls"]
            .contains(base)
    }

    private static func looksLikeHTMLDocument(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        return fileExtension.isEmpty
            || ["html", "htm", "php", "asp", "aspx", "jsp"]
                .contains(fileExtension)
    }

    private func normalizedMIME(_ value: String?) -> String {
        value?
            .split(separator: ";", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private func isHLS(mime: String, fileExtension: String) -> Bool {
        fileExtension.lowercased() == "m3u8"
            || mime == "application/vnd.apple.mpegurl"
            || mime == "application/x-mpegurl"
            || mime == "audio/mpegurl"
    }

    private func isDocumentMIME(_ mime: String) -> Bool {
        mime == "application/pdf"
            || mime == "text/plain"
            || mime == "application/epub+zip"
            || mime.contains("wordprocessingml")
            || mime.contains("spreadsheetml")
            || mime.contains("presentationml")
            || mime == "application/json"
            || mime == "text/xml"
            || mime == "application/xml"
    }

    private func isArchiveMIME(_ mime: String) -> Bool {
        mime == "application/zip"
            || mime == "application/x-rar-compressed"
            || mime == "application/x-7z-compressed"
            || mime == "application/gzip"
            || mime == "application/x-tar"
    }

    private func inferredExtension(from url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        if !pathExtension.isEmpty {
            return pathExtension
        }
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return ""
        }
        let formatNames = ["format", "ext", "type", "container"]
        for item in components.queryItems ?? []
        where formatNames.contains(item.name.lowercased()) {
            let candidate = item.value?.lowercased() ?? ""
            if candidate.range(
                of: #"^[a-z0-9]{2,8}$"#,
                options: .regularExpression
            ) != nil {
                return candidate
            }
        }
        return ""
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
