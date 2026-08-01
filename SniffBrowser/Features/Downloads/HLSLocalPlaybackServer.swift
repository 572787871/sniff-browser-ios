import Foundation
@preconcurrency import Network

enum HLSLocalPlaybackServerError: LocalizedError {
    case unavailable
    case invalidPackage

    var errorDescription: String? {
        switch self {
        case .unavailable: return "本地视频服务启动失败，请重新打开视频。"
        case .invalidPackage: return "视频文件不完整，请重新下载。"
        }
    }
}

/// AVPlayer expects HLS through an HTTP origin. This loopback-only server maps
/// a completed sandbox package to 127.0.0.1 and supports byte-range requests;
/// it never exposes the package on a Wi-Fi or cellular interface.
@MainActor
final class HLSLocalPlaybackServer {
    static let shared = HLSLocalPlaybackServer()

    private let workerQueue = DispatchQueue(
        label: "com.example.SniffBrowser.hls-local-playback",
        qos: .userInitiated
    )
    private var listener: NWListener?
    private var port: NWEndpoint.Port?
    private var packageByToken: [String: URL] = [:]
    private var tokenByPackagePath: [String: String] = [:]
    private var readinessWaiters: [CheckedContinuation<NWEndpoint.Port, Error>] = []

    private init() {}

    func playbackURL(for packageURL: URL) async throws -> URL {
        let playlist = packageURL.appendingPathComponent("index.m3u8")
        guard FileManager.default.fileExists(atPath: playlist.path) else {
            throw HLSLocalPlaybackServerError.invalidPackage
        }
        let standardizedPath = packageURL.standardizedFileURL.path
        let token: String
        if let existing = tokenByPackagePath[standardizedPath] {
            token = existing
        } else {
            token = UUID().uuidString.lowercased()
            tokenByPackagePath[standardizedPath] = token
            packageByToken[token] = packageURL.standardizedFileURL
        }
        let readyPort = try await readyPort()
        guard let url = URL(string: "http://127.0.0.1:\(readyPort.rawValue)/\(token)/index.m3u8") else {
            throw HLSLocalPlaybackServerError.unavailable
        }
        return url
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
                        self.failWaiters(HLSLocalPlaybackServerError.unavailable)
                        return
                    }
                    self.port = value
                    let waiters = self.readinessWaiters
                    self.readinessWaiters.removeAll()
                    waiters.forEach { $0.resume(returning: value) }
                case .failed(_):
                    self.listener = nil
                    self.port = nil
                    self.failWaiters(HLSLocalPlaybackServerError.unavailable)
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
                      let request = HTTPFileRequest(data: data),
                      let package = self.packageByToken[request.token]
                else {
                    Self.sendStatus(404, on: connection)
                    return
                }
                self.workerQueue.async {
                    Self.serve(request, packageURL: package, connection: connection)
                }
            }
        }
    }

    nonisolated private static func serve(
        _ request: HTTPFileRequest,
        packageURL: URL,
        connection: NWConnection
    ) {
        guard request.method == "GET" || request.method == "HEAD",
              !request.relativePath.isEmpty,
              !request.relativePath.components(separatedBy: "/").contains("..")
        else {
            sendStatus(400, on: connection)
            return
        }
        let root = packageURL.standardizedFileURL
        let fileURL = root.appendingPathComponent(request.relativePath).standardizedFileURL
        guard fileURL.path.hasPrefix(root.path + "/"),
              let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
              ),
              values.isRegularFile == true,
              let totalSize = values.fileSize,
              totalSize > 0
        else {
            sendStatus(404, on: connection)
            return
        }

        let requestedRange = request.byteRange(totalSize: totalSize)
        let start = requestedRange?.lowerBound ?? 0
        let end = requestedRange?.upperBound ?? max(totalSize - 1, 0)
        guard start >= 0, end >= start, end < totalSize else {
            sendStatus(416, on: connection)
            return
        }
        let length = end - start + 1
        var headers = [
            "HTTP/1.1 \(requestedRange == nil ? "200 OK" : "206 Partial Content")",
            "Content-Type: \(mimeType(for: fileURL))",
            "Content-Length: \(length)",
            "Accept-Ranges: bytes",
            "Cache-Control: no-store",
            "Connection: close"
        ]
        if requestedRange != nil {
            headers.append("Content-Range: bytes \(start)-\(end)/\(totalSize)")
        }
        let headerData = Data((headers.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        guard request.method == "GET" else {
            connection.send(content: headerData, completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }
        do {
            let handle = try FileHandle(forReadingFrom: fileURL)
            try handle.seek(toOffset: UInt64(start))
            connection.send(content: headerData, completion: .contentProcessed { error in
                guard error == nil else {
                    try? handle.close()
                    connection.cancel()
                    return
                }
                sendFile(
                    handle: handle,
                    remaining: length,
                    connection: connection
                )
            })
        } catch {
            sendStatus(500, on: connection)
        }
    }

    nonisolated private static func sendFile(
        handle: FileHandle,
        remaining: Int,
        connection: NWConnection
    ) {
        guard remaining > 0 else {
            try? handle.close()
            connection.cancel()
            return
        }
        do {
            let data = try handle.read(upToCount: min(remaining, 256 * 1_024)) ?? Data()
            guard !data.isEmpty else {
                try? handle.close()
                connection.cancel()
                return
            }
            connection.send(content: data, completion: .contentProcessed { error in
                guard error == nil else {
                    try? handle.close()
                    connection.cancel()
                    return
                }
                sendFile(
                    handle: handle,
                    remaining: remaining - data.count,
                    connection: connection
                )
            })
        } catch {
            try? handle.close()
            connection.cancel()
        }
    }

    nonisolated private static func sendStatus(
        _ status: Int,
        on connection: NWConnection
    ) {
        let reason: String
        switch status {
        case 400: reason = "Bad Request"
        case 404: reason = "Not Found"
        case 416: reason = "Range Not Satisfiable"
        default: reason = "Internal Server Error"
        }
        let data = Data(
            "HTTP/1.1 \(status) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8
        )
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    nonisolated private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m3u8": return "application/vnd.apple.mpegurl"
        case "ts": return "video/mp2t"
        case "m4s": return "video/iso.segment"
        case "mp4": return "video/mp4"
        case "m4a": return "audio/mp4"
        case "aac": return "audio/aac"
        case "vtt", "webvtt": return "text/vtt"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        default: return "application/octet-stream"
        }
    }
}

