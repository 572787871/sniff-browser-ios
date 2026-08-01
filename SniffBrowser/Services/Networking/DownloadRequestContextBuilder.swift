import AVFoundation
import Foundation
import WebKit

struct DownloadRequestCookie: Sendable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let isSecure: Bool
    let expiresDate: Date?

    init(_ cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        isSecure = cookie.isSecure
        expiresDate = cookie.expiresDate
    }

    var httpCookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
            .secure: isSecure ? "TRUE" : "FALSE"
        ]
        if let expiresDate {
            properties[.expires] = expiresDate
        }
        return HTTPCookie(properties: properties)
    }

    func matches(_ url: URL, now: Date = Date()) -> Bool {
        guard expiresDate.map({ $0 > now }) ?? true,
              let host = url.host?.lowercased()
        else { return false }
        let normalizedDomain = domain
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        let domainMatches = host == normalizedDomain
            || host.hasSuffix(".\(normalizedDomain)")
        guard domainMatches else { return false }
        let requestPath = url.path.isEmpty ? "/" : url.path
        guard requestPath.hasPrefix(path.isEmpty ? "/" : path) else { return false }
        return !isSecure || url.scheme?.lowercased() == "https"
    }
}

struct DownloadRequestContext: Sendable {
    let targetURL: URL
    let pageURL: URL?
    let headers: [String: String]
    let cookies: [DownloadRequestCookie]

    init(
        targetURL: URL,
        pageURL: URL?,
        headers: [String: String],
        cookies: [DownloadRequestCookie] = []
    ) {
        self.targetURL = targetURL
        self.pageURL = pageURL
        self.headers = headers
        self.cookies = cookies
    }

    func makeRequest(
        for url: URL? = nil,
        cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData,
        allowsCellularAccess: Bool = true
    ) -> URLRequest {
        let requestURL = url ?? targetURL
        var request = URLRequest(url: requestURL, cachePolicy: cachePolicy)
        request.allowsCellularAccess = allowsCellularAccess
        // Cookies are copied from WKWebView after domain/path filtering. Do not
        // let URLSession's separate cookie store replace that explicit context.
        request.httpShouldHandleCookies = false
        headers.forEach {
            guard $0.key.caseInsensitiveCompare("Cookie") != .orderedSame else { return }
            request.setValue($0.value, forHTTPHeaderField: $0.key)
        }
        let matchingCookies = cookies
            .filter { $0.matches(requestURL) }
            .compactMap(\.httpCookie)
        if !matchingCookies.isEmpty {
            HTTPCookie.requestHeaderFields(with: matchingCookies).forEach {
                request.setValue($0.value, forHTTPHeaderField: $0.key)
            }
        }
        return request
    }

    func assetOptions(allowsCellularAccess: Bool = true) -> [String: Any] {
        var options: [String: Any] = [
            AVURLAssetAllowsCellularAccessKey: allowsCellularAccess
        ]
        if let userAgent = headers["User-Agent"], !userAgent.isEmpty {
            options[AVURLAssetHTTPUserAgentKey] = userAgent
        }
        let validCookies = cookies
            .filter { $0.matches(targetURL) }
            .compactMap(\.httpCookie)
        if !validCookies.isEmpty {
            options[AVURLAssetHTTPCookiesKey] = validCookies
        }
        return options
    }
}

@MainActor
final class DownloadRequestContextBuilder {
    func build(
        targetURL: URL,
        pageURL: URL?,
        webView: WKWebView?
    ) async -> DownloadRequestContext {
        guard let webView else {
            return DownloadRequestContext(
                targetURL: targetURL,
                pageURL: pageURL,
                headers: refererHeader(pageURL),
                cookies: []
            )
        }

        let userAgent = await resolveUserAgent(in: webView)
        // Keep the current WebKit cookie snapshot in memory and apply only the
        // cookies that match each concrete playlist/key/segment URL. HLS
        // commonly redirects from the page host to a sibling CDN host; taking
        // only the manifest host's cookies here makes those later requests
        // impossible to authenticate correctly.
        let browserCookies = await resolveCookies(
            store: webView.configuration.websiteDataStore.httpCookieStore
        )
        let matchingCookies = browserCookies.filter { $0.matches(targetURL) }

        var headers = refererHeader(pageURL)
        if let value = userAgent, !value.isEmpty {
            headers["User-Agent"] = value
        }
        if !matchingCookies.isEmpty {
            let fields = HTTPCookie.requestHeaderFields(with: matchingCookies)
            fields.forEach { headers[$0.key] = $0.value }
        }
        return DownloadRequestContext(
            targetURL: targetURL,
            pageURL: pageURL,
            headers: headers,
            cookies: browserCookies.map(DownloadRequestCookie.init)
        )
    }

    private func refererHeader(_ pageURL: URL?) -> [String: String] {
        guard let pageURL,
              ["http", "https"].contains(pageURL.scheme?.lowercased() ?? "")
        else { return [:] }
        // A direct file GET normally carries Referer but no Origin. Adding an
        // Origin header to every resource request causes several CDNs to route
        // the request through their CORS/error response instead of the file.
        return ["Referer": pageURL.absoluteString]
    }

    private func resolveUserAgent(in webView: WKWebView) async -> String? {
        if let custom = webView.customUserAgent, !custom.isEmpty { return custom }
        return await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("navigator.userAgent") { value, _ in
                continuation.resume(returning: value as? String)
            }
        }
    }

    private func resolveCookies(store: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
    }
}

private extension HTTPCookie {
    func matches(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let normalizedDomain = domain
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        let domainMatches = host == normalizedDomain
            || host.hasSuffix(".\(normalizedDomain)")
        guard domainMatches else { return false }
        guard url.path.isEmpty || url.path.hasPrefix(path) else { return false }
        return !isSecure || url.scheme?.lowercased() == "https"
    }
}
