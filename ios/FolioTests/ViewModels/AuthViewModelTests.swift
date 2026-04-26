import XCTest
import KeychainAccess
@testable import Folio

private final class AuthViewModelMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (Data, HTTPURLResponse))?
    nonisolated(unsafe) static var lastRequestBody: Data?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request

        if let body = request.httpBody {
            Self.lastRequestBody = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            let bufferSize = 4096
            var data = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer {
                buffer.deallocate()
                stream.close()
            }

            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read > 0 {
                    data.append(buffer, count: read)
                } else {
                    break
                }
            }
            Self.lastRequestBody = data
        } else {
            Self.lastRequestBody = nil
        }

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

@MainActor
final class AuthViewModelTests: XCTestCase {
    private var authViewModel: AuthViewModel!
    private var keychainManager: KeyChainManager!
    private var apiClient: APIClient!
    private let baseURL = URL(string: "https://test.folio.app")!
    private let keychainService = "com.folio.app.auth-view-model-tests"

    override func setUp() {
        super.setUp()

        keychainManager = KeyChainManager(service: keychainService)
        try? keychainManager.clearTokens()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AuthViewModelMockURLProtocol.self]
        let session = URLSession(configuration: config)

        apiClient = APIClient(baseURL: baseURL, keychainManager: keychainManager, session: session)
        authViewModel = AuthViewModel(apiClient: apiClient, keychainManager: keychainManager)
    }

    override func tearDown() {
        AuthViewModelMockURLProtocol.requestHandler = nil
        AuthViewModelMockURLProtocol.lastRequestBody = nil
        AuthViewModelMockURLProtocol.lastRequest = nil
        try? keychainManager.clearTokens()
        authViewModel = nil
        apiClient = nil
        keychainManager = nil
        super.tearDown()
    }

    func testCheckExistingAuth_refreshOnlyTokenRestoresSignedInState() async throws {
        try Keychain(service: keychainService).set("refresh-only-token", key: "refresh_token")

        AuthViewModelMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/auth/refresh")
            let body = try XCTUnwrap(Self.decodeBody(AuthViewModelMockURLProtocol.lastRequestBody))
            XCTAssertEqual(body["refresh_token"] as? String, "refresh-only-token")
            return (Self.authResponseJSON(), Self.makeResponse(url: request.url, statusCode: 200))
        }

        await authViewModel.checkExistingAuth()

        XCTAssertEqual(authViewModel.authState, .signedIn)
        XCTAssertEqual(authViewModel.currentUser?.id, "user-1")
        XCTAssertEqual(keychainManager.accessToken, "new_access")
        XCTAssertEqual(keychainManager.refreshToken, "new_refresh")
    }

    func testSignOut_revokesRemoteSessionAndClearsLocalState() async throws {
        try keychainManager.saveTokens(access: "access-123", refresh: "refresh-456")
        authViewModel.currentUser = Self.makeUserDTO()
        authViewModel.authState = .signedIn

        AuthViewModelMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/auth/logout")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let body = try XCTUnwrap(Self.decodeBody(AuthViewModelMockURLProtocol.lastRequestBody))
            XCTAssertEqual(body["refresh_token"] as? String, "refresh-456")
            return (Data(), Self.makeResponse(url: request.url, statusCode: 204))
        }

        await authViewModel.signOut()

        XCTAssertEqual(authViewModel.authState, .signedOut)
        XCTAssertNil(authViewModel.currentUser)
        XCTAssertNil(keychainManager.accessToken)
        XCTAssertNil(keychainManager.refreshToken)
    }

    func testSignOut_networkFailureStillClearsLocalState() async throws {
        try keychainManager.saveTokens(access: "access-123", refresh: "refresh-456")
        authViewModel.currentUser = Self.makeUserDTO()
        authViewModel.authState = .signedIn

        AuthViewModelMockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        await authViewModel.signOut()

        XCTAssertEqual(authViewModel.authState, .signedOut)
        XCTAssertNil(authViewModel.currentUser)
        XCTAssertFalse(keychainManager.hasStoredSession)
    }

    func testSendEmailCode_successPostsEmailAndClearsError() async throws {
        AuthViewModelMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/auth/email/code")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let body = try XCTUnwrap(Self.decodeBody(AuthViewModelMockURLProtocol.lastRequestBody))
            XCTAssertEqual(body["email"] as? String, "reader@example.com")
            return (Self.messageResponseJSON(), Self.makeResponse(url: request.url, statusCode: 200))
        }

        await authViewModel.sendEmailCode(email: "reader@example.com")

        XCTAssertNil(authViewModel.errorMessage)
        XCTAssertFalse(authViewModel.isLoading)
    }

    func testSendEmailCode_networkFailureShowsLocalServiceMessage() async {
        AuthViewModelMockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        await authViewModel.sendEmailCode(email: "reader@example.com")

        XCTAssertEqual(authViewModel.errorMessage, "无法连接本地 Folio API，请先启动后端服务。")
        XCTAssertFalse(authViewModel.isLoading)
    }

    func testSendEmailCode_rateLimitShowsCooldownMessage() async {
        AuthViewModelMockURLProtocol.requestHandler = { request in
            (Self.errorResponseJSON("please wait before requesting another code"), Self.makeResponse(url: request.url, statusCode: 429))
        }

        await authViewModel.sendEmailCode(email: "reader@example.com")

        XCTAssertEqual(authViewModel.errorMessage, "验证码请求太频繁，请稍后再试。")
    }

    func testVerifyEmailCode_unauthorizedShowsInvalidCodeMessage() async {
        AuthViewModelMockURLProtocol.requestHandler = { request in
            (Self.errorResponseJSON("invalid or expired verification code"), Self.makeResponse(url: request.url, statusCode: 401))
        }

        await authViewModel.verifyEmailCode(email: "reader@example.com", code: "123456")

        XCTAssertEqual(authViewModel.errorMessage, "验证码无效或已过期，请重新输入。")
        XCTAssertEqual(authViewModel.authState, .unknown)
    }

    private static func authResponseJSON() -> Data {
        """
        {
            "access_token": "new_access",
            "refresh_token": "new_refresh",
            "expires_in": 7200,
            "user": {
                "id": "user-1",
                "subscription": "free",
                "monthly_quota": 30,
                "current_month_count": 0,
                "preferred_language": "zh-Hans",
                "created_at": "2025-01-01T00:00:00Z",
                "updated_at": "2025-01-01T00:00:00Z"
            }
        }
        """.data(using: .utf8)!
    }

    private static func messageResponseJSON() -> Data {
        """
        {
            "message": "verification code sent"
        }
        """.data(using: .utf8)!
    }

    private static func errorResponseJSON(_ message: String) -> Data {
        """
        {
            "error": "\(message)"
        }
        """.data(using: .utf8)!
    }

    private static func makeUserDTO() -> UserDTO {
        UserDTO(
            id: "user-1",
            email: "reader@example.com",
            nickname: "Reader",
            avatarUrl: nil,
            subscription: "free",
            subscriptionExpiresAt: nil,
            monthlyQuota: 30,
            currentMonthCount: 0,
            preferredLanguage: "zh-Hans",
            createdAt: Date(timeIntervalSince1970: 1_735_689_600),
            updatedAt: Date(timeIntervalSince1970: 1_735_689_600),
            syncEpoch: nil
        )
    }

    private static func makeResponse(url: URL?, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url ?? URL(string: "https://test.folio.app")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    private static func decodeBody(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
