import Foundation

struct HistoryItem: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let url: URL
    let host: String
    let visitedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        url: URL,
        host: String,
        visitedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.host = host
        self.visitedAt = visitedAt
    }
}
