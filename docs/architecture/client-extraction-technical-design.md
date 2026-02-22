# 客户端内容提取 — 技术设计文档

> 创建日期：2026-02-22
> 关联文档：[需求文档](client-extraction-requirements.md) | [三份深度研究对比分析](../research/client-extraction-comparative-analysis.md) | [客户端抓取调研](client-scraping-research.md) | [系统架构](system-design.md)

---

## 一、架构概述

### 1.1 当前架构（Before）

```
┌─── Share Extension ───┐     ┌─── Main App ────────────┐     ┌─── Server ──────────────────┐
│                        │     │                          │     │                              │
│  URL → SwiftData 保存  │     │  SyncService             │     │  Go API                      │
│  status = pending      │──→──│    .submitPendingArticles │──→──│    → Worker: article:crawl   │
│                        │     │    .pollTask              │     │      → Reader Service (Node) │
│  即时关闭（1.5s）      │     │    .fetchAndUpdateArticle │←──←─│      → Worker: article:ai    │
│                        │     │  article.updateFromDTO()  │     │      → AI Service (Python)   │
└────────────────────────┘     │  status = ready           │     │                              │
                               └──────────────────────────┘     └──────────────────────────────┘

用户等待：分享后 5-15 秒才能阅读正文
```

### 1.2 目标架构（After）

```
┌─── Share Extension ──────────────────────────────────────┐
│                                                           │
│  URL → SwiftData 保存（status = pending）                 │
│    ↓                                                      │
│  SourceType == .youtube?  ──YES──→  跳过提取，关闭        │
│    ↓ NO                                                   │
│  ContentExtractor.extract(url:)                           │
│    ├─ HTMLFetcher.fetch(url:)     ← 5s 超时, 2MB 上限     │
│    ├─ ReadabilityExtractor.extract(html:url:)             │
│    ├─ HTMLToMarkdownConverter.convert(html:)              │
│    └─→ ExtractionResult                                   │
│  ↓                                                        │
│  成功 → SharedDataManager.updateWithExtraction(...)       │
│         status = clientReady, extractionSource = client   │
│  失败 → 不变（URL-only, status = pending）                │
│                                                           │
│  关闭 Extension（最长 ~10s）                              │
└───────────────────────────────────────────────────────────┘
                    ↓ 后台同步（Main App）
┌─── Main App ─────────────────────────┐     ┌─── Server ───────────────────────┐
│                                       │     │                                  │
│  SyncService                          │     │  完整管线不变：                   │
│    .submitPendingArticles             │──→──│    crawl → AI → ready            │
│    .pollTask                          │     │                                  │
│    .fetchAndUpdateArticle             │←──←─│  ArticleDTO (markdownContent)    │
│  article.updateFromDTO()              │     │                                  │
│    → 服务端 markdown 覆盖客户端内容    │     └──────────────────────────────────┘
│    → status = ready                   │
│    → extractionSource = server        │
│                                       │
└───────────────────────────────────────┘

用户等待：分享后 2-5 秒即可阅读正文（客户端提取）
         30 秒后静默升级为服务端质量内容 + AI 分析
```

---

## 二、新增组件

### 2.1 ContentExtractor — 提取编排器

**位置**：`ios/Shared/Extraction/ContentExtractor.swift`

负责编排整个提取管线：fetch → parse → convert → 返回结果。对外暴露单一入口方法。

```swift
import Foundation

/// 客户端内容提取编排器。
/// 管理提取管线：HTML 下载 → Readability 正文提取 → Markdown 转换。
/// 在 Share Extension 中运行，受 8 秒总超时和 100MB 内存硬限制保护。
final class ContentExtractor {

    /// 提取超时（秒）
    static let totalTimeoutSeconds: TimeInterval = 8

    /// 内存安全阈值（字节）— 100MB（Extension 硬限 120MB，留 20MB 余量）
    static let memoryThresholdBytes: UInt64 = 100 * 1024 * 1024

    /// 提取结果的最小正文长度（字符数），低于此视为失败
    static let minimumContentLength = 50

    private let fetcher = HTMLFetcher()

    /// 从 URL 提取文章内容。
    /// - Parameter url: 文章 URL
    /// - Returns: 提取结果；失败时返回 nil
    func extract(url: URL) async -> ExtractionResult? {
        // 1. 检查内存水位
        guard currentMemoryUsage() < Self.memoryThresholdBytes else {
            return nil
        }

        // 2. 带总超时的提取管线
        let result = await withTaskTimeout(seconds: Self.totalTimeoutSeconds) {
            // 2a. 下载 HTML
            guard let (html, responseURL) = try await self.fetcher.fetch(url: url) else {
                return nil as ExtractionResult?
            }

            // 2b. 检查内存
            guard self.currentMemoryUsage() < Self.memoryThresholdBytes else {
                return nil
            }

            // 2c. Readability 提取正文
            let extracted = try ReadabilityExtractor.extract(html: html, url: responseURL)
            guard let articleHTML = extracted.content,
                  !articleHTML.isEmpty else {
                return nil
            }

            // 2d. HTML → Markdown 转换
            let markdown = try HTMLToMarkdownConverter.convert(html: articleHTML)
            guard markdown.count >= Self.minimumContentLength else {
                return nil
            }

            // 2e. 组装结果
            return ExtractionResult(
                title: extracted.title,
                author: extracted.byline,
                siteName: extracted.siteName,
                excerpt: extracted.excerpt,
                markdownContent: markdown,
                wordCount: Self.countWords(markdown),
                extractedAt: Date()
            )
        }

        return result
    }

    // MARK: - Private

    private func currentMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }

    private static func countWords(_ text: String) -> Int {
        // 中英文混合字数统计：英文按空格分词，中文按字符计数
        var count = 0
        text.enumerateSubstrings(
            in: text.startIndex...,
            options: [.byWords, .localized]
        ) { _, _, _, _ in
            count += 1
        }
        return count
    }

    /// 带超时的 async 任务包装
    private func withTaskTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T?
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { try? await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }

            // 先完成的胜出
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }
}
```

