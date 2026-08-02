import Foundation

enum DemoScreen: String {
    case welcome
    case library
    case reader
    case insight
    case evidence
    case askHome = "ask-home"
    case askAnswer = "ask-answer"
    case askInsufficient = "ask-insufficient"
    case shareSuccess = "share-success"
    case settings

    static var launchValue: DemoScreen? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-demoScreen") else { return nil }
        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else { return nil }
        return DemoScreen(rawValue: arguments[valueIndex])
    }
}
