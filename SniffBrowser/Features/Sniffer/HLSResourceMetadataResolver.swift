import Foundation

struct HLSResolvedMetadata: Equatable, Sendable {
    let width: Int?
    let height: Int?
    let bitrate: Int?
    let duration: TimeInterval?

    var qualityLabel: String? {
        HLSQualityLabel.make(width: width, height: height, bitrate: bitrate)
    }
}

enum HLSQualityLabel {
    static func make(width: Int?, height: Int?, bitrate: Int?) -> String? {
        if let height, height > 0 {
            switch height {
            case 2_160...: return "4K"
            case 1_440...: return "1440p"
            default: return "\(height)p"
            }
        }
        if let width, width >= 3_840 { return "4K" }
        if let bitrate, bitrate > 0 {
            let megabits = Double(bitrate) / 1_000_000
            return megabits >= 1
                ? String(format: "%.1f Mbps", megabits)
                : "\(bitrate / 1_000) Kbps"
        }
        return nil
    }
}

/// Resolves the rendition that the downloader will actually select. This is
/// intentionally invoked only while the resource sheet is visible; it does
/// not add background polling or extra traffic to ordinary browsing.
struct HLSResourceMetadataResolver {
    private let parser = HLSPlaylistParser()

    func resolve(
        resource: DetectedResource,
        context: DownloadRequestContext
    ) async throws -> DetectedResource {
        var playlistURL = context.targetURL
        var selectedVariant: HLSVariant?
        var duration = resource.duration

        for _ in 0..<4 {
            try Task.checkCancellation()
            let fetched = try await fetchPlaylist(
                at: playlistURL,
                context: context
            )
            switch try parser.parse(fetched.text, sourceURL: fetched.finalURL) {
            case let .master(variants):
                guard let selected = variants.max(by: Self.isLowerQuality)
                else { throw DownloadCenterError.invalidHLSPlaylist }
                selectedVariant = selected
                playlistURL = selected.url
            case let .media(playlist):
                let measuredDuration = playlist.segments
                    .compactMap(\.duration)
                    .reduce(0, +)
                if measuredDuration > 0 { duration = measuredDuration }
                return enrichedResource(
                    resource,
                    metadata: HLSResolvedMetadata(
                        width: selectedVariant?.width
                            ?? Self.inferredResolution(from: playlistURL).width,
                        height: selectedVariant?.height
                            ?? Self.inferredResolution(from: playlistURL).height,
                        bitrate: selectedVariant?.bandwidth,
                        duration: duration
                    )
                )
            }
        }
        throw DownloadCenterError.invalidHLSPlaylist
    }

    private func fetchPlaylist(
        at url: URL,
        context: DownloadRequestContext
    ) async throws -> (text: String, finalURL: URL) {
        var request = context.makeRequest(for: url)
        request.timeoutInterval = 20
        request.setValue(
            "application/vnd.apple.mpegurl,application/x-mpegURL,text/plain,*/*;q=0.5",
            forHTTPHeaderField: "Accept"
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              data.count <= 5_000_000,
              let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1),
              text.contains("#EXTM3U")
        else { throw DownloadCenterError.invalidHLSPlaylist }
        return (text, response.url ?? url)
    }

    private func enrichedResource(
        _ resource: DetectedResource,
        metadata: HLSResolvedMetadata
    ) -> DetectedResource {
        let quality = metadata.qualityLabel
        let readableTitle = Self.readableTitle(
            pageTitle: resource.sourcePageTitle,
            existingName: resource.fileName
        )
        let fileName: String
        if let quality {
            fileName = FileNameSanitizer.sanitize(
                "\(readableTitle) - \(quality).m3u8"
            )
        } else {
            fileName = FileNameSanitizer.sanitize("\(readableTitle).m3u8")
        }
        let estimatedSize: Int64?
        if let bitrate = metadata.bitrate,
           let duration = metadata.duration,
           duration.isFinite,
           duration > 0 {
            estimatedSize = Int64((Double(bitrate) * duration / 8).rounded())
        } else {
            estimatedSize = nil
        }
        return DetectedResource(
            id: resource.id,
            canonicalURL: resource.canonicalURL,
            originalURLString: resource.originalURLString,
            sourcePageURL: resource.sourcePageURL,
            sourcePageTitle: resource.sourcePageTitle,
            fileName: fileName,
            fileExtension: "m3u8",
            mimeType: resource.mimeType,
            resourceType: .hls,
            estimatedSize: estimatedSize,
            duration: metadata.duration,
            width: metadata.width,
            height: metadata.height,
            bitrate: metadata.bitrate,
            thumbnailURL: resource.thumbnailURL,
            detectionSource: resource.detectionSource,
            detectedAt: resource.detectedAt,
            lastSeenAt: Date(),
            tabID: resource.tabID,
            headersHint: resource.headersHint,
            isPotentiallyDownloadable: resource.isPotentiallyDownloadable,
            limitationReason: resource.limitationReason
        )
    }

    static func readableTitle(pageTitle: String?, existingName: String) -> String {
        let genericNames: Set<String> = [
            "master", "index", "playlist", "video", "stream", "hls"
        ]
        let existingBase = (existingName as NSString)
            .deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !existingBase.isEmpty,
           !genericNames.contains(existingBase.lowercased()) {
            return existingBase
        }
        let title = pageTitle?
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "下载视频" : title
    }

    private static func isLowerQuality(_ lhs: HLSVariant, _ rhs: HLSVariant) -> Bool {
        let leftBitrate = lhs.bandwidth ?? 0
        let rightBitrate = rhs.bandwidth ?? 0
        if leftBitrate != rightBitrate { return leftBitrate < rightBitrate }
        return (lhs.height ?? 0) < (rhs.height ?? 0)
    }

    private static func inferredResolution(from url: URL) -> (width: Int?, height: Int?) {
        let value = url.absoluteString.lowercased()
        let patterns = [
            #"(?:^|[/_\-.=])(2160|1440|1080|720|576|540|480|360|240)p?(?:[/_\-.?&=]|$)"#,
            #"(?:^|[/_\-.=])(3840x2160|2560x1440|1920x1080|1280x720|854x480|640x360)(?:[/_\-.?&=]|$)"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(
                    in: value,
                    range: NSRange(value.startIndex..., in: value)
                  ),
                  let range = Range(match.range(at: 1), in: value)
            else { continue }
            let captured = String(value[range])
            if captured.contains("x") {
                let dimensions = captured.split(separator: "x").compactMap {
                    Int($0)
                }
                if dimensions.count == 2 {
                    return (dimensions[0], dimensions[1])
                }
            } else if let height = Int(captured) {
                return (nil, height)
            }
        }
        return (nil, nil)
    }
}
