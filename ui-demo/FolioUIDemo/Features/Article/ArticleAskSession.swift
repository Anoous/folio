import Foundation
import Observation

@MainActor
@Observable
final class ArticleAskSession {
    var draft = ""
    var submittedQuestion: String?
    var answer: String?
    var answerScrollTarget: String?
    var isCompleted = false

    var canSubmit: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasConversation: Bool {
        submittedQuestion != nil
    }

    func submit() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        submittedQuestion = question
        answer = Self.defaultAnswer
        answerScrollTarget = "article-ask-question"
        draft = ""
        isCompleted = false
    }

    func submitSuggestion(_ question: String) {
        draft = question
        submit()
    }

    func complete() {
        isCompleted = true
        draft = ""
        submittedQuestion = nil
        answer = nil
        answerScrollTarget = nil
    }

    private static let defaultAnswer = "可信不是靠更多解释建立，而是靠证据、边界和可验证的过程建立。"
}
