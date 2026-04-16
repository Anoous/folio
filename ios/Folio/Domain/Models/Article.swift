import Foundation
import SwiftData

// MARK: - Enums

enum ArticleStatus: String, Codable {
    case pending
    case processing
    case ready
    case failed
    case clientReady
}

enum ExtractionSource: String, Codable {
    case none
    case client
    case server
}

enum SourceType: String, Codable {
    case web
    case wechat
    case twitter
    case weibo
    case zhihu
    case newsletter
    case youtube
    case manual
    case screenshot
    case voice

    var supportsClientExtraction: Bool {
        switch self {
        case .youtube, .manual, .screenshot, .voice:
            return false
        default: return true
        }
    }

    static func detect(from urlString: String) -> SourceType {
        guard let url = URL(string: urlString),
              let host = url.host()?.lowercased() else {
            return .web
        }

        if host.contains("mp.weixin.qq.com") || host.contains("weixin.qq.com") {
            return .wechat
        } else if host.contains("twitter.com") || host.contains("x.com") {
            return .twitter
        } else if host.contains("weibo.com") || host.contains("weibo.cn") {
            return .weibo
        } else if host.contains("zhihu.com") {
            return .zhihu
        } else if host.contains("youtube.com") || host.contains("youtu.be") {
            return .youtube
        } else if host.contains("substack.com") || host.contains("mailchi.mp") {
            return .newsletter
        } else {
            return .web
        }
    }
}

enum SyncState: String, Codable {
    case pendingUpload
    case synced
    case pendingUpdate
    case conflict
}

enum ArticleDirtyField: String, Codable, CaseIterable {
    case favorite
    case archived
    case readProgress
}

// MARK: - Article Model

@Model
final class Article {
    @Attribute(.unique) var id: UUID
    var url: String?
    var title: String?
    var author: String?
    var siteName: String?
    var faviconURL: String?
    var coverImageURL: String?
    var markdownContent: String?
    var summary: String?
    var keyPoints: [String]
    @Relationship(inverse: \Tag.articles) var tags: [Tag]
    @Relationship var category: Category?
    var statusRaw: String
    var isFavorite: Bool
    var isArchived: Bool
    var readProgress: Double
    var favoriteUpdatedAt: Date?
    var archivedUpdatedAt: Date?
    var readProgressUpdatedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var publishedAt: Date?
    var lastReadAt: Date?
    var wordCount: Int
    var language: String?
    var aiConfidence: Double
    var fetchError: String?
    var retryCount: Int
    var sourceTypeRaw: String
    var syncStateRaw: String
    // Optional for backward-compatible migration from older stores that don't have this column yet.
    var dirtyFieldsRaw: [String]?
    var serverID: String?
    var extractionSourceRaw: String = ExtractionSource.none.rawValue
    var clientExtractedAt: Date?
    var localImagePath: String?  // App Group relative path for screenshot images

    var status: ArticleStatus {
        get { ArticleStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var sourceType: SourceType {
        get { SourceType(rawValue: sourceTypeRaw) ?? .web }
        set { sourceTypeRaw = newValue.rawValue }
    }

    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .pendingUpload }
        set { syncStateRaw = newValue.rawValue }
    }

    var dirtyFields: Set<ArticleDirtyField> {
        get { Set((dirtyFieldsRaw ?? []).compactMap(ArticleDirtyField.init(rawValue:))) }
        set { dirtyFieldsRaw = newValue.map(\.rawValue).sorted() }
    }

    func fieldUpdatedAt(for field: ArticleDirtyField) -> Date? {
        switch field {
        case .favorite:
            return favoriteUpdatedAt
        case .archived:
            return archivedUpdatedAt
        case .readProgress:
            return readProgressUpdatedAt
        }
    }

    func setFieldUpdatedAt(_ date: Date?, for field: ArticleDirtyField) {
        switch field {
        case .favorite:
            favoriteUpdatedAt = date
        case .archived:
            archivedUpdatedAt = date
        case .readProgress:
            readProgressUpdatedAt = date
        }
    }

    func effectiveFieldUpdatedAt(for field: ArticleDirtyField) -> Date {
        if let stored = fieldUpdatedAt(for: field) {
            return stored
        }
        if field == .readProgress, let lastReadAt {
            return lastReadAt
        }
        if pendingDirtyFields.contains(field) {
            return updatedAt
        }
        return createdAt
    }

