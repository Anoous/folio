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

    var supportsClientExtraction: Bool {
        switch self {
        case .youtube: return false
        default: return true
        }
    }

    static func detect(from urlString: String) -> SourceType {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased() else {
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

// MARK: - Article Model

@Model
final class Article {
    @Attribute(.unique) var id: UUID
    var url: String
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
    var serverID: String?
    var extractionSourceRaw: String
    var clientExtractedAt: Date?

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

    var extractionSource: ExtractionSource {
        get { ExtractionSource(rawValue: extractionSourceRaw) ?? .none }
        set { extractionSourceRaw = newValue.rawValue }
    }

    /// User-friendly title: uses title if available, otherwise extracts a readable form from URL.
    var displayTitle: String {
        if let title, !title.isEmpty {
            return title
        }
        // Extract host + path from URL for a cleaner display
        if let url = URL(string: url), let host = url.host {
            let path = url.path
            if path.isEmpty || path == "/" {
                return host
            }
            // Show last meaningful path component
            let lastComponent = url.lastPathComponent
            if !lastComponent.isEmpty && lastComponent != "/" {
                return "\(host) - \(lastComponent)"
            }
            return host
        }
        return url
    }

    init(
        url: String,
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
        self.createdAt = Date()
        self.updatedAt = Date()
        self.publishedAt = nil
        self.lastReadAt = nil
        self.wordCount = 0
        self.language = nil
        self.aiConfidence = 0
        self.fetchError = nil
        self.retryCount = 0
        self.sourceTypeRaw = sourceType.rawValue
        self.syncStateRaw = SyncState.pendingUpload.rawValue
        self.serverID = nil
        self.extractionSourceRaw = ExtractionSource.none.rawValue
        self.clientExtractedAt = nil
    }
}
