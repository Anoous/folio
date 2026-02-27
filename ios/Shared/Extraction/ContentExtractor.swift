import Foundation

enum ExtractionError: Error {
    case invalidURL
    case timeout
    case contentTooShort
    case memoryLimitExceeded
    case extractionFailed(Error)
}

struct ContentExtractor {
    static let totalTimeout: TimeInterval = 8
    static let minimumContentLength = 50
    static let memoryLimitBytes: UInt64 = 100 * 1024 * 1024 // 100MB

    func extract(url: URL) async throws -> ExtractionResult {
        guard url.scheme == "http" || url.scheme == "https" else {
            throw ExtractionError.invalidURL
        }

        guard currentMemoryUsage() < Self.memoryLimitBytes else {
            throw ExtractionError.memoryLimitExceeded
        }

        return try await withThrowingTaskGroup(of: ExtractionResult.self) { group in
            group.addTask {
                try await self.performExtraction(url: url)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(Self.totalTimeout * 1_000_000_000))
                throw ExtractionError.timeout
            }

            guard let result = try await group.next() else {
                throw ExtractionError.timeout
            }
            group.cancelAll()
            return result
        }
    }

    private func performExtraction(url: URL) async throws -> ExtractionResult {
        let html: String
        let readability: ReadabilityResult
        let markdown: String

        do {
            html = try await HTMLFetcher().fetch(url: url)
            readability = try ReadabilityExtractor().extract(html: html, url: url)
            markdown = try HTMLToMarkdownConverter().convert(html: readability.contentHTML)
        } catch {
            throw ExtractionError.extractionFailed(error)
        }

        guard markdown.count >= Self.minimumContentLength else {
            throw ExtractionError.contentTooShort
        }

        return ExtractionResult(
            title: readability.title,
            author: readability.author,
            siteName: readability.siteName,
            excerpt: readability.excerpt,
            markdownContent: markdown,
            wordCount: countWords(markdown),
            extractedAt: Date()
        )
    }

    // MARK: - Word Count

    func countWords(_ text: String) -> Int {
        var chineseCount = 0
        var nonChineseWords = 0
        var inWord = false

        for scalar in text.unicodeScalars {
            if isCJKCharacter(scalar) {
                chineseCount += 1
                if inWord {
                    nonChineseWords += 1
                    inWord = false
                }
            } else if scalar.properties.isWhitespace || scalar == "\n" {
                if inWord {
                    nonChineseWords += 1
                    inWord = false
                }
            } else if scalar.properties.isAlphabetic || scalar.properties.isNumeric {
                inWord = true
            }
        }

        if inWord {
            nonChineseWords += 1
        }

        return chineseCount + nonChineseWords
    }

    func isCJKCharacter(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return (value >= 0x4E00 && value <= 0x9FFF) ||   // CJK Unified Ideographs
               (value >= 0x3400 && value <= 0x4DBF) ||   // CJK Extension A
               (value >= 0xF900 && value <= 0xFAFF) ||   // CJK Compatibility Ideographs
               (value >= 0x20000 && value <= 0x2A6DF) || // CJK Extension B
               (value >= 0x2A700 && value <= 0x2B73F) || // CJK Extension C
               (value >= 0x2B740 && value <= 0x2B81F)    // CJK Extension D
    }

    // MARK: - Memory Monitoring

    func currentMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rawPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rawPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return info.resident_size
    }
}

// MARK: - Unicode.Scalar.Properties helpers

private extension Unicode.Scalar.Properties {
    var isAlphabetic: Bool {
        return generalCategory == .uppercaseLetter ||
               generalCategory == .lowercaseLetter ||
               generalCategory == .titlecaseLetter ||
               generalCategory == .modifierLetter ||
               generalCategory == .otherLetter
    }

    var isNumeric: Bool {
        return generalCategory == .decimalNumber
    }
}
