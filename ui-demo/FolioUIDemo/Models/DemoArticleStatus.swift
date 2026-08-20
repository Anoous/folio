enum DemoArticleStatus: Hashable {
    case accepted
    case queued
    case processing
    case ready
    case partial
    case failed

    var isInProgress: Bool {
        self == .accepted || self == .queued || self == .processing
    }

    var needsAttention: Bool {
        self == .partial || self == .failed
    }
}
