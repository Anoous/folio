import Foundation

enum HomeQuotaState: Equatable {
    case signedOut
    case pro
    case available
    case warning
    case exceeded
}
