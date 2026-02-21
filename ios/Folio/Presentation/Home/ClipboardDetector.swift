import Foundation
import SwiftUI
import SwiftData

@MainActor
@Observable
final class ClipboardDetector {
    var detectedURL: URL?
    var shouldShowPrompt = false

    private let context: ModelContext
    private var ignoredURLs: Set<String>

    init(context: ModelContext) {
        self.context = context
        let stored = UserDefaults.standard.stringArray(forKey: "ignoredClipboardURLs") ?? []
        self.ignoredURLs = Set(stored)
    }

    func checkClipboard() {
        guard let url = extractURL() else {
            shouldShowPrompt = false
            detectedURL = nil
            return
        }

        let urlString = url.absoluteString

        // Check if already ignored
        guard !ignoredURLs.contains(urlString) else {
            shouldShowPrompt = false
            return
        }

        // Check if already saved
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { $0.url == urlString }
        )
        guard (try? context.fetchCount(descriptor)) == 0 else {
            shouldShowPrompt = false
            return
        }

        detectedURL = url
        shouldShowPrompt = true
    }

    func markAsIgnored() {
        guard let url = detectedURL else { return }
        ignoredURLs.insert(url.absoluteString)
        UserDefaults.standard.set(Array(ignoredURLs), forKey: "ignoredClipboardURLs")
        shouldShowPrompt = false
        detectedURL = nil
    }

    func dismissPrompt() {
        shouldShowPrompt = false
        detectedURL = nil
    }

    private func extractURL() -> URL? {
        if let url = UIPasteboard.general.url {
            return url
        }
        if let string = UIPasteboard.general.string,
           let url = URL(string: string),
           url.scheme?.hasPrefix("http") == true {
            return url
        }
        return nil
    }
}
