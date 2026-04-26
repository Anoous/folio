import XCTest
import SwiftData
@testable import Folio

private final class ArticleDeletionSyncWorkflowMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (Data, HTTPURLResponse))?
    nonisolated(unsafe) static var requestPaths: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestPaths.append(request.url?.path ?? "")
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class ArticleDeletionSyncWorkflowTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var apiClient: APIClient!
    private var keychainManager: KeyChainManager!
    private let baseURL = URL(string: "https://test.folio.app")!

    @MainActor
    override func setUp() {
        super.setUp()
        container = try! DataManager.createInMemoryContainer()
        context = container.mainContext

        keychainManager = KeyChainManager(service: "com.folio.article-deletion-sync-tests.\(UUID())")
        try? keychainManager.clearTokens()
        try? keychainManager.saveTokens(access: "test-token", refresh: "test-refresh")

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ArticleDeletionSyncWorkflowMockURLProtocol.self]
        apiClient = APIClient(
            baseURL: baseURL,
            keychainManager: keychainManager,
            session: URLSession(configuration: config)
        )

        ArticleDeletionSyncWorkflowMockURLProtocol.requestHandler = nil
        ArticleDeletionSyncWorkflowMockURLProtocol.requestPaths = []
    }

    override func tearDown() {
        ArticleDeletionSyncWorkflowMockURLProtocol.requestHandler = nil
        ArticleDeletionSyncWorkflowMockURLProtocol.requestPaths = []
        try? keychainManager.clearTokens()
        keychainManager = nil
        apiClient = nil
        container = nil
        context = nil
        super.tearDown()
    }

    private func makeResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: baseURL, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    private func pendingDeletions() throws -> [PendingDeletion] {
        try context.fetch(FetchDescriptor<PendingDeletion>())
    }

    private func deletionRecords() throws -> [DeletionRecord] {
        try context.fetch(FetchDescriptor<DeletionRecord>())
    }

    @MainActor
    func testSyncPendingDeletionsSendsOldestFirstAndRemovesOnSuccess() async throws {
        let later = PendingDeletion(serverID: "server-2", deletedAt: Date(timeIntervalSince1970: 200))
        let earlier = PendingDeletion(serverID: "server-1", deletedAt: Date(timeIntervalSince1970: 100))
        context.insert(later)
        context.insert(earlier)
        try context.save()

        ArticleDeletionSyncWorkflowMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            return (Data(), self.makeResponse(statusCode: 204))
        }

        let workflow = ArticleDeletionSyncWorkflow(apiClient: apiClient, context: context)
        await workflow.syncPendingDeletions()

        XCTAssertEqual(
            ArticleDeletionSyncWorkflowMockURLProtocol.requestPaths,
            ["/api/v1/articles/server-1", "/api/v1/articles/server-2"]
        )
        XCTAssertTrue(try pendingDeletions().isEmpty)
    }

    @MainActor
    func testSyncPendingDeletionsNotFoundClearsRecord() async throws {
        context.insert(PendingDeletion(serverID: "server-missing"))
        try context.save()

        ArticleDeletionSyncWorkflowMockURLProtocol.requestHandler = { _ in
            (Data(), self.makeResponse(statusCode: 404))
        }

        let workflow = ArticleDeletionSyncWorkflow(apiClient: apiClient, context: context)
        await workflow.syncPendingDeletions()

        XCTAssertTrue(try pendingDeletions().isEmpty)
    }

    @MainActor
    func testSyncPendingDeletionsServerFailureKeepsRecord() async throws {
        context.insert(PendingDeletion(serverID: "server-failing"))
        try context.save()

        ArticleDeletionSyncWorkflowMockURLProtocol.requestHandler = { _ in
            (Data(), self.makeResponse(statusCode: 500))
        }

        let workflow = ArticleDeletionSyncWorkflow(apiClient: apiClient, context: context)
        await workflow.syncPendingDeletions()

        let pending = try pendingDeletions()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.serverID, "server-failing")
    }

    @MainActor
    func testCleanupOldDeletionRecordsRemovesExpiredOnly() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let expiredDate = try XCTUnwrap(
            calendar.date(byAdding: .day, value: -(DeletionRecord.retentionDays + 1), to: now)
        )
        let retainedDate = try XCTUnwrap(
            calendar.date(byAdding: .day, value: -(DeletionRecord.retentionDays - 1), to: now)
        )

        context.insert(DeletionRecord(serverID: "expired", deletedAt: expiredDate))
        context.insert(DeletionRecord(serverID: "retained", deletedAt: retainedDate))
        try context.save()

        let workflow = ArticleDeletionSyncWorkflow(apiClient: apiClient, context: context)
        workflow.cleanupOldDeletionRecords(now: now, calendar: calendar)

        let serverIDs = try deletionRecords().map(\.serverID)
        XCTAssertEqual(serverIDs, ["retained"])
    }
}