### 2.2 HTMLFetcher — HTML 下载器

**位置**：`ios/Shared/Extraction/HTMLFetcher.swift`

URLSession 包装器，负责下载 HTML 内容，带 2MB 大小上限和 5 秒超时。

```swift
import Foundation

/// HTML 下载器。使用 URLSession 获取网页 HTML 内容。
/// - 下载超时：5 秒
/// - 大小上限：2MB
/// - 自动跟随重定向（最多 5 次，URLSession 默认行为）
/// - 仅接受 text/html Content-Type
final class HTMLFetcher {

    /// 下载大小上限（字节）：2MB
    static let maxDownloadBytes = 2 * 1024 * 1024

    /// 下载超时（秒）
    static let timeoutSeconds: TimeInterval = 5

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = Self.timeoutSeconds
        config.timeoutIntervalForResource = Self.timeoutSeconds
        config.httpMaximumConnectionsPerHost = 1
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// 下载 URL 对应的 HTML 内容。
    /// - Parameter url: 目标 URL
    /// - Returns: (HTML 字符串, 最终响应 URL) 的元组；失败时返回 nil
    func fetch(url: URL) async throws -> (String, URL)? {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            return nil
        }

        // 检查 Content-Type
        if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
           !contentType.contains("text/html") && !contentType.contains("text/xml")
           && !contentType.contains("application/xhtml") {
            return nil
        }

        // 检查大小
        guard data.count <= Self.maxDownloadBytes else {
            return nil
        }

        // 编码检测与转换
        let encoding = Self.detectEncoding(from: httpResponse, data: data)
        guard let html = String(data: data, encoding: encoding)
                ?? String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }

        let responseURL = httpResponse.url ?? url
        return (html, responseURL)
    }

    // MARK: - Private

    private static func detectEncoding(
        from response: HTTPURLResponse,
        data: Data
    ) -> String.Encoding {
        // 优先从 Content-Type header 检测
        if let contentType = response.value(forHTTPHeaderField: "Content-Type"),
           let charset = contentType.components(separatedBy: "charset=").last?
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: ";").first?.lowercased() {
            switch charset {
            case "utf-8": return .utf8
            case "gbk", "gb2312", "gb18030": return .init(rawValue: 2147484705) // CFStringEncodings.GB_18030_2000
            case "big5": return .init(rawValue: 2147484038) // CFStringEncodings.big5
            case "iso-8859-1", "latin1": return .isoLatin1
            case "shift_jis", "shift-jis": return .shiftJIS
            case "euc-kr": return .init(rawValue: 2147486016) // CFStringEncodings.EUC_KR
            default: return .utf8
            }
        }
        return .utf8
    }
}
```

### 2.3 ReadabilityExtractor — 正文提取器

**位置**：`ios/Shared/Extraction/ReadabilityExtractor.swift`

封装 `swift-readability` 库（Mozilla Readability 算法的纯 Swift 移植），从 HTML 中提取正文和元数据。

```swift
import Foundation
import SwiftReadability // lake-of-fire/swift-readability (fork)

/// 封装 swift-readability 库的正文提取器。
/// 输入原始 HTML，输出清洗后的正文 HTML + 元数据。
enum ReadabilityExtractor {

    /// Readability 提取结果
    struct Result {
        let title: String?
        let byline: String?      // 作者
        let siteName: String?
        let excerpt: String?      // 摘要/描述
        let content: String?      // 清洗后的正文 HTML
        let textContent: String?  // 纯文本（无 HTML 标签）
        let length: Int           // 正文字符数
    }

    /// 从 HTML 提取正文。
    /// - Parameters:
    ///   - html: 原始 HTML 字符串
    ///   - url: 文章 URL（用于解析相对链接）
    /// - Returns: 提取结果
    static func extract(html: String, url: URL) throws -> Result {
        let readability = try Readability(html: html, url: url)
        let article = try readability.parse()

        return Result(
            title: article.title,
            byline: article.byline,
            siteName: article.siteName,
            excerpt: article.excerpt,
            content: article.content,
            textContent: article.textContent,
            length: article.length
        )
    }
}
```

