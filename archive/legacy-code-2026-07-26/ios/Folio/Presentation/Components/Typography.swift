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

    // MARK: - v3 Card Fonts (LXGW WenKai TC — prototype 01)

    /// LXGW WenKai TC, 28px, Regular — page title "页集"
    static let v3PageTitle = Font.custom("LXGWWenKaiTC-Regular", size: 28)

    /// LXGW WenKai TC, 24px, Regular — hero card title (P01)
    static let v3HeroTitle = Font.custom("LXGWWenKaiTC-Regular", size: 24)

    /// LXGW WenKai TC, 17px, Regular — card title (read state)
    static let v3CardTitle = Font.custom("LXGWWenKaiTC-Regular", size: 17)

    /// LXGW WenKai TC, 17px, Medium — card title (unread state)
    static let v3CardTitleUnread = Font.custom("LXGWWenKaiTC-Medium", size: 17)

    /// LXGW WenKai TC, 16px, Italic — hero insight (P01)
    static let v3HeroInsight = Font.custom("LXGWWenKaiTC-Regular", size: 16).italic()

    /// LXGW WenKai TC, 14px, Italic — card insight (P01)
    static let v3CardInsight = Font.custom("LXGWWenKaiTC-Regular", size: 14).italic()

    /// LXGW WenKai TC, 14px, Regular — section header "今天"/"昨天" (P01)
    static let v3SectionHeader = Font.custom("LXGWWenKaiTC-Regular", size: 14)

    /// LXGW WenKai TC, 22px, Regular — empty state headline (P01)
    static let v3EmptyHeadline = Font.custom("LXGWWenKaiTC-Regular", size: 22)

    /// LXGW WenKai TC, 17px, Regular — echo question (P02)
    static let v3EchoQuestion = Font.custom("LXGWWenKaiTC-Regular", size: 17)

    /// LXGW WenKai TC, 15px, Medium — insight panel main text (P04)
    static let v3InsightMain = Font.custom("LXGWWenKaiTC-Medium", size: 15)

    /// LXGW WenKai TC, 28px, Medium — onboarding page title (P06)
    static let v3OnboardingTitle = Font.custom("LXGWWenKaiTC-Medium", size: 28)

    /// LXGW WenKai TC, 20px, Light — onboarding brand "Folio · 页集" (P06)
    static let v3OnboardingBrand = Font.custom("LXGWWenKaiTC-Light", size: 20)

    /// LXGW WenKai TC, 22px, Medium — settings comparison title (P07)
    static let v3ComparisonTitle = Font.custom("LXGWWenKaiTC-Medium", size: 22)

    /// LXGW WenKai TC, 20px, Regular — settings login prompt header (P07)
    static let v3LoginPromptTitle = Font.custom("LXGWWenKaiTC-Regular", size: 20)

    // MARK: - v3 Article Fonts (Reader — prototype 04)

    /// LXGW WenKai TC, 26px, Medium — article title in reader (P04)
    static let v3ArticleTitle = Font.custom("LXGWWenKaiTC-Medium", size: 26)

    /// LXGW WenKai TC, 17px, Regular — article body in reader (P04)
    static let v3ArticleBody = Font.custom("LXGWWenKaiTC-Regular", size: 17)

    /// LXGW WenKai TC, 20px, Medium — H2 in reader (P04)
    static let v3ArticleH2 = Font.custom("LXGWWenKaiTC-Medium", size: 20)

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
