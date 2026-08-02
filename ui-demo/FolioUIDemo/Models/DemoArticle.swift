import Foundation

struct DemoArticle: Identifiable, Hashable {
    let id: UUID
    let monogram: String
    let title: String
    let source: String
    let age: String
    let summary: String
    let status: DemoArticleStatus
    let readerTitle: String
    let originalParagraphs: [String]
    let pullQuote: String
    let insight: String
    let insightPoints: [String]

    init(
        id: UUID = UUID(),
        monogram: String,
        title: String,
        source: String,
        age: String,
        summary: String,
        status: DemoArticleStatus,
        readerTitle: String,
        originalParagraphs: [String],
        pullQuote: String,
        insight: String,
        insightPoints: [String]
    ) {
        self.id = id
        self.monogram = monogram
        self.title = title
        self.source = source
        self.age = age
        self.summary = summary
        self.status = status
        self.readerTitle = readerTitle
        self.originalParagraphs = originalParagraphs
        self.pullQuote = pullQuote
        self.insight = insight
        self.insightPoints = insightPoints
    }
}