> **注意**：`swift-readability` 的实际 API 以 fork 后的版本为准。上述代码展示的是期望接口，具体属性名可能需要在 fork/集成时调整。

### 2.4 HTMLToMarkdownConverter — HTML→Markdown 转换器

**位置**：`ios/Shared/Extraction/HTMLToMarkdownConverter.swift`

递归 DOM 遍历转换器（~150 行），将 Readability 输出的干净 HTML 转换为 Markdown。输出格式与 `MarkdownRenderer`（基于 `apple/swift-markdown`）的解析能力对齐。

```swift
import Foundation
import SwiftSoup

/// 将 Readability 输出的干净 HTML 转换为 Markdown。
///
/// 支持的元素：
/// - 标题：h1-h6 → # ~ ######
/// - 段落：p → 空行分隔
/// - 链接：a[href] → [text](url)
/// - 图片：img[src] → ![alt](src)
/// - 粗体：strong/b → **text**
/// - 斜体：em/i → *text*
/// - 删除线：del/s → ~~text~~
/// - 行内代码：code → `code`
/// - 代码块：pre > code → ```language\ncode\n```
/// - 引用块：blockquote → > text
/// - 无序列表：ul > li → - item
/// - 有序列表：ol > li → 1. item
/// - 表格：table → | col | col |
/// - 分隔线：hr → ---
/// - 换行：br → \n
enum HTMLToMarkdownConverter {

    /// 将 HTML 字符串转换为 Markdown。
    /// - Parameter html: Readability 输出的干净 HTML
    /// - Returns: Markdown 字符串
    static func convert(html: String) throws -> String {
        let document = try SwiftSoup.parse(html)
        guard let body = document.body() else { return "" }

        var lines: [String] = []
        try convertChildren(of: body, into: &lines)

        // 合并连续空行为单个空行
        return lines.joined(separator: "\n")
            .replacingOccurrences(
                of: "\\n{3,}",
                with: "\n\n",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Block-Level Conversion

    private static func convertChildren(
        of element: Element,
        into lines: inout [String]
    ) throws {
        for node in element.getChildNodes() {
            if let el = node as? Element {
                try convertElement(el, into: &lines)
            } else if let text = node as? TextNode {
                let content = text.getWholeText()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !content.isEmpty {
                    lines.append(content)
                }
            }
        }
    }

    private static func convertElement(
        _ element: Element,
        into lines: inout [String]
    ) throws {
        let tag = element.tagName().lowercased()

        switch tag {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(String(tag.last!))!
            let prefix = String(repeating: "#", count: level)
            let text = try convertInline(element)
            lines.append("")
            lines.append("\(prefix) \(text)")
            lines.append("")

        case "p":
            let text = try convertInline(element)
            if !text.isEmpty {
                lines.append("")
                lines.append(text)
                lines.append("")
            }

        case "blockquote":
            var innerLines: [String] = []
            try convertChildren(of: element, into: &innerLines)
            let quoted = innerLines
                .filter { !$0.isEmpty }
                .map { "> \($0)" }
                .joined(separator: "\n")
            lines.append("")
            lines.append(quoted)
            lines.append("")

        case "ul":
            lines.append("")
            for li in try element.select(":root > li") {
                let text = try convertInline(li)
                lines.append("- \(text)")
            }
            lines.append("")

        case "ol":
            lines.append("")
            for (index, li) in try element.select(":root > li").enumerated() {
                let text = try convertInline(li)
                lines.append("\(index + 1). \(text)")
            }
            lines.append("")

        case "pre":
            let code = try element.select("code").first()
            let language = try code?.className() ?? ""
            let content = try (code ?? element).text()
            lines.append("")
            lines.append("```\(language)")
            lines.append(content)
            lines.append("```")
            lines.append("")

        case "table":
            try convertTable(element, into: &lines)

        case "hr":
            lines.append("")
            lines.append("---")
            lines.append("")

        case "br":
            lines.append("")

        case "img":
            let src = try element.attr("src")
            let alt = try element.attr("alt")
            if !src.isEmpty {
                lines.append("")
                lines.append("![\(alt)](\(src))")
                lines.append("")
            }

        case "figure":
            // figure 通常包含 img + figcaption
            if let img = try element.select("img").first() {
                let src = try img.attr("src")
                let alt = try img.attr("alt")
                let caption = try element.select("figcaption").first()?.text() ?? alt
                if !src.isEmpty {
                    lines.append("")
                    lines.append("![\(caption)](\(src))")
                    lines.append("")
                }
            }

        case "div", "section", "article", "main", "header", "footer", "aside":
            // 容器元素：递归处理子元素
            try convertChildren(of: element, into: &lines)

        default:
            // 未知块元素：尝试作为内联处理
            let text = try convertInline(element)
            if !text.isEmpty {
                lines.append(text)
            }
        }
    }

    // MARK: - Table Conversion

    private static func convertTable(
        _ table: Element,
        into lines: inout [String]
    ) throws {
        var headers: [String] = []
        var rows: [[String]] = []

        // 提取表头
        for th in try table.select("thead th, thead td, tr:first-of-type th") {
            headers.append(try th.text())
        }

        // 提取表体
        let bodyRows = try table.select("tbody tr, tr")
        for row in bodyRows {
            let cells = try row.select("td, th")
            // 跳过已经用作表头的行
            if cells.isEmpty() { continue }
            let isHeaderRow = try cells.allSatisfy { try $0.tagName() == "th" }
            if isHeaderRow && headers.isEmpty {
                headers = try cells.map { try $0.text() }
            } else {
                rows.append(try cells.map { try $0.text() })
            }
        }

        guard !headers.isEmpty || !rows.isEmpty else { return }

        // 如果没有表头，用第一行数据作为表头
        if headers.isEmpty, let first = rows.first {
            headers = first
            rows.removeFirst()
        }

        let colCount = headers.count

        lines.append("")
        lines.append("| \(headers.joined(separator: " | ")) |")
        lines.append("| \(headers.map { _ in "---" }.joined(separator: " | ")) |")
        for row in rows {
            // 对齐列数
            let padded = row + Array(repeating: "", count: max(0, colCount - row.count))
            lines.append("| \(padded.prefix(colCount).joined(separator: " | ")) |")
        }
        lines.append("")
    }

    // MARK: - Inline Conversion

    private static func convertInline(_ element: Element) throws -> String {
        var result = ""
        for node in element.getChildNodes() {
            if let text = node as? TextNode {
                result += text.getWholeText()
            } else if let el = node as? Element {
                let tag = el.tagName().lowercased()
                switch tag {
                case "strong", "b":
                    let inner = try convertInline(el)
                    if !inner.isEmpty { result += "**\(inner)**" }
                case "em", "i":
                    let inner = try convertInline(el)
                    if !inner.isEmpty { result += "*\(inner)*" }
                case "del", "s":
                    let inner = try convertInline(el)
                    if !inner.isEmpty { result += "~~\(inner)~~" }
                case "code":
                    let code = try el.text()
                    result += "`\(code)`"
                case "a":
                    let href = try el.attr("href")
                    let text = try convertInline(el)
                    if href.isEmpty {
                        result += text
                    } else {
                        result += "[\(text)](\(href))"
                    }
                case "img":
                    let src = try el.attr("src")
                    let alt = try el.attr("alt")
                    if !src.isEmpty { result += "![\(alt)](\(src))" }
                case "br":
                    result += "\n"
                case "span":
                    result += try convertInline(el)
                default:
                    result += try convertInline(el)
                }
            }
        }
        return result
    }
}
```

**与 MarkdownRenderer 的兼容性**：

`MarkdownRenderer` 使用 `apple/swift-markdown` 的 `Document(parsing:)` 解析 Markdown。上述转换器输出的 Markdown 元素完全对应 `MarkdownSwiftUIVisitor` 中已实现的 visit 方法：

| 转换器输出 | swift-markdown AST 节点 | MarkdownSwiftUIVisitor 方法 |
|-----------|----------------------|---------------------------|
| `# Heading` | `Heading` | `visitHeading(_:)` |
| 段落文本 | `Paragraph` | `visitParagraph(_:)` |
| `**bold**` | `Strong` | `inlineText(_:)` → `.bold()` |
| `*italic*` | `Emphasis` | `inlineText(_:)` → `.italic()` |
| `` `code` `` | `InlineCode` | `inlineText(_:)` → `Typography.articleCode` |
| `[text](url)` | `Link` | `inlineText(_:)` → `AttributedString` with `.link` |
| `![alt](src)` | `Image` | `visitImage(_:)` / `visitParagraph(_:)` |
| `` ```code``` `` | `CodeBlock` | `visitCodeBlock(_:)` |
| `> quote` | `BlockQuote` | `visitBlockQuote(_:)` |
| `- item` | `UnorderedList` | `visitUnorderedList(_:)` |
| `1. item` | `OrderedList` | `visitOrderedList(_:)` |
| `---` | `ThematicBreak` | `visitThematicBreak(_:)` |
| `\| table \|` | `Table` | `visitTable(_:)` |
| `~~strike~~` | `Strikethrough` | `inlineText(_:)` → `.strikethrough()` |

