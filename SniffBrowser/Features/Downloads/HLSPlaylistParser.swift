import Foundation

struct HLSByteRange: Equatable, Sendable {
    let length: Int64
    let offset: Int64?

    var headerValue: String {
        let start = offset ?? 0
        return "bytes=\(start)-\(start + length - 1)"
    }
}

struct HLSVariant: Equatable, Sendable {
    let url: URL
    let bandwidth: Int?
    let width: Int?
    let height: Int?
}

struct HLSAES128Encryption: Equatable, Sendable {
    let keyURL: URL
    /// Explicit playlist IV. When absent, RFC 8216 derives the IV from the
    /// media sequence number of the encrypted segment.
    let initializationVector: Data?
}

struct HLSSegment: Equatable, Sendable {
    let url: URL
    let byteRange: HLSByteRange?
    let duration: TimeInterval?
    let mediaSequence: Int64
    let encryption: HLSAES128Encryption?

    init(
        url: URL,
        byteRange: HLSByteRange?,
        duration: TimeInterval?,
        mediaSequence: Int64 = 0,
        encryption: HLSAES128Encryption? = nil
    ) {
        self.url = url
        self.byteRange = byteRange
        self.duration = duration
        self.mediaSequence = mediaSequence
        self.encryption = encryption
    }
}

struct HLSMediaPlaylist: Equatable, Sendable {
    let sourceURL: URL
    let initializationSegment: HLSSegment?
    let segments: [HLSSegment]
    let isEndList: Bool
    let hasUnsupportedEncryption: Bool

    var isEncrypted: Bool {
        hasUnsupportedEncryption
            || initializationSegment?.encryption != nil
            || segments.contains(where: { $0.encryption != nil })
    }

    var outputFileExtension: String {
        if initializationSegment != nil
            || segments.allSatisfy({ ["m4s", "mp4", "cmfv", "cmfa"].contains($0.url.pathExtension.lowercased()) }) {
            return "mp4"
        }
        return "ts"
    }
}

enum HLSPlaylist: Equatable, Sendable {
    case master([HLSVariant])
    case media(HLSMediaPlaylist)
}

struct HLSPlaylistParser {
    func parse(_ text: String, sourceURL: URL) throws -> HLSPlaylist {
        let lines = text
            .components(separatedBy: .newlines)
            .map {
                $0.trimmingCharacters(
                    in: .whitespacesAndNewlines.union(
                        CharacterSet(charactersIn: "\u{FEFF}")
                    )
                )
            }
        guard lines.first(where: { !$0.isEmpty }) == "#EXTM3U" else {
            throw DownloadCenterError.invalidHLSPlaylist
        }

        if lines.contains(where: { $0.hasPrefix("#EXT-X-STREAM-INF:") }) {
            let variants = parseVariants(lines: lines, sourceURL: sourceURL)
            guard !variants.isEmpty else {
                throw DownloadCenterError.invalidHLSPlaylist
            }
            return .master(variants)
        }
        return .media(try parseMedia(lines: lines, sourceURL: sourceURL))
    }