private struct HTTPFileRequest: Sendable {
    let method: String
    let token: String
    let relativePath: String
    let rangeHeader: String?

    init?(data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        let first = lines.first?.split(separator: " ") ?? []
        guard first.count >= 2 else { return nil }
        method = String(first[0]).uppercased()
        let rawPath = String(first[1]).split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
        let decoded = rawPath.removingPercentEncoding ?? rawPath
        let components = decoded.split(separator: "/", omittingEmptySubsequences: true)
        guard let firstComponent = components.first else { return nil }
        token = String(firstComponent)
        relativePath = components.dropFirst().map(String.init).joined(separator: "/")
        rangeHeader = lines.first(where: {
            $0.lowercased().hasPrefix("range:")
        }).map { line in
            let parts = line.split(separator: ":", maxSplits: 1)
            return parts.count == 2
                ? String(parts[1]).trimmingCharacters(in: .whitespaces)
                : ""
        }
    }

    func byteRange(totalSize: Int) -> ClosedRange<Int>? {
        guard let rangeHeader,
              rangeHeader.lowercased().hasPrefix("bytes=")
        else { return nil }
        let value = rangeHeader.dropFirst("bytes=".count)
        let bounds = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard bounds.count == 2 else { return nil }
        if bounds[0].isEmpty, let suffix = Int(bounds[1]), suffix > 0 {
            return max(totalSize - suffix, 0)...max(totalSize - 1, 0)
        }
        guard let start = Int(bounds[0]) else { return nil }
        let end = bounds[1].isEmpty ? totalSize - 1 : (Int(bounds[1]) ?? totalSize - 1)
        let normalizedEnd = min(end, totalSize - 1)
        guard start >= 0, start <= normalizedEnd else { return nil }
        return start...normalizedEnd
    }
}
