import Foundation
import AuthenticationServices
import os

enum AuthState: Equatable {
    case unknown
    case signedOut
    case signedIn
}

@MainActor
@Observable
final class AuthViewModel {
    var authState: AuthState = .unknown
    var currentUser: UserDTO?
    var errorMessage: String?
    var isLoading = false

    var isAuthenticated: Bool {
        authState == .signedIn
    }

    private let apiClient: APIClient
    private let keychainManager: KeyChainManager

    init(apiClient: APIClient = .shared, keychainManager: KeyChainManager = .shared) {
        self.apiClient = apiClient
        self.keychainManager = keychainManager
    }

    // MARK: - Check Existing Auth

    func checkExistingAuth() async {
        guard keychainManager.hasStoredSession else {
            currentUser = nil
            authState = .signedOut
            return
        }

        do {
            let response = try await apiClient.refreshAuth()
            currentUser = response.user
            authState = .signedIn
            FolioLogger.auth.info("existing auth validated")
        } catch let error as APIError {
            switch error {
            case .unauthorized, .forbidden:
                FolioLogger.auth.info("existing auth rejected: \(error)")
                try? keychainManager.clearTokens()
                currentUser = nil
                authState = .signedOut
            default:
                FolioLogger.auth.debug("auth check network error, keeping signed in: \(error)")
                authState = .signedIn
            }
        } catch {
            FolioLogger.auth.debug("auth check error, keeping signed in: \(error)")
            authState = .signedIn
        }
    }

    // MARK: - Apple Sign-In

    func handleAppleSignIn(result: Result<ASAuthorization, Error>) async {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityTokenData = credential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                errorMessage = String(localized: "auth.error.credentials", defaultValue: "Unable to verify your Apple ID. Please try again.")
                return
            }

            let email = credential.email
            let fullName = credential.fullName
            let nickname = [fullName?.givenName, fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")

            do {
                let response = try await apiClient.loginWithApple(
                    identityToken: identityToken,
                    email: email,
                    nickname: nickname.isEmpty ? nil : nickname
                )
                currentUser = response.user
                authState = .signedIn
                FolioLogger.auth.info("Apple sign-in succeeded")
            } catch {
                FolioLogger.auth.error("Apple sign-in failed: \(error)")
                errorMessage = String(localized: "auth.error.network", defaultValue: "Could not connect to the server. Please check your network and try again.")
            }

        case .failure:
            errorMessage = String(localized: "auth.error.cancelled", defaultValue: "Sign-in was cancelled.")
        }
    }

    // MARK: - Email Auth

    func sendEmailCode(email: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await apiClient.sendEmailCode(email: email)
            FolioLogger.auth.info("verification code sent to \(email)")
        } catch let error as APIError {
            FolioLogger.auth.error("send code failed: \(error)")
            errorMessage = sendCodeErrorMessage(for: error)
        } catch {
            FolioLogger.auth.error("send code failed: \(error)")
            errorMessage = Self.networkUnavailableMessage
        }
    }

    func verifyEmailCode(email: String, code: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await apiClient.verifyEmailCode(email: email, code: code)
            currentUser = response.user
            authState = .signedIn
            FolioLogger.auth.info("email login succeeded")
        } catch let error as APIError {
            FolioLogger.auth.error("email verify failed: \(error)")
            switch error {
            case .unauthorized:
                errorMessage = "验证码无效或已过期，请重新输入。"
            case .networkError:
                errorMessage = Self.networkUnavailableMessage
            case .serverError:
                errorMessage = "验证码服务暂时不可用，请稍后再试。"
            case .quotaExceeded:
                errorMessage = "尝试次数过多，请稍后再试。"
            case .serverMessage(let message):
                errorMessage = Self.localizedServerMessage(message)
            default:
                errorMessage = "无法完成验证，请稍后再试。"
            }
        } catch {
            FolioLogger.auth.error("email verify failed: \(error)")
            errorMessage = Self.networkUnavailableMessage
        }
    }

    // MARK: - Sign Out

    func signOut(revokeRemoteSession: Bool = true) async {
        let refreshToken = keychainManager.refreshToken

        if revokeRemoteSession, let refreshToken {
            do {
                try await apiClient.logout(refreshToken: refreshToken)
                FolioLogger.auth.info("remote session revoked")
            } catch let error as APIError {
                FolioLogger.auth.error("remote sign-out failed: \(error)")
            } catch {
                FolioLogger.auth.error("remote sign-out failed: \(error)")
            }
        }

        try? keychainManager.clearTokens()
        currentUser = nil
        authState = .signedOut
        FolioLogger.auth.info("user signed out")
    }

    private func sendCodeErrorMessage(for error: APIError) -> String {
        switch error {
        case .quotaExceeded:
            "验证码请求太频繁，请稍后再试。"
        case .networkError:
            Self.networkUnavailableMessage
        case .serverError:
            "验证码服务暂时不可用，请稍后再试。"
        case .serverMessage(let message):
            Self.localizedServerMessage(message)
        default:
            "无法发送验证码，请稍后再试。"
        }
    }

    private static var networkUnavailableMessage: String {
        #if DEBUG
        "无法连接本地 Folio API，请先启动后端服务。"
        #else
        "无法连接 Folio 服务，请检查网络后重试。"
        #endif
    }

    private static func localizedServerMessage(_ message: String) -> String {
        switch message {
        case "please wait before requesting another code":
            "验证码请求太频繁，请稍后再试。"
        case "invalid or expired verification code":
            "验证码无效或已过期，请重新输入。"
        default:
            "请求失败，请稍后再试。"
        }
    }
}
