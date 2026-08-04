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

extension DemoArticle {
    static func processingURL(_ url: URL) -> DemoArticle {
        let host = url.host() ?? "新链接"
        let path = url.path == "/" ? "" : url.path
        let displayURL = host + path

        return DemoArticle(
            monogram: String(host.prefix(2)).lowercased(),
            title: displayURL,
            source: host,
            age: "刚刚",
            summary: "已接收 · 正在获取正文…",
            status: .processing,
            readerTitle: displayURL,
            originalParagraphs: [
                "Folio 已经接收这个链接，正在云端获取并整理正文。处理完成前，你可以先离开当前页面。"
            ],
            pullQuote: "链接已经可靠接收，正文仍在处理中。",
            insight: "正在理解这篇内容，\n完成后会在这里展示核心洞察。",
            insightPoints: [
                "链接已进入你的资料库。",
                "正文获取和内容理解会在云端继续完成。"
            ]
        )
    }
}
