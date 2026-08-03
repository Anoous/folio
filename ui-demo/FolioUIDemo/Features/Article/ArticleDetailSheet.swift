import Foundation

enum ArticleDetailSheet: Identifiable {
    case appearance
    case evidence(DemoEvidence)

    var id: String {
        switch self {
        case .appearance:
            "appearance"
        case .evidence:
            "evidence"
        }
    }
}
