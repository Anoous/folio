import XCTest
@testable import Folio

final class SSEParserTests: XCTestCase {

    func testParseSourcesEvent() throws {
        let data = "{\"sources\":[{\"article_id\":\"a1\",\"title\":\"Test\",\"created_at\":\"2025-01-01T00:00:00Z\",\"relevance\":0.9}],\"source_count\":1,\"conversation_id\":\"conv1\"}"
        let event = try SSEEventParser.parse(eventType: "sources", data: data)
        guard case .sources(let payload) = event else {
            XCTFail("expected sources event"); return
        }
        XCTAssertEqual(payload.sourceCount, 1)
        XCTAssertEqual(payload.conversationId, "conv1")
        XCTAssertEqual(payload.sources.count, 1)
        XCTAssertEqual(payload.sources[0].articleId, "a1")
    }

    func testParseDeltaEvent() throws {
        let event = try SSEEventParser.parse(eventType: "delta", data: "{\"text\":\"你好\"}")
        guard case .delta(let text) = event else {
            XCTFail("expected delta event"); return
        }
        XCTAssertEqual(text, "你好")
    }

    func testParseDoneEvent() throws {
        let event = try SSEEventParser.parse(eventType: "done", data: "{\"cited_indices\":[1,3],\"followup_suggestions\":[\"q1\"]}")
        guard case .done(let payload) = event else {
            XCTFail("expected done event"); return
        }
        XCTAssertEqual(payload.citedIndices, [1, 3])
        XCTAssertEqual(payload.followupSuggestions, ["q1"])
    }

    func testParseErrorEvent() throws {
        let event = try SSEEventParser.parse(eventType: "error", data: "{\"code\":\"quota_exceeded\",\"message\":\"exceeded\"}")
        guard case .error(let err) = event else {
            XCTFail("expected error event"); return
        }
        XCTAssertEqual(err.code, "quota_exceeded")
    }

    func testParseUnknownEventThrows() {
        XCTAssertThrowsError(try SSEEventParser.parse(eventType: "unknown", data: "{}"))
    }

    func testParseEmptyDelta() throws {
        let event = try SSEEventParser.parse(eventType: "delta", data: "{\"text\":\"\"}")
        guard case .delta(let text) = event else {
            XCTFail("expected delta event"); return
        }
        XCTAssertEqual(text, "")
    }
}
