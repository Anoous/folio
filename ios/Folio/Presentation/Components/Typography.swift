import SwiftUI

enum Typography {
    // MARK: - Interface Fonts (Dynamic Type enabled)

    /// SF Pro Display, ~20pt, Semibold — scales with .title3
    static let navTitle = Font.system(.title3, design: .default, weight: .semibold)

    /// SF Pro Display, ~28pt, Bold — scales with .title
    static let pageTitle = Font.system(.title, design: .default, weight: .bold)

    /// SF Pro Text, ~17pt, Semibold — scales with .headline
    static let listTitle = Font.system(.headline, weight: .semibold)

    /// SF Pro Text, ~15pt, Regular — scales with .subheadline
    static let body = Font.system(.subheadline)

    /// SF Pro Text, ~13pt, Regular — scales with .footnote
    static let caption = Font.system(.footnote)

    // MARK: - Editorial Card Fonts (Home page)

    /// New York (serif), ~17pt — article titles on home cards
    static let cardTitle = Font.system(.headline, design: .serif)

    /// New York (serif), ~17pt, semibold — unread article titles
    static let cardTitleUnread = Font.system(.headline, design: .serif).weight(.semibold)

    /// SF Pro Text, ~15pt — article summaries on home cards
    static let cardSummary = Font.system(.subheadline)

    /// SF Pro Text, ~13pt — source + time on home cards
    static let cardMeta = Font.system(.footnote)

    /// New York (serif), ~24pt — empty state headline
    static let emptyHeadline = Font.system(.title2, design: .serif)

    /// SF Pro Text, ~13pt, Medium — scales with .footnote
    static let tag = Font.system(.footnote, weight: .medium)

    // MARK: - Article Fonts (Chinese)

    /// Noto Serif SC, 28pt, Bold
    static let articleTitle = Font.custom("NotoSerifSC-Bold", size: 28)

    /// Noto Serif SC, 17pt, Regular, line height 1.7
    static let articleBody = Font.custom("Noto Serif SC", size: 17)

    /// SF Mono, 14pt, Regular
    static let articleCode = Font.system(size: 14, weight: .regular, design: .monospaced)

    /// Noto Serif SC, 16pt, Regular (used for quotes)
    static let articleQuote = Font.custom("NotoSerifSC-Regular", size: 16)

    /// Line spacing for articleBody (line height 1.7 → 17 * 0.7 = 11.9)
    static let articleBodyLineSpacing: CGFloat = 11.9

    // MARK: - Reader Heading Fonts (downgraded from article title)

    /// Returns a heading font for the reader, sized below the 28pt article title.
    /// Georgia only has Regular/Bold — no SemiBold variant.
    static func readerHeadingFont(level: Int, family: ReadingFontFamily) -> Font {
        switch family {
        case .notoSerif:
            switch level {
            case 1: return Font.custom("NotoSerifSC-SemiBold", size: 22)
            case 2: return Font.custom("NotoSerifSC-SemiBold", size: 19)
            case 3: return Font.custom("NotoSerifSC-SemiBold", size: 17)
            case 4: return Font.custom("NotoSerifSC-Medium", size: 17)
            case 5: return Font.custom("NotoSerifSC-Medium", size: 15)
            default: return Font.custom("NotoSerifSC-Medium", size: 15)
            }
        case .system:
            switch level {
            case 1: return Font.system(size: 22, weight: .semibold)
            case 2: return Font.system(size: 19, weight: .semibold)
            case 3: return Font.system(size: 17, weight: .semibold)
            case 4: return Font.system(size: 17, weight: .medium)
            case 5: return Font.system(size: 15, weight: .medium)
            default: return Font.system(size: 15, weight: .medium)
            }
        case .serif:
            switch level {
            case 1: return Font.custom("Georgia-Bold", size: 22)
            case 2: return Font.custom("Georgia-Bold", size: 19)
            case 3: return Font.custom("Georgia", size: 17)
            case 4: return Font.custom("Georgia", size: 17)
            case 5: return Font.custom("Georgia", size: 15)
            default: return Font.custom("Georgia", size: 15)
            }
        }
    }
}

/// Dynamic Type–aware article metrics.
/// Instantiate with `@State private var metrics = ScaledArticleMetrics()` in reader views.
struct ScaledArticleMetrics {
    @ScaledMetric(relativeTo: .title) var titleSize: CGFloat = 28
    @ScaledMetric(relativeTo: .body)  var bodySize: CGFloat = 17
    @ScaledMetric(relativeTo: .caption) var codeSize: CGFloat = 14
    @ScaledMetric(relativeTo: .body)  var quoteSize: CGFloat = 16
    @ScaledMetric(relativeTo: .body)  var lineSpacing: CGFloat = 11.9
}
