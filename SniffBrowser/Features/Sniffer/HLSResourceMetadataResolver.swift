import Foundation

struct HLSResolvedMetadata: Equatable, Sendable {
    let width: Int?
    let height: Int?
    let bitrate: Int?
    let duration: TimeInterval?
    let estimatedSize: Int64?

    var qualityLabel: String? {
        HLSQualityLabel.make(width: width, height: height, bitrate: bitrate)
    }
}

enum HLSQualityLabel {
    static func make(width: Int?, height: Int?, bitrate: Int?) -> String? {
        let verticalResolution: Int? = {
            if let width, width > 0, let height, height > 0 {
                return min(width, height)
            }
            return height.flatMap { $0 > 0 ? $0 : nil }
        }()
        if let verticalResolution {
            switch verticalResolution {
            case 2_160...: return "4K"
            case 1_440...: return "1440p"
            default: return "\(verticalResolution)p"
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
                let estimatedSize = await estimateSize(
                    playlist: playlist,
                    duration: duration,
                    bitrate: selectedVariant?.bandwidth,
                    context: context
                )
                return enrichedResource(
                    resource,
                    metadata: HLSResolvedMetadata(
                        width: selectedVariant?.width
                            ?? Self.inferredResolution(from: playlistURL).width,
                        height: selectedVariant?.height
                            ?? Self.inferredResolution(from: playlistURL).height,
                        bitrate: selectedVariant?.bandwidth,
                        duration: duration,
                        estimatedSize: estimatedSize
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
            estimatedSize: metadata.estimatedSize ?? resource.estimatedSize,
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

    private func estimateSize(
        playlist: HLSMediaPlaylist,
        duration: TimeInterval?,
        bitrate: Int?,
        context: DownloadRequestContext
    ) async -> Int64? {
        if let bitrate,
           let duration,
           duration.isFinite,
           duration > 0 {
            return Int64((Double(bitrate) * duration / 8).rounded())
        }

        let rangedSegments = playlist.segments.compactMap(\.byteRange)
        if rangedSegments.count == playlist.segments.count {
            return rangedSegments.reduce(Int64(0)) { $0 + $1.length }
                + (playlist.initializationSegment?.byteRange?.length ?? 0)
        }

        let samples = Self.sampledSegments(from: playlist.segments)
        var sampledBytes: Int64 = 0
        var sampledDuration: TimeInterval = 0
        var measuredCount = 0
        for segment in samples {
            guard !Task.isCancelled,
                  let byteCount = await Self.contentLength(
                    for: segment,
                    context: context
                  ), byteCount > 0
            else { continue }
            sampledBytes += byteCount
            sampledDuration += segment.duration ?? 0
            measuredCount += 1
        }
        guard measuredCount > 0 else { return nil }

        let mediaBytes: Double
        if sampledDuration > 0,
           let duration,
           duration.isFinite,
           duration > 0 {
            mediaBytes = Double(sampledBytes) / sampledDuration * duration
        } else {
            mediaBytes = Double(sampledBytes) / Double(measuredCount)
                * Double(playlist.segments.count)
        }
        let initializationBytes: Int64
        if let initializationSegment = playlist.initializationSegment {
            if let byteRange = initializationSegment.byteRange {
                initializationBytes = byteRange.length
            } else {
                initializationBytes = await Self.contentLength(
                    for: initializationSegment,
                    context: context
                ) ?? 0
            }
        } else {
            initializationBytes = 0
        }
        guard mediaBytes.isFinite, mediaBytes > 0 else { return nil }
        return Int64(mediaBytes.rounded()) + initializationBytes
    }

    private static func sampledSegments(
        from segments: [HLSSegment]
    ) -> [HLSSegment] {
        guard segments.count > 5 else { return segments }
        let last = segments.count - 1
        let indexes = Set([0, last / 4, last / 2, last * 3 / 4, last])
        return indexes.sorted().map { segments[$0] }
    }

    private static func contentLength(
        for segment: HLSSegment,
        context: DownloadRequestContext
    ) async -> Int64? {
        if let byteRange = segment.byteRange { return byteRange.length }
        var headRequest = context.makeRequest(for: segment.url)
        headRequest.httpMethod = "HEAD"
        headRequest.timeoutInterval = 10
        if let length = await HLSContentLengthProbe.measure(headRequest) {
            return length
        }
        var rangeRequest = context.makeRequest(for: segment.url)
        rangeRequest.httpMethod = "GET"
        rangeRequest.timeoutInterval = 10
        rangeRequest.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        return await HLSContentLengthProbe.measure(rangeRequest)
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

private final class HLSContentLengthProbe: NSObject, URLSessionDataDelegate {
    private var continuation: CheckedContinuation<Int64?, Never>?
    private var session: URLSession?
    private var didFinish = false

    static func measure(_ request: URLRequest) async -> Int64? {
        await withCheckedContinuation { continuation in
            let probe = HLSContentLengthProbe()
            probe.start(request: request, continuation: continuation)
        }
    }

    private func start(
        request: URLRequest,
        continuation: CheckedContinuation<Int64?, Never>
    ) {
        self.continuation = continuation
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: queue
        )
        self.session = session
        session.dataTask(with: request).resume()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let length = Self.contentLength(
            from: response,
            requestedRange: dataTask.originalRequest?
                .value(forHTTPHeaderField: "Range") != nil
        )
        completionHandler(.cancel)
        finish(length)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        finish(nil)
    }

    private func finish(_ value: Int64?) {
        guard !didFinish else { return }
        didFinish = true
        let continuation = continuation
        self.continuation = nil
        session?.invalidateAndCancel()
        session = nil
        continuation?.resume(returning: value)
    }

    private static func contentLength(
        from response: URLResponse,
        requestedRange: Bool
    ) -> Int64? {
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { return nil }
        if let contentRange = http.value(forHTTPHeaderField: "Content-Range"),
           let totalText = contentRange.split(separator: "/").last,
           totalText != "*",
           let total = Int64(totalText),
           total > 0 {
            return total
        }
        if requestedRange, http.statusCode == 206 { return nil }
        return response.expectedContentLength > 0
            ? response.expectedContentLength
            : nil
    }
}
