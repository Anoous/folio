import Foundation

/// Generic view state for simple CRUD views.
/// NOT suitable for streaming/partial data flows (RAG, search) — use domain-specific state instead.
enum ViewState<T> {
    case idle
    case loading
    case loaded(T)
    case error(String)
    case empty
}

extension ViewState {
    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var value: T? {
        if case .loaded(let v) = self { return v }
        return nil
    }

    var errorMessage: String? {
        if case .error(let msg) = self { return msg }
        return nil
    }
}
