import Foundation

struct ResourceDeduplicator: Sendable {
    private static let removableTrackingNames: Set<String> = [
        "fbclid", "gclid", "dclid", "msclkid"
    ]

    static func canonicalURL(for url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https", "blob", "file"].contains(scheme)
        else {
            return nil
        }
        if scheme == "blob" || scheme == "file" {
            var components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            )
            components?.fragment = nil
            return components?.url ?? url
        }

        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        components.scheme = scheme
        components.host = components.host?.lowercased()
        components.fragment = nil
        if (scheme == "https" && components.port == 443)
            || (scheme == "http" && components.port == 80) {
            components.port = nil
        }
        components.percentEncodedQuery = filteredPercentEncodedQuery(
            components.percentEncodedQuery
        )
        return components.url
    }

    private static func filteredPercentEncodedQuery(_ query: String?) -> String? {
        guard let query, !query.isEmpty else { return nil }
        let retained = query.split(
            separator: "&",
            omittingEmptySubsequences: false
        ).filter { item in
            let encodedName = item.split(
                separator: "=",
                maxSplits: 1,
                omittingEmptySubsequences: false
            ).first.map(String.init) ?? ""
            let name = encodedName.removingPercentEncoding?
                .lowercased() ?? encodedName.lowercased()
            return !name.hasPrefix("utm_")
                && !Self.removableTrackingNames.contains(name)
        }
        let result = retained.joined(separator: "&")
        return result.isEmpty ? nil : result
    }

    func merge(
        existing: DetectedResource,
        incoming: DetectedResource
    ) -> DetectedResource {
        let preferredSource: DetectionSource
        if incoming.detectionSource.confidence > existing.detectionSource.confidence {
            preferredSource = incoming.detectionSource
        } else {
            preferredSource = existing.detectionSource
        }
        let preferredType: ResourceType
        if incoming.resourceType.sortPriority < existing.resourceType.sortPriority {
            preferredType = incoming.resourceType
        } else {
            preferredType = existing.resourceType
        }

        return DetectedResource(
            id: existing.id,
            canonicalURL: existing.canonicalURL,
            originalURLString: preferredOriginalURL(
                existing: existing,
                incoming: incoming
            ),
            sourcePageURL: incoming.sourcePageURL ?? existing.sourcePageURL,
            sourcePageTitle: nonEmpty(incoming.sourcePageTitle)
                ?? existing.sourcePageTitle,
            fileName: preferredFileName(existing: existing, incoming: incoming),
            fileExtension: incoming.fileExtension ?? existing.fileExtension,
            mimeType: incoming.mimeType ?? existing.mimeType,
            resourceType: preferredType,
            estimatedSize: maximum(existing.estimatedSize, incoming.estimatedSize),
            duration: maximum(existing.duration, incoming.duration),
            width: maximum(existing.width, incoming.width),
            height: maximum(existing.height, incoming.height),
            bitrate: maximum(existing.bitrate, incoming.bitrate),
            thumbnailURL: incoming.thumbnailURL ?? existing.thumbnailURL,
            detectionSource: preferredSource,
            detectedAt: min(existing.detectedAt, incoming.detectedAt),
            lastSeenAt: max(existing.lastSeenAt, incoming.lastSeenAt),
            tabID: existing.tabID,
            headersHint: existing.headersHint.merging(
                incoming.headersHint,
                uniquingKeysWith: { _, new in new }
            ),
            isPotentiallyDownloadable: existing.isPotentiallyDownloadable
                || incoming.isPotentiallyDownloadable,
            limitationReason: incoming.limitationReason
                ?? existing.limitationReason
        )
    }

    private func preferredOriginalURL(
        existing: DetectedResource,
        incoming: DetectedResource
    ) -> String {
        incoming.originalURLString.count >= existing.originalURLString.count
            ? incoming.originalURLString
            : existing.originalURLString
    }

    private func preferredFileName(
        existing: DetectedResource,
        incoming: DetectedResource
    ) -> String {
        if existing.resourceType == .hls,
           incoming.resourceType == .hls,
           let quality = HLSQualityLabel.make(
            width: incoming.width,
            height: incoming.height,
            bitrate: incoming.bitrate
           ),
           !existing.fileName.localizedCaseInsensitiveContains(quality) {
            return incoming.fileName
        }
        if existing.fileName == "未命名文件"
            || (isGenericHLSName(existing.fileName)
                && !isGenericHLSName(incoming.fileName)) {
            return incoming.fileName
        }
        return existing.fileName
    }

    private func isGenericHLSName(_ name: String) -> Bool {
        let base = (name as NSString).deletingPathExtension.lowercased()
        return ["master", "index", "playlist", "video", "stream", "hls"]
            .contains(base)
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func maximum<T: Comparable>(_ first: T?, _ second: T?) -> T? {
        switch (first, second) {
        case let (.some(lhs), .some(rhs)): return max(lhs, rhs)
        case let (.some(value), .none), let (.none, .some(value)): return value
        case (.none, .none): return nil
        }
    }
}
