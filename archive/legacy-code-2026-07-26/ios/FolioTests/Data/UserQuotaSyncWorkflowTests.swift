import XCTest
@testable import Folio

private final class UserQuotaSyncWorkflowMockURLProtocol: URLProtocol {
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

final class UserQuotaSyncWorkflowTests: XCTestCase {
    private var apiClient: APIClient!
    private var keychainManager: KeyChainManager!
    private let baseURL = URL(string: "https://test.folio.app")!

    override func setUp() {
        super.setUp()

        keychainManager = KeyChainManager(service: "com.folio.user-quota-sync-tests.\(UUID())")
        try? keychainManager.clearTokens()
        try? keychainManager.saveTokens(access: "test-token", refresh: "test-refresh")

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UserQuotaSyncWorkflowMockURLProtocol.self]
        apiClient = APIClient(
            baseURL: baseURL,
            keychainManager: keychainManager,
            session: URLSession(configuration: config)
        )

        UserQuotaSyncWorkflowMockURLProtocol.requestHandler = nil
        UserQuotaSyncWorkflowMockURLProtocol.requestPaths = []
    }

    override func tearDown() {
        UserQuotaSyncWorkflowMockURLProtocol.requestHandler = nil
        UserQuotaSyncWorkflowMockURLProtocol.requestPaths = []
        try? keychainManager.clearTokens()
        keychainManager = nil
        apiClient = nil
        super.tearDown()
    }

    private func makeResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: baseURL, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    private func authResponseJSON(
        subscription: String,
        monthlyQuota: Int = 100,
        currentMonthCount: Int = 3,
        syncEpoch: Int? = 7
    ) -> Data {
        """
        {
          "access_token": "new-token",
          "refresh_token": "new-refresh",
          "expires_in": 3600,
          "user": {
            "id": "user-1",
            "email": "test@example.com",
            "nickname": "tester",
            "avatar_url": null,
            "subscription": "\(subscription)",
            "subscription_expires_at": null,
            "monthly_quota": \(monthlyQuota),
            "current_month_count": \(currentMonthCount),
            "preferred_language": "en",
            "created_at": "2025-01-01T00:00:00Z",
            "updated_at": "2025-01-01T00:00:00Z",
            "sync_epoch": \(syncEpoch.map(String.init) ?? "null")
          }
        }
        """.data(using: .utf8)!
    }

    @MainActor
    func testSyncUserQuotaWritesServerQuotaAndChecksEpoch() async {
        UserQuotaSyncWorkflowMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/auth/refresh")
            return (
                self.authResponseJSON(subscription: AppConstants.subscriptionPro, monthlyQuota: 500, currentMonthCount: 8, syncEpoch: 9),
                self.makeResponse(statusCode: 200)
            )
        }

        var quotaWrites: [(Int, Int, Bool)] = []
        var checkedEpochs: [Int] = []
        let workflow = UserQuotaSyncWorkflow(
            apiClient: apiClient,
            quotaWriter: { monthlyQuota, currentMonthCount, isPro in
                quotaWrites.append((monthlyQuota, currentMonthCount, isPro))
            },
            epochChecker: { epoch in
                checkedEpochs.append(epoch)
            }
        )

        await workflow.syncUserQuota()

        XCTAssertEqual(UserQuotaSyncWorkflowMockURLProtocol.requestPaths, ["/api/v1/auth/refresh"])
        XCTAssertEqual(quotaWrites.count, 1)
        XCTAssertEqual(quotaWrites.first?.0, 500)
        XCTAssertEqual(quotaWrites.first?.1, 8)
        XCTAssertEqual(quotaWrites.first?.2, true)
        XCTAssertEqual(checkedEpochs, [9])
    }

    @MainActor
    func testSyncUserQuotaTreatsFreeUserAsNonProAndSkipsMissingEpoch() async {
        UserQuotaSyncWorkflowMockURLProtocol.requestHandler = { _ in
            (
                self.authResponseJSON(subscription: AppConstants.subscriptionFree, syncEpoch: nil),
                self.makeResponse(statusCode: 200)
            )
        }

        var quotaWrites: [(Int, Int, Bool)] = []
        var checkedEpochs: [Int] = []
        let workflow = UserQuotaSyncWorkflow(
            apiClient: apiClient,
            quotaWriter: { monthlyQuota, currentMonthCount, isPro in
                quotaWrites.append((monthlyQuota, currentMonthCount, isPro))
            },
            epochChecker: { epoch in
                checkedEpochs.append(epoch)
            }
        )

        await workflow.syncUserQuota()

        XCTAssertEqual(quotaWrites.count, 1)
        XCTAssertEqual(quotaWrites.first?.2, false)
        XCTAssertTrue(checkedEpochs.isEmpty)
    }

    @MainActor
    func testSyncUserQuotaFailureDoesNotWriteQuotaOrCheckEpoch() async {
        UserQuotaSyncWorkflowMockURLProtocol.requestHandler = { _ in
            (Data(), self.makeResponse(statusCode: 500))
        }

        var quotaWriteCount = 0
        var checkedEpochs: [Int] = []
        let workflow = UserQuotaSyncWorkflow(
            apiClient: apiClient,
            quotaWriter: { _, _, _ in
                quotaWriteCount += 1
            },
            epochChecker: { epoch in
                checkedEpochs.append(epoch)
            }
        )

        await workflow.syncUserQuota()

        XCTAssertEqual(quotaWriteCount, 0)
        XCTAssertTrue(checkedEpochs.isEmpty)
    }
}
