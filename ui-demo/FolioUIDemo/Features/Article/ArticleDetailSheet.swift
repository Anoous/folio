import Foundation

enum ArticleDetailSheet: Identifiable {
    case appearance
    case articleAsk
    case evidence(DemoEvidence)

    var id: String {
        switch self {
        case .appearance:
            "appearance"
        case .articleAsk:
            "articleAsk"
        case .evidence:
            "evidence"
        }
    }
}
