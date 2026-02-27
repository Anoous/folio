import Foundation

enum HTMLFetchError: Error {
    case invalidURL
    case invalidContentType(String)
    case responseTooLarge(Int)
    case encodingError
    case networkError(Error)
    case httpError(Int)
}

struct HTMLFetcher {
    static let defaultTimeout: TimeInterval = 5
    static let maxResponseSize = 2 * 1024 * 1024 // 2MB

    private let sessionConfiguration: URLSessionConfiguration?

    init(sessionConfiguration: URLSessionConfiguration? = nil) {
        self.sessionConfiguration = sessionConfiguration
    }

    func fetch(url: URL) async throws -> String {
        let config = sessionConfiguration ?? URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = Self.defaultTimeout
        config.timeoutIntervalForResource = Self.defaultTimeout
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw HTMLFetchError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTMLFetchError.httpError(0)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw HTMLFetchError.httpError(httpResponse.statusCode)
        }

        // Content-Type check
        if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
            let lowered = contentType.lowercased()
            guard lowered.contains("text/html") || lowered.contains("text/xml") || lowered.contains("application/xhtml") else {
                throw HTMLFetchError.invalidContentType(contentType)
            }
        }

        // Size check
        guard data.count <= Self.maxResponseSize else {
            throw HTMLFetchError.responseTooLarge(data.count)
        }

        // Encoding detection
        if let html = decodeHTML(data: data, response: httpResponse) {
            return html
        }

        throw HTMLFetchError.encodingError
    }

    private func decodeHTML(data: Data, response: HTTPURLResponse) -> String? {
        // Try charset from Content-Type header
        if let contentType = response.value(forHTTPHeaderField: "Content-Type") {
            let charset = extractCharset(from: contentType)
            if let encoding = encodingFromCharset(charset) {
                if let html = String(data: data, encoding: encoding) {
                    return html
                }
            }
        }

        // Try UTF-8
        if let html = String(data: data, encoding: .utf8) {
            return html
        }

        // Try detecting from meta tag in first bytes
        if let partial = String(data: data.prefix(4096), encoding: .ascii) {
            let charset = extractMetaCharset(from: partial)
            if let encoding = encodingFromCharset(charset) {
                if let html = String(data: data, encoding: encoding) {
                    return html
                }
            }
        }

        // Fallback: ISO Latin 1 (always succeeds for any byte sequence)
        return String(data: data, encoding: .isoLatin1)
    }

    private func extractCharset(from contentType: String) -> String? {
        let parts = contentType.components(separatedBy: ";")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces).lowercased()
            if trimmed.hasPrefix("charset=") {
                return String(trimmed.dropFirst("charset=".count))
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "\"", with: "")
            }
        }
        return nil
    }

    private func extractMetaCharset(from html: String) -> String? {
        // Match <meta charset="...">
        if let range = html.range(of: #"charset=["\']?([^"\';\s>]+)"#, options: .regularExpression) {
            let match = html[range]
            let charset = match.replacingOccurrences(of: "charset=", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            return charset.lowercased()
        }
        return nil
    }

    private func encodingFromCharset(_ charset: String?) -> String.Encoding? {
        guard let charset = charset?.lowercased() else { return nil }
        switch charset {
        case "utf-8", "utf8":
            return .utf8
        case "gbk", "gb2312", "gb18030":
            let cfEncoding = CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
            return String.Encoding(rawValue: cfEncoding)
        case "big5":
            let cfEncoding = CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.big5.rawValue)
            )
            return String.Encoding(rawValue: cfEncoding)
        case "iso-8859-1", "latin1":
            return .isoLatin1
        case "ascii":
            return .ascii
        default:
            return nil
        }
    }
}
