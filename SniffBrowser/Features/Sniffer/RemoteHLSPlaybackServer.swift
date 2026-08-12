import Foundation
@preconcurrency import Network

enum RemoteHLSPlaybackServerError: LocalizedError {
    case unavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "在线播放服务启动失败，请重试。"
        case .invalidResponse:
            return "视频地址已失效，请返回网页重新识别。"
        }
    }
}

enum RemoteMediaPlaybackKind: Sendable {
    case hls
    case direct
}

/// Provides AVPlayer with a loopback media origin while fetching manifests,
/// segments and direct-file byte ranges with the same in-memory context as
/// the WKWebView. This avoids undocumented AVURLAsset header options and never
/// persists cookies or request headers.
@MainActor
final class RemoteHLSPlaybackServer {
    static let shared = RemoteHLSPlaybackServer()

    private let workerQueue = DispatchQueue(
        label: "com.example.SniffBrowser.hls-remote-playback",
        qos: .userInitiated
    )
    private let session: URLSession
    private var listener: NWListener?
    private var port: NWEndpoint.Port?
    private struct PlaybackContext: Sendable {
        let requestContext: DownloadRequestContext
        let kind: RemoteMediaPlaybackKind
    }

    private var contextByToken: [String: PlaybackContext] = [:]
    private var readinessWaiters: [CheckedContinuation<NWEndpoint.Port, Error>] = []

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        session = URLSession(configuration: configuration)
    }

    func playbackURL(
        context: DownloadRequestContext,
        kind: RemoteMediaPlaybackKind = .hls
    ) async throws -> URL {
        guard ["http", "https"].contains(
            context.targetURL.scheme?.lowercased() ?? ""
        ) else { throw RemoteHLSPlaybackServerError.invalidResponse }
        let token = UUID().uuidString.lowercased()
        contextByToken[token] = PlaybackContext(
            requestContext: context,
            kind: kind
        )
        // Tokens are intentionally short-lived and never written to disk.
        // Keeping a hard cap also prevents repeated previews from retaining
        // old cookie snapshots for the lifetime of the app.
        if contextByToken.count > 32,
           let staleToken = contextByToken.keys.first(where: { $0 != token }) {
            contextByToken[staleToken] = nil
        }
        let readyPort = try await readyPort()
        return try Self.proxyURL(
            remoteURL: context.targetURL,
            token: token,
            port: readyPort
        )
    }

    private func readyPort() async throws -> NWEndpoint.Port {
        if let port { return port }
        if listener == nil { try startListener() }
        return try await withCheckedThrowingContinuation { continuation in
            readinessWaiters.append(continuation)
        }
    }

    private func startListener() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: .any
        )
        let listener = try NWListener(using: parameters, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor [weak self] in
                self?.receiveRequest(on: connection)
            }
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let value = listener.port else {
                        self.failWaiters(RemoteHLSPlaybackServerError.unavailable)
                        return
                    }
                    self.port = value
                    let waiters = self.readinessWaiters
                    self.readinessWaiters.removeAll()
                    waiters.forEach { $0.resume(returning: value) }
                case .failed(_):
                    self.listener = nil
                    self.port = nil
                    self.failWaiters(RemoteHLSPlaybackServerError.unavailable)
                case .cancelled:
                    self.listener = nil
                    self.port = nil
                default:
                    break
                }
            }
        }
        listener.start(queue: workerQueue)
    }

    private func failWaiters(_ error: Error) {
        let waiters = readinessWaiters
        readinessWaiters.removeAll()
        waiters.forEach { $0.resume(throwing: error) }
    }

    private func receiveRequest(on connection: NWConnection) {
        connection.start(queue: workerQueue)
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 32 * 1_024
        ) { [weak self] data, _, _, error in
            guard error == nil, let data, !data.isEmpty else {
                connection.cancel()
                return
            }
            Task { @MainActor [weak self] in
                guard let self,
                      let request = RemoteHLSHTTPRequest(data: data),
                      let playbackContext = self.contextByToken[request.token],
                      let readyPort = self.port,
                      let remoteURL = request.remoteURL
                else {
                    Self.sendStatus(404, on: connection)
                    return
                }
                let session = self.session
                Task(priority: .userInitiated) {
                    await Self.serve(
                        request,
                        remoteURL: remoteURL,
                        context: playbackContext.requestContext,
                        kind: playbackContext.kind,
                        port: readyPort,
                        session: session,
                        connection: connection
                    )
                }
            }
        }
    }

    nonisolated private static func serve(
        _ localRequest: RemoteHLSHTTPRequest,
        remoteURL: URL,
        context: DownloadRequestContext,
        kind: RemoteMediaPlaybackKind,
        port: NWEndpoint.Port,
        session: URLSession,
        connection: NWConnection
    ) async {
        guard localRequest.method == "GET" || localRequest.method == "HEAD" else {
            sendStatus(400, on: connection)
            return
        }
        var request = context.makeRequest(for: remoteURL)
        request.httpMethod = localRequest.method
        request.timeoutInterval = 30
        if let range = localRequest.rangeHeader, !range.isEmpty {
            request.setValue(range, forHTTPHeaderField: "Range")
        }
        if kind == .direct {
            await serveDirectMedia(
                request,
                session: session,
                connection: connection
            )
            return
        }
        do {
            let (receivedData, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode)
            else {
                sendStatus(502, on: connection)
                return
            }
            let finalURL = response.url ?? remoteURL
            var data = receivedData
            var mimeType = http.mimeType ?? "application/octet-stream"
            if localRequest.method == "GET",
               data.count <= 5_000_000,
               let playlist = String(data: data, encoding: .utf8),
               playlist.contains("#EXTM3U") {
                let rewritten = RemoteHLSPlaylistRewriter.rewrite(
                    playlist,
                    baseURL: finalURL
                ) { nestedURL in
                    makeProxyURL(
                        remoteURL: nestedURL,
                        token: localRequest.token,
                        port: port
                    )
                }
                data = Data(rewritten.utf8)
                mimeType = "application/vnd.apple.mpegurl"
            }
            sendResponse(
                statusCode: http.statusCode,
                mimeType: mimeType,
                contentRange: http.value(forHTTPHeaderField: "Content-Range"),
                acceptsRanges: http.value(forHTTPHeaderField: "Accept-Ranges"),
                expectedContentLength: http.expectedContentLength,
                data: data,
                isHead: localRequest.method == "HEAD",
                connection: connection
            )
        } catch {
            sendStatus(502, on: connection)
        }
    }

    /// 普通 MP4/MOV/音频按 URLSession 的字节流逐段转发。AVPlayer 发出的
    /// Range 请求会原样带给源站，所以下载同时播放时仍可拖动到源站支持
    /// 的任意时间点；任何时刻内存里只保留一个小缓冲区。
    nonisolated private static func serveDirectMedia(
        _ request: URLRequest,
        session: URLSession,
        connection: NWConnection
    ) async {
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode)
            else {
                sendStatus(502, on: connection)
                return
            }
            let isHead = request.httpMethod == "HEAD"
            let header = responseHeaderData(
                statusCode: http.statusCode,
                mimeType: http.mimeType ?? "application/octet-stream",
                contentRange: http.value(forHTTPHeaderField: "Content-Range"),
                acceptsRanges: http.value(forHTTPHeaderField: "Accept-Ranges"),
                expectedContentLength: http.expectedContentLength
            )
            try await sendChunk(header, on: connection)
            guard !isHead else {
                connection.cancel()
                return
            }

            var buffer = Data()
            buffer.reserveCapacity(64 * 1_024)
            for try await byte in bytes {
                try Task.checkCancellation()
                buffer.append(byte)
                if buffer.count >= 64 * 1_024 {
                    try await sendChunk(buffer, on: connection)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            if !buffer.isEmpty {
                try await sendChunk(buffer, on: connection)
            }
            connection.cancel()
        } catch {
            connection.cancel()
        }
    }

    nonisolated private static func responseHeaderData(
        statusCode: Int,
        mimeType: String,
        contentRange: String?,
        acceptsRanges: String?,
        expectedContentLength: Int64
    ) -> Data {
        let reason = statusCode == 206 ? "Partial Content" : "OK"
        var headers = [
            "HTTP/1.1 \(statusCode) \(reason)",
            "Content-Type: \(mimeType)",
            "Accept-Ranges: \(acceptsRanges ?? "bytes")",
            "Cache-Control: no-store",
            "Connection: close"
        ]
        if expectedContentLength >= 0 {
            headers.append("Content-Length: \(expectedContentLength)")
        }
        if let contentRange {
            headers.append("Content-Range: \(contentRange)")
        }
        return Data((headers.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    }

    nonisolated private static func sendChunk(
        _ data: Data,
        on connection: NWConnection
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: data,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            )
        }
    }

    nonisolated private static func sendResponse(
        statusCode: Int,
        mimeType: String,
        contentRange: String?,
        acceptsRanges: String?,
        expectedContentLength: Int64,
        data: Data,
        isHead: Bool,
        connection: NWConnection
    ) {
        let reason = statusCode == 206 ? "Partial Content" : "OK"
        let contentLength = isHead && expectedContentLength >= 0
            ? expectedContentLength
            : Int64(data.count)
        var headers = [
            "HTTP/1.1 \(statusCode) \(reason)",
            "Content-Type: \(mimeType)",
            "Content-Length: \(contentLength)",
            "Accept-Ranges: \(acceptsRanges ?? "bytes")",
            "Cache-Control: no-store",
            "Connection: close"
        ]
        if let contentRange { headers.append("Content-Range: \(contentRange)") }
        let headerData = Data((headers.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        connection.send(content: headerData, completion: .contentProcessed { error in
            guard error == nil, !isHead else {
                connection.cancel()
                return
            }
            sendBody(data, offset: 0, connection: connection)
        })
    }

    nonisolated private static func sendBody(
        _ data: Data,
        offset: Int,
        connection: NWConnection
    ) {
        guard offset < data.count else {
            connection.cancel()
            return
        }
        let end = min(offset + 256 * 1_024, data.count)
        connection.send(
            content: data.subdata(in: offset..<end),
            completion: .contentProcessed { error in
                guard error == nil else {
                    connection.cancel()
                    return
                }
                sendBody(data, offset: end, connection: connection)
            }
        )
    }

    nonisolated private static func sendStatus(
        _ status: Int,
        on connection: NWConnection
    ) {
        let reason: String
        switch status {
        case 400: reason = "Bad Request"
        case 404: reason = "Not Found"
        default: reason = "Bad Gateway"
        }
        let response = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    nonisolated private static func proxyURL(
        remoteURL: URL,
        token: String,
        port: NWEndpoint.Port
    ) throws -> URL {
        guard let url = makeProxyURL(
            remoteURL: remoteURL,
            token: token,
            port: port
        ) else { throw RemoteHLSPlaybackServerError.unavailable }
        return url
    }

    nonisolated private static func makeProxyURL(
        remoteURL: URL,
        token: String,
        port: NWEndpoint.Port
    ) -> URL? {
        let encoded = Data(remoteURL.absoluteString.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return URL(string: "http://127.0.0.1:\(port.rawValue)/remote/\(token)/\(encoded)")
    }
}

enum RemoteHLSPlaylistRewriter {
    static func rewrite(
        _ playlist: String,
        baseURL: URL,
        proxyURL: (URL) -> URL?
    ) -> String {
        playlist.components(separatedBy: .newlines).map { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !trimmed.hasPrefix("#"),
               let remote = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL,
               let local = proxyURL(remote) {
                return local.absoluteString
            }
            return rewriteURIAttributes(line, baseURL: baseURL, proxyURL: proxyURL)
        }.joined(separator: "\n")
    }

    private static func rewriteURIAttributes(
        _ line: String,
        baseURL: URL,
        proxyURL: (URL) -> URL?
    ) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: #"URI="([^"]+)""#
        ) else { return line }
        var result = line
        let matches = expression.matches(
            in: line,
            range: NSRange(line.startIndex..., in: line)
        )
        for match in matches.reversed() {
            guard let valueRange = Range(match.range(at: 1), in: result),
                  let fullRange = Range(match.range(at: 0), in: result),
                  let remote = URL(
                    string: String(result[valueRange]),
                    relativeTo: baseURL
                  )?.absoluteURL,
                  let local = proxyURL(remote)
            else { continue }
            result.replaceSubrange(fullRange, with: "URI=\"\(local.absoluteString)\"")
        }
        return result
    }
}

private struct RemoteHLSHTTPRequest: Sendable {
    let method: String
    let token: String
    let remoteURL: URL?
    let rangeHeader: String?

    init?(data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        let first = lines.first?.split(separator: " ") ?? []
        guard first.count >= 2 else { return nil }
        method = String(first[0]).uppercased()
        let rawPath = String(first[1]).split(
            separator: "?",
            maxSplits: 1
        ).first.map(String.init) ?? ""
        let components = rawPath.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 3, components[0] == "remote" else { return nil }
        token = String(components[1])
        var encoded = String(components[2])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        remoteURL = Data(base64Encoded: encoded)
            .flatMap { String(data: $0, encoding: .utf8) }
            .flatMap(URL.init(string:))
        rangeHeader = lines.first(where: {
            $0.lowercased().hasPrefix("range:")
        }).flatMap { line in
            line.split(separator: ":", maxSplits: 1).dropFirst().first.map {
                String($0).trimmingCharacters(in: .whitespaces)
            }
        }
    }
}
