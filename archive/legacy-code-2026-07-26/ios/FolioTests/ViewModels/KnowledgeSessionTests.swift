import XCTest
@testable import Folio

private final class KnowledgeSessionFakeClient: KnowledgeSessionClient {
    var streamEvents: [RAGStreamEvent] = []
    var sparkResponse = SparkResponse(insights: [])
    var learnResponse = LearnResponse(summary: "", items: [])

    func ragQueryStream(question: String, conversationId: String?) -> AsyncThrowingStream<RAGStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in streamEvents {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    func knowledgeSpark(prompt: String) async throws -> SparkResponse {
        sparkResponse
    }

    func knowledgeLearn(prompt: String) async throws -> LearnResponse {
        learnResponse
    }
}

final class KnowledgeSessionTests: XCTestCase {
    @MainActor
    func testRAGStreamAccumulatesSourcesDeltasAndDoneState() async {
        let client = KnowledgeSessionFakeClient()
        client.streamEvents = [
            .sources(RAGSourcesPayload(sources: [], sourceCount: 0, conversationId: "conv-1")),
            .delta("Hello "),
            .delta("world"),
            .done(RAGDonePayload(citedIndices: [1], followupSuggestions: ["Next?"])),
        ]
        let session = KnowledgeSession(client: client, debounce: .zero)

        session.submitRAGQuery("What did I save about Swift?")
        await session.waitForCurrentTask()

        XCTAssertEqual(session.ragConversationId, "conv-1")
        XCTAssertEqual(session.ragPartialAnswer, "Hello world")
        XCTAssertEqual(session.ragCitedIndices, [1])
        XCTAssertEqual(session.ragFollowupSuggestions, ["Next?"])
        XCTAssertFalse(session.ragIsStreaming)
    }

    @MainActor
    func testSparkClearsRAGStateAndStoresInsights() async throws {
        let client = KnowledgeSessionFakeClient()
        client.sparkResponse = SparkResponse(insights: [
            SparkInsightDTO(
                insight: "Connect ideas",
                whyItMatters: "Because they compound",
                sourceIDs: ["a1"],
                followupQuestion: "How?"
            ),
        ])
        let session = KnowledgeSession(client: client, debounce: .zero)
        session.ragPartialAnswer = "stale"

        await session.loadSpark(prompt: "connect")

        XCTAssertEqual(session.activeKnowledgePanel, .spark)
        XCTAssertEqual(session.sparkInsights.count, 1)
        XCTAssertEqual(session.ragPartialAnswer, "")
        XCTAssertFalse(session.isKnowledgeLoading)
    }
}
