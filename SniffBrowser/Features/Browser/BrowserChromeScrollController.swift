import CoreGraphics

enum BrowserChromeState: Equatable {
  case expanded
  case compact
}

/// A direction-and-threshold state machine that avoids per-frame constraint
/// mutations while a web page scrolls.
struct BrowserChromeScrollController {
  private(set) var state: BrowserChromeState = .expanded
  private var previousOffset: CGFloat?
  private var accumulatedDelta: CGFloat = 0

  mutating func update(
    contentOffsetY: CGFloat,
    adjustedTopInset: CGFloat,
    canCollapse: Bool
  ) -> BrowserChromeState? {
    let visibleOffset = contentOffsetY + adjustedTopInset
    defer { previousOffset = visibleOffset }

    guard canCollapse else {
      accumulatedDelta = 0
      return transition(to: .expanded)
    }
    guard visibleOffset > 8 else {
      accumulatedDelta = 0
      return transition(to: .expanded)
    }
    guard let previousOffset else { return nil }

    let delta = visibleOffset - previousOffset
    guard abs(delta) > 0.5 else { return nil }

    if accumulatedDelta.directionSign != delta.directionSign {
      accumulatedDelta = 0
    }
    accumulatedDelta += delta

    if accumulatedDelta >= 32 {
      accumulatedDelta = 0
      return transition(to: .compact)
    }
    if accumulatedDelta <= -24 {
      accumulatedDelta = 0
      return transition(to: .expanded)
    }
    return nil
  }

  mutating func reset(to state: BrowserChromeState = .expanded) {
    self.state = state
    previousOffset = nil
    accumulatedDelta = 0
  }

  private mutating func transition(
    to newState: BrowserChromeState
  ) -> BrowserChromeState? {
    guard state != newState else { return nil }
    state = newState
    return newState
  }
}

private extension FloatingPoint {
  var directionSign: Self {
    if self > 0 { return 1 }
    if self < 0 { return -1 }
    return 0
  }
}