    private func parseVariants(lines: [String], sourceURL: URL) -> [HLSVariant] {
        var result: [HLSVariant] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            guard line.hasPrefix("#EXT-X-STREAM-INF:") else {
                index += 1
                continue
            }
            let attributes = parseAttributes(String(line.dropFirst("#EXT-X-STREAM-INF:".count)))
            var cursor = index + 1
            while cursor < lines.count, lines[cursor].isEmpty || lines[cursor].hasPrefix("#") {
                cursor += 1
            }
            if cursor < lines.count,
               let url = URL(string: lines[cursor], relativeTo: sourceURL)?.absoluteURL {
                let resolution = attributes["RESOLUTION"]?
                    .split(separator: "x", maxSplits: 1)
                let width = resolution.flatMap { values in
                    values.first.flatMap { Int(String($0)) }
                }
                let height = resolution.flatMap { values in
                    values.dropFirst().first.flatMap { Int(String($0)) }
                }
                result.append(HLSVariant(
                    url: url,
                    bandwidth: attributes["BANDWIDTH"].flatMap(Int.init),
                    width: width,
                    height: height
                ))
            }
            index = max(cursor + 1, index + 1)
        }
        return result
    }

    private func parseMedia(lines: [String], sourceURL: URL) throws -> HLSMediaPlaylist {
        var segments: [HLSSegment] = []
        var initializationSegment: HLSSegment?
        var pendingDuration: TimeInterval?
        var pendingByteRange: HLSByteRange?
        var previousRangeEnd: Int64?
        var mediaSequence: Int64 = 0
        var nextSequence: Int64 = 0
        var currentEncryption: HLSAES128Encryption?
        var hasUnsupportedEncryption = false

        for line in lines {
            if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                let value = String(line.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                mediaSequence = Int64(value) ?? 0
                nextSequence = mediaSequence
            } else if line.hasPrefix("#EXTINF:") {
                let raw = line.dropFirst("#EXTINF:".count).split(separator: ",", maxSplits: 1).first
                pendingDuration = raw.flatMap { TimeInterval(String($0)) }
            } else if line.hasPrefix("#EXT-X-BYTERANGE:") {
                pendingByteRange = parseByteRange(
                    String(line.dropFirst("#EXT-X-BYTERANGE:".count)),
                    implicitOffset: previousRangeEnd
                )
            } else if line.hasPrefix("#EXT-X-MAP:") {
                let attributes = parseAttributes(String(line.dropFirst("#EXT-X-MAP:".count)))
                if let uri = attributes["URI"],
                   let url = URL(string: uri, relativeTo: sourceURL)?.absoluteURL {
                    let range = attributes["BYTERANGE"].flatMap {
                        parseByteRange($0, implicitOffset: nil)
                    }
                    initializationSegment = HLSSegment(
                        url: url,
                        byteRange: range,
                        duration: nil,
                        mediaSequence: nextSequence,
                        encryption: currentEncryption
                    )
                }
            } else if line.hasPrefix("#EXT-X-KEY:") {
                let attributes = parseAttributes(String(line.dropFirst("#EXT-X-KEY:".count)))
                let method = attributes["METHOD"]?.uppercased() ?? ""
                let keyFormat = attributes["KEYFORMAT"]?.lowercased() ?? "identity"
                switch method {
                case "NONE":
                    currentEncryption = nil
                case "AES-128" where keyFormat == "identity":
                    guard let rawURI = attributes["URI"],
                          let keyURL = URL(string: rawURI, relativeTo: sourceURL)?.absoluteURL
                    else {
                        hasUnsupportedEncryption = true
                        currentEncryption = nil
                        continue
                    }
                    let iv = attributes["IV"].flatMap(parseInitializationVector)
                    if attributes["IV"] != nil, iv == nil {
                        hasUnsupportedEncryption = true
                        currentEncryption = nil
                    } else {
                        currentEncryption = HLSAES128Encryption(
                            keyURL: keyURL,
                            initializationVector: iv
                        )
                    }
                case "":
                    break
                default:
                    // SAMPLE-AES, FairPlay key formats and unknown methods are
                    // protected media. They must never be treated as AES-CBC.
                    hasUnsupportedEncryption = true
                    currentEncryption = nil
                }
            } else if !line.isEmpty, !line.hasPrefix("#"),
                      let url = URL(string: line, relativeTo: sourceURL)?.absoluteURL {
                let range = pendingByteRange
                segments.append(HLSSegment(
                    url: url,
                    byteRange: range,
                    duration: pendingDuration,
                    mediaSequence: nextSequence,
                    encryption: currentEncryption
                ))
                nextSequence += 1
                if let range {
                    previousRangeEnd = (range.offset ?? previousRangeEnd ?? 0) + range.length
                } else {
                    previousRangeEnd = nil
                }
                pendingDuration = nil
                pendingByteRange = nil
            }
        }

        guard !segments.isEmpty else {
            throw DownloadCenterError.invalidHLSPlaylist
        }
        return HLSMediaPlaylist(
            sourceURL: sourceURL,
            initializationSegment: initializationSegment,
            segments: segments,
            isEndList: lines.contains("#EXT-X-ENDLIST"),
            hasUnsupportedEncryption: hasUnsupportedEncryption
        )
    }

    private func parseInitializationVector(_ value: String) -> Data? {
        var hex = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.lowercased().hasPrefix("0x") {
            hex.removeFirst(2)
        }
        guard !hex.isEmpty, hex.count <= 32,
              hex.range(of: #"^[0-9a-fA-F]+$"#, options: .regularExpression) != nil
        else { return nil }
        hex = String(repeating: "0", count: 32 - hex.count) + hex
        var bytes = [UInt8]()
        bytes.reserveCapacity(16)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }

    private func parseByteRange(_ value: String, implicitOffset: Int64?) -> HLSByteRange? {
        let pieces = value
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            .split(separator: "@", maxSplits: 1)
        guard let first = pieces.first, let length = Int64(first), length > 0 else {
            return nil
        }
        let offset = pieces.count > 1 ? Int64(pieces[1]) : implicitOffset
        return HLSByteRange(length: length, offset: offset)
    }

    private func parseAttributes(_ value: String) -> [String: String] {
        var attributes: [String: String] = [:]
        var token = ""
        var quoted = false
        var parts: [String] = []
        for character in value {
            if character == "\"" { quoted.toggle() }
            if character == ",", !quoted {
                parts.append(token)
                token = ""
            } else {
                token.append(character)
            }
        }
        if !token.isEmpty { parts.append(token) }
        for part in parts {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            attributes[pair[0].uppercased()] = pair[1]
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return attributes
    }
}
