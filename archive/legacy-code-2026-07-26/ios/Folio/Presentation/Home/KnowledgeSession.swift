import Foundation
import Observation

enum KnowledgePanelKind {
    case spark
    case learn
}

protocol KnowledgeSessionClient {
    func ragQueryStream(question: String, conversationId: String?) -> AsyncThrowingStream<RAGStreamEvent, Error>
    func knowledgeSpark(prompt: String) async throws -> SparkResponse
    func knowledgeLearn(prompt: String) async throws -> LearnResponse
}

extension APIClient: KnowledgeSessionClient {}

@MainActor
@Observable
final class KnowledgeSession {
    private let client: KnowledgeSessionClient
    private let debounce: Duration

    var activeKnowledgePanel: KnowledgePanelKind?
    var isKnowledgeLoading = false
    var sparkInsights: [SparkInsightDTO] = []
    var learnSummary: String?
    var learnItems: [LearnItemDTO] = []
    var knowledgeError: String?

    var ragPartialAnswer: String = ""
    var ragIsStreaming: Bool = false
    var ragSources: RAGSourcesPayload?
    var ragCitedIndices: [Int] = []
    var ragFollowupSuggestions: [String] = []
    var ragError: RAGErrorView.ErrorType?
    var ragConversationId: String?
    var ragThread: [RAGThreadEntry] = []
    var ragStreamTask: Task<Void, Never>?

    init(client: KnowledgeSessionClient, debounce: Duration = .seconds(1)) {
        self.client = client
        self.debounce = debounce
    }

    func isRAGQuery(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 10 else { return false }
        if URLDetection.isURLOnly(trimmed) { return false }
        let indicators = ["？", "?", "什么", "哪些", "如何", "为什么", "怎么", "怎样", "是否", "有没有", "能不能", "多少"]
        return indicators.contains { trimmed.contains($0) }
    }

    func submitRAGQuery(_ question: String) {
        clearKnowledge()
        ragStreamTask?.cancel()
        ragStreamTask = Task {
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await executeRAGQuery(question)
        }
    }

    func waitForCurrentTask() async {
        await ragStreamTask?.value
    }

    private func executeRAGQuery(_ question: String) async {
        ragIsStreaming = true
        ragPartialAnswer = ""
        ragSources = nil
        ragError = nil
        ragCitedIndices = []
        ragFollowupSuggestions = []

        do {
            let stream = client.ragQueryStream(
                question: question,
                conversationId: ragConversationId
            )
            for try await event in stream {
                switch event {
                case .sources(let payload):
                    ragSources = payload
                    ragConversationId = payload.conversationId
                case .delta(let text):
                    ragPartialAnswer += text
                case .done(let payload):
                    ragCitedIndices = payload.citedIndices
                    ragFollowupSuggestions = payload.followupSuggestions
                case .error(let err):
                    switch err.code {
                    case "quota_exceeded":
                        ragError = .quota
                    case "no_articles":
                        ragError = .noArticles
                    default:
                        ragError = .error
                    }
                }
            }
        } catch {
            if !Task.isCancelled, ragPartialAnswer.isEmpty {
                ragError = .error
            }
        }
        ragIsStreaming = false
    }

    func submitFollowup(_ question: String) {
        if let sources = ragSources, !ragPartialAnswer.isEmpty {
            ragThread.append(RAGThreadEntry(
                question: question,
                answer: ragPartialAnswer,
                sources: sources.sources,
                sourceCount: sources.sourceCount,
                citedIndices: ragCitedIndices
            ))
        }
        ragPartialAnswer = ""
        ragSources = nil
        ragCitedIndices = []
        ragFollowupSuggestions = []
        submitRAGQuery(question)
    }

    func clearRAG() {
        ragPartialAnswer = ""
        ragSources = nil
        ragConversationId = nil
        ragThread = []
        ragError = nil
        ragIsStreaming = false
        ragCitedIndices = []
        ragFollowupSuggestions = []
        ragStreamTask?.cancel()
        ragStreamTask = nil
    }

    func loadSpark(prompt: String = "") async {
        clearRAG()
        activeKnowledgePanel = .spark
        isKnowledgeLoading = true
        knowledgeError = nil
        sparkInsights = []
        do {
            let response = try await client.knowledgeSpark(prompt: prompt)
            sparkInsights = response.insights
        } catch {
            knowledgeError = (error as? UserFacingError)?.userMessage ?? error.localizedDescription
        }
        isKnowledgeLoading = false
    }

    func loadLearn(prompt: String = "") async {
        clearRAG()
        activeKnowledgePanel = .learn
        isKnowledgeLoading = true
        knowledgeError = nil
        learnSummary = nil
        learnItems = []
        do {
            let response = try await client.knowledgeLearn(prompt: prompt)
            learnSummary = response.summary
            learnItems = response.items
        } catch {
            knowledgeError = (error as? UserFacingError)?.userMessage ?? error.localizedDescription
        }
        isKnowledgeLoading = false
    }

    func clearKnowledge() {
        activeKnowledgePanel = nil
        isKnowledgeLoading = false
        sparkInsights = []
        learnSummary = nil
        learnItems = []
        knowledgeError = nil
    }
}
