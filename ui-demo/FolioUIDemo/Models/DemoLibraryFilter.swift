enum DemoLibraryFilter: String, CaseIterable, Identifiable {
    case all
    case inProgress
    case readable
    case attention

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            "全部"
        case .inProgress:
            "处理中"
        case .readable:
            "可阅读"
        case .attention:
            "需处理"
        }
    }

    func includes(_ status: DemoArticleStatus) -> Bool {
        switch self {
        case .all:
            true
        case .inProgress:
            status.isInProgress
        case .readable:
            status == .ready || status == .partial
        case .attention:
            status.needsAttention
        }
    }
}