### 2.5 ExtractionResult — 提取结果数据结构

**位置**：`ios/Shared/Extraction/ExtractionResult.swift`

```swift
import Foundation

/// 客户端内容提取的结果。
struct ExtractionResult {
    /// 文章标题
    let title: String?

    /// 文章作者
    let author: String?

    /// 站点名称
    let siteName: String?

    /// 文章摘要/描述
    let excerpt: String?

    /// Markdown 格式的正文内容
    let markdownContent: String

    /// 正文字数
    let wordCount: Int

    /// 提取完成时间
    let extractedAt: Date
}
```

---

## 三、现有模型变更

### 3.1 Article 模型

**文件**：`ios/Folio/Domain/Models/Article.swift`

新增两个字段和一个枚举值：

```swift
// --- 新增枚举 ---

enum ExtractionSource: String, Codable {
    case none     // 未提取（默认值，向后兼容）
    case client   // 客户端提取
    case server   // 服务端提取
}

// --- ArticleStatus 枚举新增 ---

enum ArticleStatus: String, Codable {
    case pending
    case clientReady  // 新增：客户端已提取到内容
    case processing
    case ready
    case failed
}

// --- Article 模型新增字段 ---

@Model
final class Article {
    // ... 现有字段保持不变 ...

    /// 内容提取来源：none / client / server
    var extractionSourceRaw: String  // 默认值 "none"

    /// 客户端提取完成时间
    var clientExtractedAt: Date?

    // --- 计算属性 ---

    var extractionSource: ExtractionSource {
        get { ExtractionSource(rawValue: extractionSourceRaw) ?? .none }
        set { extractionSourceRaw = newValue.rawValue }
    }

    // --- init 更新 ---

    init(url: String, ...) {
        // ... 现有初始化代码 ...
        self.extractionSourceRaw = ExtractionSource.none.rawValue  // 新增
        self.clientExtractedAt = nil                                // 新增
    }
}
```

