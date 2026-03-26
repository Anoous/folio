import Foundation

/// Errors that can be displayed to users. Conforming types provide a localized
/// user-facing message and a developer-facing log context.
protocol UserFacingError: Error {
    /// Message shown to the user (localized, no technical jargon).
    var userMessage: String { get }
    /// Context for logging (method, parameters, technical details).
    var logContext: String { get }
}

// MARK: - APIError + UserFacingError

extension APIError: UserFacingError {
    var userMessage: String {
        switch self {
        case .invalidURL:
            return String(localized: "error.invalidURL", defaultValue: "Invalid link")
        case .encodingFailed:
            return String(localized: "error.requestFailed", defaultValue: "Request failed")
        case .decodingFailed:
            return String(localized: "error.unexpected", defaultValue: "Unexpected response from server")
        case .unauthorized:
            return String(localized: "error.unauthorized", defaultValue: "Please sign in again")
        case .forbidden:
            return String(localized: "error.forbidden", defaultValue: "Access denied")
        case .notFound:
            return String(localized: "error.notFound", defaultValue: "Content not found")
        case .quotaExceeded:
            return String(localized: "error.quotaExceeded", defaultValue: "Monthly limit reached")
        case .conflict:
            return String(localized: "error.conflict", defaultValue: "Already exists")
        case .serverError:
            return String(localized: "error.server", defaultValue: "Server error, please try again")
        case .networkError:
            return String(localized: "error.network", defaultValue: "Network unavailable")
        case .serverMessage(let msg):
            return msg
        }
    }

    var logContext: String {
        switch self {
        case .decodingFailed(let detail): return "decodingFailed: \(detail)"
        case .serverError(let code): return "serverError: HTTP \(code)"
        case .networkError(let detail): return "networkError: \(detail)"
        case .serverMessage(let msg): return "serverMessage: \(msg)"
        default: return String(describing: self)
        }
    }
}

// MARK: - SharedDataError + UserFacingError

extension SharedDataError: UserFacingError {
    var userMessage: String {
        switch self {
        case .duplicateURL:
            return String(localized: "error.duplicateURL", defaultValue: "Already saved")
        case .quotaExceeded:
            return String(localized: "error.quotaExceeded", defaultValue: "Monthly limit reached")
        case .containerUnavailable:
            return String(localized: "error.storage", defaultValue: "Storage unavailable")
        case .invalidInput:
            return String(localized: "error.invalidInput", defaultValue: "Invalid input")
        }
    }

    var logContext: String { String(describing: self) }
}

// MARK: - KeychainError + UserFacingError

extension KeychainError: UserFacingError {
    var userMessage: String {
        String(localized: "error.auth", defaultValue: "Authentication error")
    }

    var logContext: String { String(describing: self) }
}

// MARK: - FTS5Error + UserFacingError

extension FTS5Error: UserFacingError {
    var userMessage: String {
        String(localized: "error.search", defaultValue: "Search unavailable")
    }

    var logContext: String {
        switch self {
        case .cannotOpenDatabase: return "FTS5: cannot open database"
        case .queryFailed(let detail): return "FTS5: query failed — \(detail)"
        }
    }
}
