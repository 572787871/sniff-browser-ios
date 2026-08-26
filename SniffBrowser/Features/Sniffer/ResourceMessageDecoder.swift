import Foundation

struct ResourceMessageDecoder: Sendable {
    static let maximumBatchCount = 500
    static let maximumURLLength = 8_192
    private static let maximumInlineImageURLLength = 1_500_000
    private static let maximumInlineThumbnailURLLength = 180_000
    private static let maximumTextLength = 1_024

    enum DecodeError: Error, Equatable {
        case malformedMessage
        case unsupportedKind
    }

    func decode(_ data: Data) throws -> ResourceMessageBatch {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawKind = boundedString(root["kind"], maximum: 32),
              let kind = ResourceMessageBatch.Kind(rawValue: rawKind)
        else {
            throw DecodeError.malformedMessage
        }

        let pageURL = boundedString(
            root["pageURL"],
            maximum: Self.maximumURLLength
        )
        let pageTitle = boundedString(
            root["pageTitle"],
            maximum: Self.maximumTextLength
        )
        let scanID = boundedString(root["scanID"], maximum: 64)
            .flatMap(UUID.init(uuidString:))

        if kind != .batch {
            return ResourceMessageBatch(
                kind: kind,
                scanID: scanID,
                pageURLString: pageURL,
                pageTitle: pageTitle,
                candidates: []
            )
        }

        let rawValues = root["candidates"] as? [[String: Any]] ?? []
        let values = rawValues.prefix(Self.maximumBatchCount)
        let candidates = values.compactMap {
            decodeCandidate($0, pageURL: pageURL, pageTitle: pageTitle)
        }
        return ResourceMessageBatch(
            kind: kind,
            scanID: scanID,
            pageURLString: pageURL,
            pageTitle: pageTitle,
            candidates: candidates
        )
    }

    private func decodeCandidate(
        _ value: [String: Any],
        pageURL: String?,
        pageTitle: String?
    ) -> ResourceCandidate? {
        guard let rawURL = value["url"] as? String,
              !rawURL.isEmpty else {
            return nil
        }
        let maxURLLength = rawURL.lowercased().hasPrefix("data:image/")
            ? Self.maximumInlineImageURLLength
            : Self.maximumURLLength
        guard rawURL.utf16.count <= maxURLLength,
              isAllowed(rawURL, pageURL: pageURL) else {
            return nil
        }
        let source = boundedString(value["source"], maximum: 64)
            .flatMap(DetectionSource.init(rawValue:)) ?? .dom
        let headers = safeHeaders(value["headers"] as? [String: Any])

        return ResourceCandidate(
            originalURLString: rawURL,
            pageURLString: pageURL,
            pageTitle: pageTitle,
            mimeType: boundedString(value["mimeType"], maximum: 256),
            estimatedSize: positiveInt64(value["estimatedSize"])
                ?? positiveInt64(value["contentLength"]),
            duration: positiveDouble(value["duration"]),
            width: positiveInt(value["width"]),
            height: positiveInt(value["height"]),
            bitrate: positiveInt(value["bitrate"]),
            thumbnailURLString: allowedThumbnailURL(
                value["thumbnailURL"],
                pageURL: pageURL
            ),
            detectionSource: source,
            elementType: boundedString(value["elementType"], maximum: 64),
            headersHint: headers
        )
    }

    private func allowedThumbnailURL(_ value: Any?, pageURL: String?) -> String? {
        guard let rawValue = value as? String else { return nil }
        let isInlineImage = rawValue.lowercased().hasPrefix("data:image/")
        let maximumLength = isInlineImage
            ? Self.maximumInlineThumbnailURLLength
            : Self.maximumURLLength
        guard let rawURL = boundedString(value, maximum: maximumLength),
              isAllowed(rawURL, pageURL: pageURL),
              let scheme = URL(string: rawURL)?.scheme?.lowercased(),
              ["http", "https", "data"].contains(scheme)
        else { return nil }
        return rawURL
    }

    private func isAllowed(_ rawURL: String, pageURL: String?) -> Bool {
        guard !rawURL.isEmpty, let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased()
        else {
            return false
        }
        if ["javascript", "about"].contains(scheme) {
            return false
        }
        if scheme == "data" {
            // Only image data URLs are accepted, and the outer message size
            // limit still bounds the amount of inline data we retain.
            return rawURL.lowercased().hasPrefix("data:image/")
        }
        if ["http", "https", "blob"].contains(scheme) {
            return true
        }
        if scheme == "file" {
            return pageURL.flatMap(URL.init(string:))?.scheme == "file"
        }
        return false
    }

    private func safeHeaders(_ raw: [String: Any]?) -> [String: String] {
        guard let raw else { return [:] }
        let allowed = ["content-type", "content-length", "accept-ranges"]
        var result: [String: String] = [:]
        for (key, value) in raw {
            let normalized = key.lowercased()
            guard allowed.contains(normalized),
                  let text = boundedString(value, maximum: 256)
            else {
                continue
            }
            result[normalized] = text
        }
        return result
    }

    private func boundedString(_ value: Any?, maximum: Int) -> String? {
        guard let string = value as? String,
              !string.isEmpty,
              string.utf16.count <= maximum
        else {
            return nil
        }
        return string
    }

    private func positiveInt(_ value: Any?) -> Int? {
        let number = value as? NSNumber
        guard let result = number?.intValue, result > 0 else { return nil }
        return result
    }

    private func positiveInt64(_ value: Any?) -> Int64? {
        let number = value as? NSNumber
        guard let result = number?.int64Value, result > 0 else { return nil }
        return result
    }

    private func positiveDouble(_ value: Any?) -> Double? {
        let number = value as? NSNumber
        guard let result = number?.doubleValue,
              result.isFinite, result > 0
        else {
            return nil
        }
        return result
    }
}
