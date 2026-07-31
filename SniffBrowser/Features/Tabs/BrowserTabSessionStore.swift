import Foundation

struct BrowserTabSessionRecord: Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let url: URL?
    let lastVisitedDate: Date
}

struct BrowserTabSession: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let selectedTabID: UUID?
    let tabs: [BrowserTabSessionRecord]

    init(
        version: Int = BrowserTabSession.currentVersion,
        selectedTabID: UUID?,
        tabs: [BrowserTabSessionRecord]
    ) {
        self.version = version
        self.selectedTabID = selectedTabID
        self.tabs = tabs
    }
}

@MainActor
final class BrowserTabSessionStore {
    private let defaults: UserDefaults
    private let storageKey: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "browser.tabs.session"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func save(_ session: BrowserTabSession) {
        guard let data = try? encoder.encode(session) else { return }
        defaults.set(data, forKey: storageKey)
    }

    func load() -> BrowserTabSession? {
        guard let data = defaults.data(forKey: storageKey),
              let session = try? decoder.decode(BrowserTabSession.self, from: data),
              session.version == BrowserTabSession.currentVersion
        else {
            return nil
        }
        return session
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
    }
}
