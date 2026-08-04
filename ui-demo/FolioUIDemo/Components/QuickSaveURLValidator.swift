import Foundation

enum QuickSaveURLValidator {
    static func normalizedURL(from input: String) -> URL? {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return nil }

        let candidate = trimmedInput.contains("://")
            ? trimmedInput
            : "https://\(trimmedInput)"

        guard
            let components = URLComponents(string: candidate),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = components.host,
            host.contains("."),
            let url = components.url
        else {
            return nil
        }

        return url
    }

    static func displayHost(from input: String) -> String {
        normalizedURL(from: input)?.host() ?? "链接"
    }
}
