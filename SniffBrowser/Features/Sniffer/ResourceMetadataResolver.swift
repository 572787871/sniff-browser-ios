import Foundation

struct ResourceMetadataResolver: Sendable {
    private let classifier = ResourceClassifier()

    /// 第一阶段只解析脚本已安全提供的元数据，不主动发起 HEAD 或额外网络请求。
    func resolve(
        candidates: [ResourceCandidate],
        tabID: UUID,
        now: Date = Date()
    ) -> [DetectedResource] {
        candidates.prefix(ResourceMessageDecoder.maximumBatchCount).compactMap {
            classifier.makeResource(from: $0, tabID: tabID, now: now)
        }
    }
}
