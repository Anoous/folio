import Foundation

enum AuthNavigationPolicy {
    static func shouldDismissSignIn(isAuthenticated: Bool?) -> Bool {
        isAuthenticated == true
    }
}