    /// Older builds only stored a coarse pendingUpdate bit.
    /// Treat that legacy state as read-progress-only to avoid replaying stale booleans.
    var pendingDirtyFields: Set<ArticleDirtyField> {
        let fields = dirtyFields
        if !fields.isEmpty {
            return fields
        }
        if syncState == .pendingUpdate {
            return [.readProgress]
        }
        return []
    }

    var extractionSource: ExtractionSource {
        get { ExtractionSource(rawValue: extractionSourceRaw) ?? .none }
        set { extractionSourceRaw = newValue.rawValue }
    }

    // MARK: - Card Tier

    enum CardTier {
        case large     // Rich content: cover image + summary + long article
        case standard  // Normal: has summary or cover image
        case compact   // Short: tweet, voice note, screenshot, or minimal content
    }

    var cardTier: CardTier {
        let hasCover = coverImageURL != nil && !(coverImageURL?.isEmpty ?? true)
        let hasSummary = displaySummary != nil
        let isShortForm = sourceType == .twitter || sourceType == .voice
        let isScreenshot = sourceType == .screenshot

        if isShortForm || isScreenshot { return .compact }
        if status != .ready && status != .clientReady { return .standard }
        if hasCover && hasSummary && wordCount > 500 { return .large }
        return .standard
    }

    /// Summary with markdown syntax stripped for display in cards and AI summary sections.
    var displaySummary: String? {
        guard let summary, !summary.isEmpty else { return nil }
        return Self.stripMarkdown(summary)
    }

