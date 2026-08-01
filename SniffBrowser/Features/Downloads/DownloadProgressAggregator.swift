import Foundation

struct DownloadProgressSample: Sendable {
    let receivedBytes: Int64
    let expectedBytes: Int64?
    let speedBytesPerSecond: Double?
    let estimatedRemainingTime: TimeInterval?
}

struct DownloadProgressAggregator {
    private var samples: [(Date, Int64)] = []

    mutating func update(
        receivedBytes: Int64,
        expectedBytes: Int64?,
        now: Date = Date()
    ) -> DownloadProgressSample {
        samples.append((now, receivedBytes))
        samples.removeAll { now.timeIntervalSince($0.0) > 4 }
        let speed: Double?
        if let first = samples.first,
           let last = samples.last,
           last.0.timeIntervalSince(first.0) > 0.25 {
            speed = max(0, Double(last.1 - first.1) / last.0.timeIntervalSince(first.0))
        } else {
            speed = nil
        }
        let remaining: TimeInterval?
        if let expectedBytes, let speed, speed > 0 {
            remaining = max(0, Double(expectedBytes - receivedBytes) / speed)
        } else {
            remaining = nil
        }
        return DownloadProgressSample(
            receivedBytes: receivedBytes,
            expectedBytes: expectedBytes,
            speedBytesPerSecond: speed,
            estimatedRemainingTime: remaining
        )
    }
}