**向后兼容性**：
- `extractionSourceRaw` 默认值为 `"none"`，SwiftData 轻量级迁移自动处理
- `clientExtractedAt` 为可选类型，默认 `nil`
- `ArticleStatus.clientReady` 是新增枚举值，旧代码中 `ArticleStatus(rawValue: "clientReady")` 返回 `nil`，由 `?? .pending` 兜底处理
- 服务端不感知 `clientReady` 状态（状态仅在客户端本地使用，提交到服务端时仍为 `pending`）

### 3.2 SourceType 过滤

**文件**：`ios/Folio/Domain/Models/Article.swift`

在 `SourceType` 枚举中新增属性：

```swift
extension SourceType {
    /// 是否支持客户端提取
    var supportsClientExtraction: Bool {
        switch self {
        case .youtube: return false
        case .web, .wechat, .twitter, .weibo, .zhihu, .newsletter: return true
        }
    }
}
```

---

## 四、现有组件变更

### 4.1 ShareViewController 变更

**文件**：`ios/ShareExtension/ShareViewController.swift`

在 `saveURL(_:)` 方法中，保存 URL 成功后触发客户端提取：

```swift
@MainActor
private func saveURL(_ urlString: String) {
    do {
        let schema = Schema([Article.self, Tag.self, Category.self])
        // ... 现有 ModelContainer 初始化代码 ...
        let container = try ModelContainer(for: schema, configurations: [config])
        let manager = SharedDataManager(context: container.mainContext)

        // 现有：检查配额
        let isPro = UserDefaults.appGroup.bool(forKey: "is_pro_user")
        guard SharedDataManager.canSave(isPro: isPro) else {
            showState(.quotaExceeded)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.dismiss()
            }
            return
        }

        // 现有：保存 URL
        let article = try manager.saveArticle(url: urlString)
        SharedDataManager.incrementQuota()

        // 现有：配额警告检查
        let currentCount = SharedDataManager.currentMonthCount()
        let quota = SharedDataManager.freeMonthlyQuota
        if !isPro && currentCount >= Int(Double(quota) * 0.9) {
            showState(.quotaWarning(remaining: quota - currentCount))
        } else {
            showState(.saved)
        }

        // ===== 新增：客户端提取 =====
        if article.sourceType.supportsClientExtraction,
           let url = URL(string: urlString) {
            showState(.extracting)  // 新增状态
            Task {
                let extractor = ContentExtractor()
                if let result = await extractor.extract(url: url) {
                    manager.updateWithExtraction(result, for: article)
                    showState(.extracted)  // 新增状态
                } else {
                    // 提取失败：恢复之前的状态（saved 或 quotaWarning）
                    if !isPro && currentCount >= Int(Double(quota) * 0.9) {
                        showState(.quotaWarning(remaining: quota - currentCount))
                    } else {
                        showState(.saved)
                    }
                }
            }
        }
        // ===== 新增结束 =====

    } catch SharedDataError.duplicateURL {
        showState(.duplicate)
    } catch {
        showState(.offline)
    }

    // 延长关闭时间以容纳提取（从 1.5s 增加到 ~10s，但 Task 完成后可提前关闭）
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
        self?.dismiss()
    }
}
```

**关键设计决策**：
- URL 保存在提取**之前**完成 → 提取失败不影响保存
- `showState(.extracting)` 让用户知道提取正在进行
- 提取在 `Task` 中异步执行，不阻塞 UI
- 关闭时间从 1.5 秒延长到最多 10 秒，但提取通常在 2-5 秒内完成后会更新状态
- YouTube 等不支持客户端提取的类型直接跳过

### 4.2 CompactShareView 变更

**文件**：`ios/ShareExtension/CompactShareView.swift`

