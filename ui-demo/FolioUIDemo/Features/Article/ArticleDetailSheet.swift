import Foundation

enum ArticleDetailSheet: Identifiable {
    case appearance
    case annotations(focusedHighlightID: UUID?)
    case evidence(DemoEvidence)

    var id: String {
        switch self {
        case .appearance:
            "appearance"
        case .annotations(let focusedHighlightID):
            "annotations-\(focusedHighlightID?.uuidString ?? "all")"
        case .evidence:
            "evidence"
        }
    }
}
