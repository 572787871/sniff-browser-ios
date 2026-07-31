import Foundation
import WebKit

/// 负责清理普通浏览会话使用的公开 WebKit 网站数据。
///
/// 无痕标签使用 nonPersistent 数据存储，关闭后由 WebKit 销毁；这里不会
/// 绕过证书、访问网页内容或读取 Cookie 值。
@MainActor
final class WebsiteDataManager {
    func clearAllWebsiteData() async {
        let store = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()

        await withCheckedContinuation { continuation in
            store.removeData(
                ofTypes: dataTypes,
                modifiedSince: .distantPast
            ) {
                continuation.resume()
            }
        }
        URLCache.shared.removeAllCachedResponses()
    }
}
