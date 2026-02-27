// MARK: - KeyChain Manager
import Foundation
import KeychainAccess

enum KeychainError: Error {
    case saveFailed
    case deleteFailed
}

final class KeyChainManager {
    static let shared = KeyChainManager()

    private let keychain: Keychain

    private enum Keys {
        static let accessToken = "access_token"
        static let refreshToken = "refresh_token"
    }

    init(service: String = "com.folio.app") {
        self.keychain = Keychain(service: service)
    }

    func saveTokens(access: String, refresh: String) throws {
        do {
            try keychain.set(access, key: Keys.accessToken)
        } catch {
            throw KeychainError.saveFailed
        }
        do {
            try keychain.set(refresh, key: Keys.refreshToken)
        } catch {
            // Roll back access token on failure
            try? keychain.remove(Keys.accessToken)
            throw KeychainError.saveFailed
        }
    }

    var accessToken: String? {
        try? keychain.get(Keys.accessToken)
    }

    var refreshToken: String? {
        try? keychain.get(Keys.refreshToken)
    }

    func clearTokens() throws {
        do {
            try keychain.remove(Keys.accessToken)
            try keychain.remove(Keys.refreshToken)
        } catch {
            throw KeychainError.deleteFailed
        }
    }
}
