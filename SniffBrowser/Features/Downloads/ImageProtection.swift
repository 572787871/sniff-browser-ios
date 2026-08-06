import CommonCrypto
import Foundation

/// 部分图床对图片做 AES 加密防盗链：页面脚本用固定密钥解密后再展示，
/// 直接下载拿到的是密文（打开就是“损坏图片”）。这里在下载完成时识别
/// 并解密这类内容，让用户拿到真正可用的图片。
///
/// 密钥/IV 来自对应站点的公开页面脚本（静态值），仅用于把已授权访问的
/// 资源解密成可播放文件，不绕过任何 DRM。
enum ImageProtection {

    struct Scheme {
        let key: Data
        let iv: Data
        let hosts: Set<String>
    }

    /// 已知防护方案注册表。键/IV 为站点页面脚本中的静态 AES-128-CBC 参数。
    static let schemes: [Scheme] = [
        Scheme(
            key: Data("f5d965df75336270".utf8),
            iv: Data("97b60394abc2fbe1".utf8),
            hosts: ["pic.uforxk.cn", "hl365.com"]
        )
    ]

    /// 内容不是合法图片、且来源域名命中已知防护方案时，尝试 AES-CBC 解密；
    /// 解密结果再次校验图片魔数，仍不合法则返回 nil（保持原文件不动）。
    static func decryptedImageData(
        from data: Data,
        sourceHost: String?
    ) -> Data? {
        guard !isRecognizedImage(data) else { return nil }
        guard let host = sourceHost?.lowercased(),
              let scheme = schemes.first(where: { scheme in
                  scheme.hosts.contains { candidate in
                      host == candidate || host.hasSuffix(".\(candidate)")
                  }
              })
        else { return nil }
        guard let plain = try? decrypt(data, key: scheme.key, iv: scheme.iv),
              isRecognizedImage(plain)
        else { return nil }
        return plain
    }

    // MARK: - 图片魔数识别

    /// 识别常见图片格式的魔数（JPEG/PNG/GIF/WebP/BMP/TIFF/HEIC/AVIF/SVG）。
    static func isRecognizedImage(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(16))
        guard !bytes.isEmpty else { return false }
        // JPEG: FF D8 FF
        if bytes.count >= 3,
           bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
            return true
        }
        // PNG: 89 50 4E 47
        if bytes.count >= 4,
           bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47 {
            return true
        }
        // GIF87a / GIF89a
        if bytes.count >= 4,
           bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x38 {
            return true
        }
        // WebP: RIFF....WEBP
        if bytes.count >= 12,
           bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46,
           bytes[8] == 0x57, bytes[9] == 0x45, bytes[10] == 0x42, bytes[11] == 0x50 {
            return true
        }
        // BMP: BM
        if bytes.count >= 2, bytes[0] == 0x42, bytes[1] == 0x4D {
            return true
        }
        // TIFF: II*\0 或 MM\0*
        if bytes.count >= 4,
           (bytes[0] == 0x49 && bytes[1] == 0x49 && bytes[2] == 0x2A)
            || (bytes[0] == 0x4D && bytes[1] == 0x4D && bytes[2] == 0x00) {
            return true
        }
        // HEIC / AVIF / fMP4: 第 4..7 字节为 ftyp
        if bytes.count >= 8,
           bytes[4] == 0x66, bytes[5] == 0x74, bytes[6] == 0x79, bytes[7] == 0x70 {
            return true
        }
        // SVG: 文本形式 <svg / <?xml / <!doctype
        if let head = String(data: data.prefix(512), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) {
            let lower = head.lowercased()
            if lower.hasPrefix("<svg")
                || lower.hasPrefix("<?xml")
                || lower.hasPrefix("<!doctype") {
                return true
            }
        }
        return false
    }

    // MARK: - AES-128-CBC

    private static func decrypt(
        _ data: Data,
        key: Data,
        iv: Data
    ) throws -> Data {
        guard key.count == kCCKeySizeAES128,
              iv.count == kCCBlockSizeAES128
        else {
            throw ImageProtectionError.invalidKey
        }
        var output = Data(count: data.count + kCCBlockSizeAES128)
        let capacity = output.count
        var outputLength = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress,
                            data.count,
                            outputBytes.baseAddress,
                            capacity,
                            &outputLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else {
            throw ImageProtectionError.decryptionFailed
        }
        output.removeSubrange(outputLength..<output.count)
        return output
    }
}

enum ImageProtectionError: LocalizedError {
    case invalidKey
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .invalidKey: return "图片解密密钥无效。"
        case .decryptionFailed: return "图片解密失败。"
        }
    }
}
