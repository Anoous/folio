import SwiftUI

enum Typography {
    // MARK: - Interface Fonts

    /// SF Pro Display, 20pt, Semibold
    static let navTitle = Font.system(size: 20, weight: .semibold, design: .default)

    /// SF Pro Display, 28pt, Bold
    static let pageTitle = Font.system(size: 28, weight: .bold, design: .default)

    /// SF Pro Text, 17pt, Semibold
    static let listTitle = Font.system(size: 17, weight: .semibold)

    /// SF Pro Text, 15pt, Regular
    static let body = Font.system(size: 15, weight: .regular)

    /// SF Pro Text, 13pt, Regular
    static let caption = Font.system(size: 13, weight: .regular)

    /// SF Pro Text, 13pt, Medium
    static let tag = Font.system(size: 13, weight: .medium)

    // MARK: - Article Fonts (Chinese)

    /// Noto Serif SC, 24pt, Bold
    static let articleTitle = Font.custom("Noto Serif SC", size: 24).weight(.bold)

    /// Noto Serif SC, 17pt, Regular, line height 1.7
    static let articleBody = Font.custom("Noto Serif SC", size: 17)

    /// SF Mono, 14pt, Regular
    static let articleCode = Font.system(size: 14, weight: .regular, design: .monospaced)

    /// Noto Serif SC, 16pt, Italic
    static let articleQuote = Font.custom("Noto Serif SC", size: 16).italic()

    /// Line spacing for articleBody (line height 1.7 → 17 * 0.7 = 11.9)
    static let articleBodyLineSpacing: CGFloat = 11.9
}

// MARK: - View Modifiers

struct TypographyModifier: ViewModifier {
    let font: Font
    let lineSpacing: CGFloat?

    func body(content: Content) -> some View {
        if let lineSpacing {
            content
                .font(font)
                .lineSpacing(lineSpacing)
        } else {
            content
                .font(font)
        }
    }
}

extension View {
    func typography(_ font: Font, lineSpacing: CGFloat? = nil) -> some View {
        modifier(TypographyModifier(font: font, lineSpacing: lineSpacing))
    }

    func articleBodyStyle() -> some View {
        modifier(TypographyModifier(font: Typography.articleBody, lineSpacing: Typography.articleBodyLineSpacing))
    }
}
