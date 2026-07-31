import UIKit

enum TabOverviewMode: Int, CaseIterable {
    case standard
    case privateBrowsing

    var title: String {
        switch self {
        case .standard:
            return "普通"
        case .privateBrowsing:
            return "无痕"
        }
    }

    var isPrivate: Bool {
        self == .privateBrowsing
    }
}

struct TabOverviewItem: Identifiable, Equatable {
    let id: UUID
    var title: String
    var url: URL?
    var thumbnail: UIImage?
    var isSelected: Bool
    var isPrivate: Bool

    init(
        id: UUID = UUID(),
        title: String,
        url: URL?,
        thumbnail: UIImage? = nil,
        isSelected: Bool = false,
        isPrivate: Bool = false
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.thumbnail = thumbnail
        self.isSelected = isSelected
        self.isPrivate = isPrivate
    }

    static func == (lhs: TabOverviewItem, rhs: TabOverviewItem) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.url == rhs.url
            && lhs.thumbnail === rhs.thumbnail
            && lhs.isSelected == rhs.isSelected
            && lhs.isPrivate == rhs.isPrivate
    }

    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "新标签页" : trimmedTitle
    }

    var displayDomain: String {
        guard let url else { return "嗅探浏览器" }
        if let host = url.host, !host.isEmpty {
            return host
        }
        return url.absoluteString
    }
}
