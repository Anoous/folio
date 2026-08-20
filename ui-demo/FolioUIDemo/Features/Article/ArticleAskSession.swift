import Foundation
import Observation

@MainActor
@Observable
final class ArticleAskSession {
    var draft = ""
    private(set) var submittedQuestion: String?
    private(set) var answer: String?

    var canSubmit: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func submit() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        submittedQuestion = question
        answer = Self.defaultAnswer
        draft = ""
    }

    func referenceArticle(_ title: String) {
        guard draft.isEmpty else { return }
        draft = "关于《\(title)》，"
    }

    func useVoiceDemoPrompt() {
        guard draft.isEmpty else { return }
        draft = "这篇文章的核心观点是什么？"
    }

    func clearConversation() {
        submittedQuestion = nil
        answer = nil
    }

    private static let defaultAnswer = "可信不是靠更多解释建立，而是靠证据、边界和可验证的过程建立。"
}