    /// Strips markdown syntax to produce plain text.
    static func stripMarkdown(_ text: String) -> String {
        var s = text
        // Remove images: ![alt](url)
        s = s.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]*\)?"#, with: "", options: .regularExpression)
        // Replace complete links with text: [text](url) → text
        s = s.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        // Handle truncated/incomplete links: [text](url... → text
        s = s.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*$"#, with: "$1", options: .regularExpression)
        // Remove leftover brackets: - [text] or standalone [text]
        s = s.replacingOccurrences(of: #"\[([^\]]*)\]"#, with: "$1", options: .regularExpression)
        // Remove heading markers
        s = s.replacingOccurrences(of: #"(?m)^#{1,6}\s+"#, with: "", options: .regularExpression)
        // Remove bold/italic markers
        s = s.replacingOccurrences(of: #"\*{1,3}([^*]+)\*{1,3}"#, with: "$1", options: .regularExpression)
        // Remove inline code backticks
        s = s.replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
        // Remove bare URLs (http/https/protocol-relative)
        s = s.replacingOccurrences(of: #"(?:https?:)?//[^\s)>]+"#, with: "", options: .regularExpression)
        // Remove markdown list markers
        s = s.replacingOccurrences(of: #"(?m)^\s*[-*+]\s+"#, with: "", options: .regularExpression)
        // Collapse whitespace and newlines
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// User-friendly title: uses title if available, otherwise extracts a readable form from URL.
    var displayTitle: String {
        if let title, !title.isEmpty {
            return title
        }
        if let url, let parsed = URL(string: url), let host = parsed.host() {
            let path = parsed.path
            if path.isEmpty || path == "/" {
                return host
            }
            // Show last meaningful path component
            let lastComponent = parsed.lastPathComponent
            if !lastComponent.isEmpty && lastComponent != "/" {
                return "\(host) - \(lastComponent)"
            }
            return host
        }
        if let content = markdownContent, !content.isEmpty {
            let preview = String(content.prefix(50))
            return preview.count < content.count ? preview + "..." : preview
        }
        return String(localized: "article.untitled", defaultValue: "Untitled")
    }

    /// Source name for display in cards: uses siteName for web sources,
    /// localized labels for manual/screenshot/voice.
    var effectiveSourceName: String? {
        switch sourceType {
        case .manual:
            return wordCount < 200
                ? String(localized: "source.thought", defaultValue: "My Thought")
                : String(localized: "source.pasted", defaultValue: "Pasted Content")
        case .screenshot:
            return String(localized: "Screenshot", defaultValue: "截图")
        case .voice:
            return String(localized: "Voice Note", defaultValue: "语音笔记")
        default:
            if let siteName, !siteName.isEmpty {
                return siteName
            }
            return nil
        }
    }

    /// Removes the local image file (if any) from the App Group container.
    func cleanupLocalImage() {
        guard let localPath = localImagePath,
              let containerURL = FileManager.default.containerURL(
                  forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier
              ) else { return }
        let imagePath = containerURL.appendingPathComponent(localPath)
        try? FileManager.default.removeItem(at: imagePath)
    }

    init(
        url: String?,
        title: String? = nil,
        author: String? = nil,
        siteName: String? = nil,
        sourceType: SourceType = .web
    ) {
        self.id = UUID()
        self.url = url
        self.title = title
        self.author = author
        self.siteName = siteName
        self.faviconURL = nil
        self.coverImageURL = nil
        self.markdownContent = nil
        self.summary = nil
        self.keyPoints = []
        self.tags = []
        self.category = nil
        self.statusRaw = ArticleStatus.pending.rawValue
        self.isFavorite = false
        self.isArchived = false
        self.readProgress = 0
        self.favoriteUpdatedAt = nil
        self.archivedUpdatedAt = nil
        self.readProgressUpdatedAt = nil
        self.createdAt = .now
        self.updatedAt = .now
        self.publishedAt = nil
        self.lastReadAt = nil
        self.wordCount = 0
        self.language = nil
        self.aiConfidence = 0
        self.fetchError = nil
        self.retryCount = 0
        self.sourceTypeRaw = sourceType.rawValue
        self.syncStateRaw = SyncState.pendingUpload.rawValue
        self.dirtyFieldsRaw = []
        self.serverID = nil
        self.extractionSourceRaw = ExtractionSource.none.rawValue
        self.clientExtractedAt = nil
    }

    convenience init(content: String, title: String? = nil) {
        self.init(url: nil, title: title, sourceType: .manual)
        self.markdownContent = content
        self.wordCount = Self.countWords(content)
    }

    /// Count words: CJK characters counted individually; non-CJK runs split by whitespace.
    /// Mirrors the server-side `CountWords` in `repository/article.go`.
    static func countWords(_ text: String) -> Int {
        var count = 0
        var inNonCJKRun = false
        for scalar in text.unicodeScalars {
            if Self.isCJK(scalar) {
                if inNonCJKRun {
                    count += 1
                    inNonCJKRun = false
                }
                count += 1
            } else if scalar.properties.isWhitespace || scalar == "\n" {
                if inNonCJKRun {
                    count += 1
                    inNonCJKRun = false
                }
            } else {
                inNonCJKRun = true
            }
        }
        if inNonCJKRun { count += 1 }
        return count
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (0x4E00...0x9FFF).contains(v) ||    // CJK Unified
               (0x3400...0x4DBF).contains(v) ||    // CJK Extension A
               (0x20000...0x2A6DF).contains(v) ||  // CJK Extension B
               (0xF900...0xFAFF).contains(v) ||    // CJK Compatibility
               (0x3000...0x303F).contains(v) ||    // CJK Symbols
               (0x3040...0x309F).contains(v) ||    // Hiragana
               (0x30A0...0x30FF).contains(v) ||    // Katakana
               (0xAC00...0xD7AF).contains(v)       // Hangul
    }
}

// MARK: - SourceType Display

extension SourceType {
    var iconName: String {
        switch self {
        case .wechat: "message.fill"
        case .twitter: "bird"
        case .weibo: "globe.asia.australia"
        case .zhihu: "questionmark.circle"
        case .youtube: "play.rectangle.fill"
        case .newsletter: "envelope.fill"
        case .web: "globe"
        case .manual: "square.and.pencil"
        case .screenshot: "camera.viewfinder"
        case .voice: "mic.fill"
        }
    }

    var displayName: String {
        switch self {
        case .wechat: "WeChat"
        case .twitter: "Twitter"
        case .weibo: "Weibo"
        case .zhihu: "Zhihu"
        case .youtube: "YouTube"
        case .newsletter: "Newsletter"
        case .web: "Web"
        case .manual: String(localized: "source.manual", defaultValue: "Manual")
        case .screenshot: String(localized: "Screenshot", defaultValue: "截图")
        case .voice: String(localized: "Voice Note", defaultValue: "语音笔记")
        }
    }
}
