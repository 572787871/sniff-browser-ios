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
    static let metadataAreaHeight: CGFloat = 60
    static let minimumPortraitPreviewHeightToWidthRatio: CGFloat = 1.34
    static let portraitMinimumItemHeight: CGFloat = 180
    static let portraitMaximumItemHeight: CGFloat = 340

    let columnCount: Int
    let itemSize: CGSize
    let viewportRowCount: Int

    var firstViewportCapacity: Int {
        columnCount * viewportRowCount
    }

    var previewSize: CGSize {
        CGSize(
            width: itemSize.width,
            height: max(1, itemSize.height - Self.metadataAreaHeight)
        )
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
            let fittingItemHeight = floor(
                (
                    availableHeight
                        - topInset
                        - bottomInset
                        - interRowSpacing
                ) / 2
            )
            let aspectPreservingItemHeight = ceil(
                itemWidth * minimumPortraitPreviewHeightToWidthRatio
                    + metadataAreaHeight
            )
            let itemHeight = min(
                portraitMaximumItemHeight,
                max(
                    portraitMinimumItemHeight,
                    fittingItemHeight,
                    aspectPreservingItemHeight
                )
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

/// 标签页预览与浏览器转场共用的页面取景几何。
///
/// 页面始终等比铺满，并固定保留网页顶部；卡片高度不足时只隐藏下方内容。
/// 转场使用 `origin + uniform scale`，让图片在动画任意时刻都不会
/// 非等比变形。
enum TabOverviewTransitionGeometry {
    struct PageImageLayout: Equatable {
        let origin: CGPoint
        let scale: CGFloat

        func frame(contentSize: CGSize) -> CGRect {
            CGRect(
                origin: origin,
                size: CGSize(
                    width: contentSize.width * scale,
                    height: contentSize.height * scale
                )
            )
        }
    }

    static func pageFillLayout(
        contentSize: CGSize,
        containerSize: CGSize
    ) -> PageImageLayout {
        guard contentSize.width > 0,
              contentSize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0
        else {
            return PageImageLayout(origin: .zero, scale: 1)
        }

        let scale = max(
            containerSize.width / contentSize.width,
            containerSize.height / contentSize.height
        )
        let scaledWidth = contentSize.width * scale
        return PageImageLayout(
            origin: CGPoint(
                x: (containerSize.width - scaledWidth) / 2,
                y: 0
            ),
            scale: scale
        )
    }

    static func pageFillFrame(
        contentSize: CGSize,
        containerSize: CGSize
    ) -> CGRect {
        guard contentSize.width > 0,
              contentSize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0
        else { return CGRect(origin: .zero, size: containerSize) }
        return pageFillLayout(
            contentSize: contentSize,
            containerSize: containerSize
        ).frame(contentSize: contentSize)
    }

    /// 将完整页面的顶部锚定布局换算到隐藏地址栏和底部工具栏后的
    /// 局部坐标。
    static func clippedPageLayout(
        contentSize: CGSize,
        fullContainerFrame: CGRect,
        clippedTo clippedFrame: CGRect
    ) -> PageImageLayout {
        let fullLayout = pageFillLayout(
            contentSize: contentSize,
            containerSize: fullContainerFrame.size
        )
        return PageImageLayout(
            origin: CGPoint(
                x: fullContainerFrame.minX
                    + fullLayout.origin.x
                    - clippedFrame.minX,
                y: fullContainerFrame.minY
                    + fullLayout.origin.y
                    - clippedFrame.minY
            ),
            scale: fullLayout.scale
        )
    }

    static func clippedPageFrame(
        contentSize: CGSize,
        fullContainerFrame: CGRect,
        clippedTo clippedFrame: CGRect
    ) -> CGRect {
        clippedPageLayout(
            contentSize: contentSize,
            fullContainerFrame: fullContainerFrame,
            clippedTo: clippedFrame
        ).frame(contentSize: contentSize)
    }
}

/// 恢复标签总览位置时的纯几何计算。默认保留用户原来的 offset；只有
/// 当前标签已经与视口相交但被上下边缘裁切时，才移动到刚好完整可见。
enum TabOverviewScrollRestorationGeometry {
    static func resolvedOffset(
        savedOffset: CGFloat,
        minimumOffset: CGFloat,
        maximumOffset: CGFloat,
        viewportHeight: CGFloat,
        selectedItemFrame: CGRect?,
        visibilityPadding: CGFloat = TabOverviewGridLayoutMetrics.bottomInset
    ) -> CGFloat {
        let lowerBound = min(minimumOffset, maximumOffset)
        let upperBound = max(minimumOffset, maximumOffset)
        var offset = min(upperBound, max(lowerBound, savedOffset))
        guard viewportHeight > 0, let selectedItemFrame else { return offset }

        let viewportMinY = offset
        let viewportMaxY = offset + viewportHeight
        guard selectedItemFrame.maxY > viewportMinY,
              selectedItemFrame.minY < viewportMaxY
        else {
            return offset
        }

        if selectedItemFrame.maxY + visibilityPadding > viewportMaxY {
            offset = selectedItemFrame.maxY
                + visibilityPadding
                - viewportHeight
        } else if selectedItemFrame.minY - visibilityPadding < viewportMinY {
            offset = selectedItemFrame.minY - visibilityPadding
        }
        return min(upperBound, max(lowerBound, offset))
    }
}
