import Foundation

struct FavoriteItem: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let url: URL
    let host: String
    let createdAt: Date
    let updatedAt: Date
    let faviconURL: URL?

    init(
        id: UUID = UUID(),
        title: String,
        url: URL,
        host: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        faviconURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.host = host
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.faviconURL = faviconURL
    }
}
