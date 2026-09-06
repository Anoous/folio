import Foundation

enum ReaderOriginalLinkPolicy {
    private static let externalBrowserHosts: Set<String> = [
        "x.com", "www.x.com", "twitter.com", "www.twitter.com",
        "mobile.x.com", "mobile.twitter.com"
    ]

    static func shouldOpenExternally(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        return externalBrowserHosts.contains(host)
    }
}