新增 `.extracting` 和 `.extracted` 状态：

```swift
enum ShareState {
    case saving
    case saved
    case extracting     // 新增：正在提取内容
    case extracted      // 新增：提取完成，文章可读
    case duplicate
    case offline
    case quotaExceeded
    case quotaWarning(remaining: Int)
}
```

UI 实现：

```swift
case .extracting:
    ProgressView()
    Text(String(localized: "share.extracting", defaultValue: "Extracting article..."))
        .font(Typography.listTitle)
    Text(String(localized: "share.extractingSubtitle", defaultValue: "Saving for offline reading"))
        .font(Typography.caption)
        .foregroundStyle(Color.folio.textSecondary)

case .extracted:
    Image(systemName: "doc.richtext")
        .font(.system(size: 44))
        .foregroundStyle(Color.folio.success)
    Text(String(localized: "share.extracted", defaultValue: "Article ready"))
        .font(Typography.listTitle)
    Text(String(localized: "share.extractedSubtitle", defaultValue: "Full content saved for offline reading"))
        .font(Typography.caption)
        .foregroundStyle(Color.folio.textSecondary)
    Button {
        if let url = URL(string: "folio://library") {
            openURL(url)
        }
        onDismiss()
    } label: {
        Text(String(localized: "share.openApp", defaultValue: "Open Folio"))
            .font(Typography.caption)
            .foregroundStyle(Color.folio.accent)
    }
```

同步更新 `showState(_:)` 中的触觉反馈：

```swift
case .extracting:
    break  // 无触觉反馈
case .extracted:
    let generator = UINotificationFeedbackGenerator()
    generator.notificationOccurred(.success)
```

### 4.3 SharedDataManager 变更

**文件**：`ios/Folio/Data/SwiftData/SharedDataManager.swift`

新增方法将提取结果写入 Article：

```swift
extension SharedDataManager {
    /// 将客户端提取结果更新到 Article。
    /// - Parameters:
    ///   - result: 提取结果
    ///   - article: 目标 Article
    @MainActor
    func updateWithExtraction(_ result: ExtractionResult, for article: Article) {
        if let title = result.title, !title.isEmpty {
            article.title = title
        }
        if let author = result.author, !author.isEmpty {
            article.author = author
        }
        if let siteName = result.siteName, !siteName.isEmpty {
            article.siteName = siteName
        }

        article.markdownContent = result.markdownContent
        article.wordCount = result.wordCount
        article.status = .clientReady
        article.extractionSource = .client
        article.clientExtractedAt = result.extractedAt
        article.updatedAt = Date()

        try? context.save()
    }
}
```

### 4.4 DTOMapping 变更

**文件**：`ios/Folio/Data/Network/DTOMapping.swift`

`updateFromDTO(_:)` 方法中，确保服务端结果覆盖客户端内容，并更新 `extractionSource`：

```swift
extension Article {
    func updateFromDTO(_ dto: ArticleDTO) {
        serverID = dto.id
        url = dto.url
        title = dto.title
        author = dto.author
        siteName = dto.siteName
        faviconURL = dto.faviconUrl
        coverImageURL = dto.coverImageUrl
        if let content = dto.markdownContent {
            markdownContent = content
            extractionSource = .server  // 新增：标记来源为服务端
        }
        summary = dto.summary
        keyPoints = dto.keyPoints ?? []
        aiConfidence = dto.aiConfidence ?? 0
        statusRaw = dto.status
        sourceTypeRaw = dto.sourceType
        fetchError = dto.fetchError
        retryCount = dto.retryCount
        isFavorite = dto.isFavorite
        isArchived = dto.isArchived
        readProgress = max(readProgress, dto.readProgress)
        if let serverDate = dto.lastReadAt {
            if let localDate = lastReadAt {
                lastReadAt = max(localDate, serverDate)
            } else {
                lastReadAt = serverDate
            }
        }
        publishedAt = dto.publishedAt
        wordCount = dto.wordCount
        language = dto.language
        updatedAt = dto.updatedAt
        syncState = .synced
    }
}
```

**变更说明**：
- 唯一的变更是在 `if let content = dto.markdownContent` 块内新增一行 `extractionSource = .server`
- 服务端 `markdownContent` 非空时，无条件覆盖客户端内容（服务端是权威质量层）
- `statusRaw = dto.status` 会将 `clientReady` 更新为服务端返回的 `ready` 或 `processing`

### 4.5 SyncService — 无变更

**文件**：`ios/Folio/Data/Sync/SyncService.swift`

SyncService **无需代码变更**。现有流程已满足需求：

1. `submitPendingArticles(_:)` 将文章提交到服务端 — `clientReady` 状态的文章同样需要提交（它的 `syncState` 仍为 `.pendingUpload`）
2. `pollTask(taskId:articleLocalId:)` 轮询服务端处理状态
3. `fetchAndUpdateArticle(serverID:localID:)` 获取完整 DTO 并调用 `article.updateFromDTO(dto)` — 上述 DTOMapping 变更确保服务端内容正确覆盖

