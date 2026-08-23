extension DemoStore {
    func markdownExport(for article: DemoArticle) -> String {
        var sections = [
            "# \(article.title)",
            "",
            "- 来源：\(article.source)",
            "- 原文：\(article.url?.absoluteString ?? article.source)"
        ]

        let articleNote = articleNote(for: article.id)
        if !articleNote.isEmpty {
            sections.append(contentsOf: [
                "",
                "## 文章笔记",
                "",
                articleNote
            ])
        }

        let articleHighlights = highlights(for: article.id)
        if !articleHighlights.isEmpty {
            sections.append(contentsOf: ["", "## 高亮与笔记"])
            for highlight in articleHighlights {
                sections.append(contentsOf: ["", "> \(highlight.quote)"])
                if !highlight.note.isEmpty {
                    sections.append(contentsOf: ["", highlight.note])
                }
            }
        }

        return sections.joined(separator: "\n")
    }
}
