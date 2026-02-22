import Foundation

struct ExtractionResult {
    let title: String?
    let author: String?
    let siteName: String?
    let excerpt: String?
    let markdownContent: String
    let wordCount: Int
    let extractedAt: Date
}
