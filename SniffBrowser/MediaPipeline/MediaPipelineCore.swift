import Foundation

/// 媒体类型。用户不感知这些类型，仅用于管线内部决策。
enum MediaType: String, Sendable {
    case mp4
    case mov
    case m4v
    case hls
    case ts
    case flv
    case dash
    case mkv
    case webm
    case audio
    case unknown

    var isContainerNeedingRemux: Bool {
        switch self {
        case .ts, .flv, .hls, .dash, .mov, .m4v:
            return true
        case .mp4, .audio, .mkv, .webm, .unknown:
            return false
        }
    }

    var isDirectlyPlayable: Bool {
        switch self {
        case .mp4, .mov, .m4v, .audio:
            return true
        case .hls, .ts, .flv, .dash, .mkv, .webm, .unknown:
            return false
        }
    }

    var preferredFileExtension: String {
        switch self {
        case .mp4, .mov, .m4v, .ts, .flv, .mkv, .webm, .audio:
            return rawValue
        case .hls, .dash, .unknown:
            return "mp4"
        }
    }
}

/// 媒体类型检测：按 URL 扩展名、Content-Type、魔数依次判断。
enum MediaTypeDetector {
    static func detect(
        url: URL?,
        contentType: String?,
        magicBytes: Data? = nil
    ) -> MediaType {
        if let magicBytes {
            let bytes = [UInt8](magicBytes.prefix(12))
            // EBML 头（MKV/WebM）
            if bytes.count >= 4,
               bytes[0] == 0x1A, bytes[1] == 0x45, bytes[2] == 0xDF, bytes[3] == 0xA3 {
                let docType: MediaType = String(
                    data: magicBytes,
                    encoding: .ascii
                )?.contains("webm") == true ? .webm : .mkv
                return docType
            }
            // FLV
            if bytes.count >= 3,
               bytes[0] == 0x46, bytes[1] == 0x4C, bytes[2] == 0x56 {
                return .flv
            }
            // MPEG-TS：0x47 同步字节
            if bytes.count >= 1, bytes[0] == 0x47 {
                return .ts
            }
            // ftyp box（MP4/MOV/M4V 容器由 box 类型区分）
            if bytes.count >= 12,
               bytes[4] == 0x66, bytes[5] == 0x74, bytes[6] == 0x79, bytes[7] == 0x70 {
                let brand = String(bytes: [UInt8](magicBytes[8..<12]), encoding: .ascii) ?? ""
                switch brand {
                case "qt  ": return .mov
                case "M4V ", "M4VH", "M4VP": return .m4v
                default: return .mp4
                }
            }
        }

        if let contentType {
            let normalized = contentType.lowercased()
            if normalized.contains("mpegurl") || normalized.contains("m3u8")
                || normalized.contains("application/vnd.apple.mpegurl") {
                return .hls
            }
            if normalized.contains("dash") || normalized.contains("mpd") {
                return .dash
            }
            if normalized.contains("matroska") || normalized.contains("x-matroska") {
                return .mkv
            }
            if normalized.contains("webm") {
                return .webm
            }
            if normalized.contains("mp4") || normalized.contains("quicktime") {
                return normalized.contains("quicktime") ? .mov : .mp4
            }
            if normalized.contains("mpegurl") || normalized.contains("m3u8") {
                return .hls
            }
            if normalized.contains("mpeg") || normalized.contains("mp2t") {
                return .ts
            }
            if normalized.contains("flv") || normalized.contains("x-flv") {
                return .flv
            }
        }

        if let url {
            let ext = url.pathExtension.lowercased()
            switch ext {
            case "mp4", "m4v", "mov", "m3u8", "m3u", "ts", "flv", "mpd",
                 "mkv", "webm", "m4a", "mp3", "aac", "wav":
                switch ext {
                case "mp4": return .mp4
                case "m4v": return .m4v
                case "mov": return .mov
                case "m3u8", "m3u": return .hls
                case "ts": return .ts
                case "flv": return .flv
                case "mpd": return .dash
                case "mkv": return .mkv
                case "webm": return .webm
                default: return .audio
                }
            default:
                break
            }
        }
        return .unknown
    }
}

/// 从资源类型（嗅探结果）推断媒体类型。
extension MediaType {
    static func from(resourceType: String?) -> MediaType? {
        guard let resourceType else { return nil }
        let normalized = resourceType.lowercased()
        if normalized.contains("hls") || normalized.contains("m3u8") {
            return .hls
        }
        if normalized.contains("dash") || normalized.contains("mpd") {
            return .dash
        }
        if normalized.contains("mkv") {
            return .mkv
        }
        if normalized.contains("webm") {
            return .webm
        }
        if normalized.contains("flv") {
            return .flv
        }
        if normalized.contains("mp2t") || normalized.contains("mpeg-ts") {
            return .ts
        }
        if normalized.contains("quicktime") {
            return .mov
        }
        if normalized.contains("mp4") || normalized.contains("video/mp4") {
            return .mp4
        }
        return nil
    }
}

/// 提取的媒体元数据。
struct MediaAssetInfo: Sendable {
    var duration: TimeInterval
    var width: Int
    var height: Int
    var estimatedBitrate: Double
    var fileSizeBytes: Int64
}

/// 管线处理结果：最终文件 + 封面 + 元数据。
struct FinalMedia: Sendable {
    let url: URL
    let fileName: String
    let thumbnailData: Data?
    let thumbnailLocalPath: String?
    let info: MediaAssetInfo
}

enum MediaProcessError: LocalizedError {
    case invalidSource
    case unsupportedFormat
    case remuxFailed
    case muxFailed
    case metadataFailed
    case thumbnailFailed
    case storageFailed
    case ffmpegUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidSource: return "文件无效。"
        case .unsupportedFormat: return "暂不支持该媒体格式。"
        case .remuxFailed: return "无法生成最终视频。"
        case .muxFailed: return "无法合成最终视频。"
        case .metadataFailed: return "无法读取媒体信息。"
        case .thumbnailFailed: return "无法生成封面。"
        case .storageFailed: return "无法保存文件。"
        case .ffmpegUnavailable: return "当前构建未集成媒体处理组件。"
        }
    }
}
