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
        cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData,
        allowsCellularAccess: Bool = true
    ) -> URLRequest {
        var request = URLRequest(url: targetURL, cachePolicy: cachePolicy)
        request.allowsCellularAccess = allowsCellularAccess
        // Cookies are copied from WKWebView after domain/path filtering. Do not
        // let URLSession's separate cookie store replace that explicit context.
        request.httpShouldHandleCookies = false
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        return request
    }

    func assetOptions(allowsCellularAccess: Bool = true) -> [String: Any] {
        var options: [String: Any] = [
            AVURLAssetAllowsCellularAccessKey: allowsCellularAccess
        ]
        if let userAgent = headers["User-Agent"], !userAgent.isEmpty {
            options[AVURLAssetHTTPUserAgentKey] = userAgent
        }
        let validCookies = cookies.compactMap(\.httpCookie)
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
        let matchingCookies = await resolveCookies(
            for: targetURL,
            store: webView.configuration.websiteDataStore.httpCookieStore
        )

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
            cookies: matchingCookies.map(DownloadRequestCookie.init)
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

    private func resolveCookies(
        for targetURL: URL,
        store: WKHTTPCookieStore
    ) async -> [HTTPCookie] {
        let allCookies = await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
        return allCookies.filter { cookie in
            cookie.matches(targetURL)
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
