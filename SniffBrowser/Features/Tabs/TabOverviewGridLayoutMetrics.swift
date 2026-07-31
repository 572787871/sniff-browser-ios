import UIKit

/// 标签页网格的确定性布局结果。
///
/// 竖屏始终使用两列，并用当前容器的完整可用高度计算两行卡片；
/// 横屏根据宽度使用三列或四列，卡片保持可读的最小高度。
struct TabOverviewGridLayoutMetrics: Equatable {
    static let horizontalInset: CGFloat = 16
    static let interItemSpacing: CGFloat = 12
    static let interRowSpacing: CGFloat = 12
    static let topInset: CGFloat = 8
    static let bottomInset: CGFloat = 16
    static let landscapeFourColumnThreshold: CGFloat = 840
    static let previewHeightRatio: CGFloat = 0.69

    let columnCount: Int
    let itemSize: CGSize
    let viewportRowCount: Int

    var firstViewportCapacity: Int {
        columnCount * viewportRowCount
    }

    var firstViewportContentHeight: CGFloat {
        Self.topInset
            + CGFloat(viewportRowCount) * itemSize.height
            + CGFloat(max(0, viewportRowCount - 1)) * Self.interRowSpacing
            + Self.bottomInset
    }

    func requiresVerticalScrolling(itemCount: Int) -> Bool {
        itemCount > firstViewportCapacity
    }

    static func resolve(containerSize: CGSize) -> TabOverviewGridLayoutMetrics {
        let availableWidth = max(1, containerSize.width)
        let availableHeight = max(1, containerSize.height)
        let isPortrait = availableHeight >= availableWidth
        let columns: Int

        if isPortrait {
            columns = 2
        } else {
            columns = availableWidth >= landscapeFourColumnThreshold ? 4 : 3
        }

        let totalColumnSpacing = CGFloat(max(0, columns - 1)) * interItemSpacing
        let itemWidth = floor(
            (
                availableWidth
                    - horizontalInset * 2
                    - totalColumnSpacing
            ) / CGFloat(columns)
        )

        if isPortrait {
            let itemHeight = floor(
                (
                    availableHeight
                        - topInset
                        - bottomInset
                        - interRowSpacing
                ) / 2
            )
            return TabOverviewGridLayoutMetrics(
                columnCount: columns,
                itemSize: CGSize(
                    width: max(1, itemWidth),
                    height: max(1, itemHeight)
                ),
                viewportRowCount: 2
            )
        }

        let itemHeight = min(
            230,
            max(180, floor(max(1, itemWidth) * 1.12))
        )
        let rowCount = max(
            1,
            Int(
                floor(
                    (
                        availableHeight
                            - topInset
                            - bottomInset
                            + interRowSpacing
                    ) / (itemHeight + interRowSpacing)
                )
            )
        )
        return TabOverviewGridLayoutMetrics(
            columnCount: columns,
            itemSize: CGSize(width: max(1, itemWidth), height: itemHeight),
            viewportRowCount: rowCount
        )
    }
}
