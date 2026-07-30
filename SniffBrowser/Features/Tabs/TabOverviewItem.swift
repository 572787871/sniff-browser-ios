import UIKit

struct TabOverviewItem: Identifiable {
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
}
