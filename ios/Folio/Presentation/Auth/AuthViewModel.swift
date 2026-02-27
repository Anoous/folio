import Foundation
import AuthenticationServices

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
        guard keychainManager.accessToken != nil else {
            authState = .signedOut
            return
        }

        do {
            let response = try await apiClient.refreshAuth()
            currentUser = response.user
            authState = .signedIn
        } catch let error as APIError {
            switch error {
            case .unauthorized, .forbidden:
                // Server explicitly rejected credentials — sign out
                try? keychainManager.clearTokens()
                authState = .signedOut
            default:
                // Network error or server unavailable — keep signed in with cached token
                authState = .signedIn
            }
        } catch {
            // Network/other error — keep signed in with cached token
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
            } catch {
                errorMessage = String(localized: "auth.error.network", defaultValue: "Could not connect to the server. Please check your network and try again.")
            }

        case .failure:
            errorMessage = String(localized: "auth.error.cancelled", defaultValue: "Sign-in was cancelled.")
        }
    }

    // MARK: - Dev Login

    #if DEBUG
    func loginDev() async {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            let response = try await apiClient.loginDev()
            currentUser = response.user
            authState = .signedIn
        } catch {
            errorMessage = "Dev login failed: \(error.localizedDescription)"
        }
    }
    #endif

    // MARK: - Sign Out

    func signOut() {
        try? keychainManager.clearTokens()
        currentUser = nil
        authState = .signedOut
    }
}