**注意**：`submitPendingArticles` 应同时处理 `pending` 和 `clientReady` 状态的文章。调用方在查询待提交文章时，需将 `clientReady` 包含在查询条件中。当前的查询逻辑（在调用方如 HomeViewModel 中）需要确认是否已覆盖 `clientReady` 状态，如果是按 `syncState == .pendingUpload` 查询则已自动覆盖。

---

## 五、XcodeGen 项目配置变更

**文件**：`ios/project.yml`

### 5.1 新增 SPM 依赖

```yaml
packages:
  swift-markdown:
    url: https://github.com/apple/swift-markdown.git
    from: "0.5.0"
  Nuke:
    url: https://github.com/kean/Nuke.git
    from: "12.8.0"
  KeychainAccess:
    url: https://github.com/kishikawakatsumi/KeychainAccess.git
    from: "4.2.2"
  # 新增
  SwiftSoup:
    url: https://github.com/scinfu/SwiftSoup.git
    from: "2.7.0"
  swift-readability:
    url: https://github.com/anthropics/swift-readability.git  # Folio fork
    from: "0.1.0"
```

> **注意**：`swift-readability` 的 URL 指向 Folio 的 fork 仓库（具体组织名待定）。该 fork 需要将 Swift 版本从 6.2 降级到 5.9，并确保 iOS 17 兼容。

### 5.2 ShareExtension target 变更

```yaml
  ShareExtension:
    type: app-extension
    platform: iOS
    sources:
      - path: ShareExtension
        excludes:
          - "**/.DS_Store"
      - path: Folio/Domain/Models
      - path: Folio/Data/SwiftData/DataManager.swift
      - path: Folio/Data/SwiftData/SharedDataManager.swift
      - path: Folio/Presentation/Components/Spacing.swift
      - path: Folio/Presentation/Components/Typography.swift
      - path: Folio/Presentation/Components/CornerRadius.swift
      - path: Folio/Presentation/Components/FolioButton.swift
      - path: Folio/Presentation/Components/ReadingFontFamily.swift
      - path: Folio/Utils/Extensions/Color+Folio.swift
      - path: Shared/Extraction     # 新增：提取模块
    # ... 其余配置不变 ...
    dependencies:                     # 新增
      - package: SwiftSoup
      - package: swift-readability
```

### 5.3 Folio 主 target

主 app target 无需依赖 SwiftSoup 或 swift-readability（提取仅在 Share Extension 中运行）。但 `Shared/Extraction/ExtractionResult.swift` 如果在主 app 中也需要访问，可共享。

---

## 六、内存管理

### 6.1 内存监控

`ContentExtractor.currentMemoryUsage()` 使用 `mach_task_basic_info` 获取当前进程的驻留内存大小。在以下时机检查：

1. 提取开始前（避免在已高内存时启动提取）
2. HTML 下载完成后（DOM 解析前）

### 6.2 大小限制

- **HTML 下载**：`HTMLFetcher.maxDownloadBytes = 2MB`
- 使用 `URLSessionConfiguration.ephemeral`：不写磁盘缓存
- 下载完成后立即检查 `data.count`

### 6.3 Autorelease Pool

提取管线中的大量临时字符串操作应在 autorelease pool 中执行，确保及时释放。`ContentExtractor.extract(url:)` 的实际实现应在关键位置包裹 `autoreleasepool`：

```swift
// 在 Readability 提取和 Markdown 转换之间
autoreleasepool {
    // Readability 输出的中间 HTML 在这里被 Markdown 转换器消费后释放
}
```

### 6.4 安全阈值

| 阈值 | 值 | 作用 |
|------|-----|------|
| Apple Extension 硬限制 | 120MB | 超过则被系统 kill |
| Folio 软限制 | 100MB | 主动中止提取，降级保存 |
| 预期峰值 | 35-65MB | 正常提取的内存范围 |
| 安全余量 | 20-85MB | 给系统和 SwiftData 留空间 |

---

## 七、测试策略

### 7.1 单元测试

| 测试文件 | 测试对象 | 关键用例 |
|---------|---------|---------|
| `HTMLToMarkdownConverterTests.swift` | `HTMLToMarkdownConverter` | 标题、段落、链接、图片、列表、代码块、引用、表格、嵌套结构 |
| `ContentExtractorTests.swift` | `ContentExtractor` | Mock HTML → 预期 `ExtractionResult`；超时处理；空内容处理 |
| `HTMLFetcherTests.swift` | `HTMLFetcher` | 超大响应截断；非 HTML Content-Type 拒绝；编码检测 |
| `ReadabilityExtractorTests.swift` | `ReadabilityExtractor` | 标准博客 HTML → 正文提取正确；无正文 HTML → 返回空 |
| `ArticleModelTests.swift` | `Article` 新字段 | `extractionSource` 默认值；`clientReady` 状态流转 |
| `SharedDataManagerExtractionTests.swift` | `updateWithExtraction` | 字段正确填充；status 更新；重复调用幂等 |
| `DTOMappingExtractionTests.swift` | `updateFromDTO` | 服务端覆盖客户端内容；`extractionSource` 更新 |

