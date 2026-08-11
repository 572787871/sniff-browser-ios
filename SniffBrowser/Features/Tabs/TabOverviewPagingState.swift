import CoreGraphics

/// 普通／无痕分页的单一状态源，并分别保存两页的垂直滚动位置。
struct TabOverviewPagingState: Equatable {
    private(set) var selectedMode: TabOverviewMode
    private(set) var pendingInteractiveMode: TabOverviewMode?

    private var standardScrollOffset: CGFloat = 0
    private var privateScrollOffset: CGFloat = 0

    init(
        selectedMode: TabOverviewMode,
        standardScrollOffset: CGFloat = 0,
        privateScrollOffset: CGFloat = 0
    ) {
        self.selectedMode = selectedMode
        self.standardScrollOffset = Self.normalized(standardScrollOffset)
        self.privateScrollOffset = Self.normalized(privateScrollOffset)
    }

    @discardableResult
    mutating func selectMode(_ mode: TabOverviewMode) -> Bool {
        pendingInteractiveMode = nil
        guard selectedMode != mode else { return false }
        selectedMode = mode
        return true
    }

    mutating func beginInteractiveTransition(to mode: TabOverviewMode) {
        pendingInteractiveMode = mode == selectedMode ? nil : mode
    }

    @discardableResult
    mutating func finishInteractiveTransition(completed: Bool) -> Bool {
        defer { pendingInteractiveMode = nil }
        guard
            completed,
            let pendingInteractiveMode,
            pendingInteractiveMode != selectedMode
        else {
            return false
        }
        selectedMode = pendingInteractiveMode
        return true
    }

    mutating func saveScrollOffset(_ offset: CGFloat, for mode: TabOverviewMode) {
        guard offset.isFinite else { return }
        let normalizedOffset = max(0, offset)
        switch mode {
        case .standard:
            standardScrollOffset = normalizedOffset
        case .privateBrowsing:
            privateScrollOffset = normalizedOffset
        }
    }

    func scrollOffset(for mode: TabOverviewMode) -> CGFloat {
        switch mode {
        case .standard:
            return standardScrollOffset
        case .privateBrowsing:
            return privateScrollOffset
        }
    }

    private static func normalized(_ offset: CGFloat) -> CGFloat {
        offset.isFinite ? max(0, offset) : 0
    }
}
