import Foundation

struct BrowserDisplayError: Equatable {
  let title: String
  let message: String
  let symbolName: String
  let canRetry: Bool
}

enum BrowserErrorMapper {
  static func map(_ error: Error) -> BrowserDisplayError {
    let nsError = error as NSError
    guard nsError.domain == NSURLErrorDomain else {
      return BrowserDisplayError(
        title: "网页无法打开",
        message: "载入网页时出现问题，请稍后重试。",
        symbolName: "exclamationmark.triangle",
        canRetry: true
      )
    }
    let code = URLError.Code(rawValue: nsError.code)

    switch code {
    case .notConnectedToInternet, .networkConnectionLost:
      return BrowserDisplayError(
        title: "没有网络连接",
        message: "请检查 Wi‑Fi 或蜂窝网络后重试。",
        symbolName: "wifi.slash",
        canRetry: true
      )
    case .timedOut:
      return BrowserDisplayError(
        title: "连接超时",
        message: "服务器响应时间过长，请稍后重试。",
        symbolName: "clock.badge.exclamationmark",
        canRetry: true
      )
    case .cannotFindHost, .dnsLookupFailed:
      return BrowserDisplayError(
        title: "找不到网站",
        message: "请检查网址是否正确。",
        symbolName: "globe.badge.chevron.backward",
        canRetry: true
      )
    case .secureConnectionFailed,
         .serverCertificateUntrusted,
         .serverCertificateHasBadDate,
         .serverCertificateHasUnknownRoot,
         .serverCertificateNotYetValid:
      return BrowserDisplayError(
        title: "无法建立安全连接",
        message: "网站证书无效或不受信任，连接已停止。",
        symbolName: "lock.trianglebadge.exclamationmark",
        canRetry: false
      )
    case .cancelled:
      return BrowserDisplayError(
        title: "载入已停止",
        message: "网页载入已取消。",
        symbolName: "xmark.circle",
        canRetry: true
      )
    default:
      return BrowserDisplayError(
        title: "网页无法打开",
        message: "请检查网络连接或稍后重试。",
        symbolName: "exclamationmark.icloud",
        canRetry: true
      )
    }
  }
}