### 7.2 Fixture 测试

准备真实 HTML 文件作为测试 fixture，覆盖目标内容源：

| Fixture | 来源 | 验证点 |
|---------|------|--------|
| `chinese-blog.html` | 中文博客 | 中文标题、正文、图片提取 |
| `wechat-article.html` | 微信公众号 | 公众号特殊 HTML 结构 |
| `medium-article.html` | Medium | 英文长文、代码块、引用 |
| `twitter-thread.html` | Twitter/X | 推文提取 |
| `zhihu-column.html` | 知乎专栏 | 知乎特殊结构 |
| `table-heavy.html` | 含复杂表格的页面 | 表格转换 |
| `minimal-content.html` | 极少正文的页面 | 最小内容阈值判断 |
| `large-page.html` | 超大 HTML（>1MB） | 性能和内存测试 |

### 7.3 内存 Profiling

使用 Instruments → Allocations 测量：

1. 正常博客文章的提取内存峰值
2. 大型页面（~2MB HTML）的提取内存峰值
3. 连续提取多篇文章后的内存趋势

**通过标准**：峰值 ≤ 65MB（正常页面），≤ 100MB（极端页面）

### 7.4 测试文件位置

所有测试文件位于 `ios/FolioTests/` 目录下。Fixture HTML 文件位于 `ios/FolioTests/Fixtures/Extraction/` 目录下。

新增测试文件后需运行 `cd ios && xcodegen generate` 重新生成 Xcode 项目。

---

## 八、新增文件清单

```
ios/
├── Shared/
│   └── Extraction/
│       ├── ContentExtractor.swift        # 提取编排器
│       ├── HTMLFetcher.swift              # HTML 下载器
│       ├── ReadabilityExtractor.swift     # Readability 封装
│       ├── HTMLToMarkdownConverter.swift  # HTML→Markdown 转换器
│       └── ExtractionResult.swift        # 提取结果数据结构
├── FolioTests/
│   ├── HTMLToMarkdownConverterTests.swift
│   ├── ContentExtractorTests.swift
│   ├── HTMLFetcherTests.swift
│   ├── ReadabilityExtractorTests.swift
│   ├── SharedDataManagerExtractionTests.swift
│   ├── DTOMappingExtractionTests.swift
│   └── Fixtures/
│       └── Extraction/
│           ├── chinese-blog.html
│           ├── wechat-article.html
│           ├── medium-article.html
│           ├── twitter-thread.html
│           ├── zhihu-column.html
│           ├── table-heavy.html
│           ├── minimal-content.html
│           └── large-page.html
└── project.yml                           # 更新：新增 SPM 依赖 + Shared/Extraction 源码路径
```

**修改的现有文件**：

| 文件 | 变更内容 |
|------|---------|
| `ios/Folio/Domain/Models/Article.swift` | 新增 `ExtractionSource` 枚举、`ArticleStatus.clientReady`、`extractionSourceRaw` 和 `clientExtractedAt` 字段、`SourceType.supportsClientExtraction` |
| `ios/ShareExtension/ShareViewController.swift` | `saveURL(_:)` 中新增客户端提取逻辑，关闭延时调整 |
| `ios/ShareExtension/CompactShareView.swift` | `ShareState` 新增 `.extracting` 和 `.extracted`，对应 UI |
| `ios/Folio/Data/SwiftData/SharedDataManager.swift` | 新增 `updateWithExtraction(_:for:)` 方法 |
| `ios/Folio/Data/Network/DTOMapping.swift` | `updateFromDTO` 中新增 `extractionSource = .server` |
| `ios/project.yml` | 新增 SwiftSoup + swift-readability 依赖，ShareExtension sources 新增 Shared/Extraction |

---

## 九、风险与缓解

| 风险 | 严重度 | 缓解措施 |
|------|--------|---------|
| swift-readability 项目太新（8 commits, 2 stars） | 高 | Fork 到 Folio org 维护；fixture 测试建立质量基线；备选：自己基于 SwiftSoup 实现核心 Readability 算法（~300 行） |
| Swift 6.2 要求与 Folio Swift 5.9 不兼容 | 中 | Fork 后降级——该库核心逻辑不依赖 Swift 6.2 特性（主要是并发标注） |
| HTML→Markdown 转换质量 | 中 | 自写转换器针对 Readability 已清洗的 HTML（结构简单）；fixture 测试覆盖主要站点 |
| 中文/日文页面提取质量 | 中 | 微信公众号、知乎等目标站点专项测试；必要时补充自定义规则 |
| Share Extension 关闭时间延长影响用户体验 | 低 | 提取通常 2-5 秒完成；提取期间展示进度指示器；提取失败立即回退到 saved 状态 |
| SwiftData 轻量级迁移失败 | 低 | 新增字段都有默认值（`"none"` 和 `nil`），SwiftData 自动处理；测试覆盖迁移场景 |
