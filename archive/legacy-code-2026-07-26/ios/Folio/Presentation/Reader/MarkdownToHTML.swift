import Foundation
import Markdown

// MARK: - Markdown → HTML Converter

/// Converts Markdown content + reading preferences + highlights into a complete
/// HTML document string suitable for rendering in WKWebView.
struct MarkdownToHTML {

    // MARK: - Article Header Metadata

    struct ArticleHeader {
        let title: String
        let siteName: String?
        let author: String?
        let readingTime: String
        let dateLabel: String
        let summary: String?
        let keyPoints: [String]
    }

    struct ReaderStrings {
        let highlight: String
        let copy: String
        let removeHighlight: String
        let highlighted: String
        let copied: String
        let removedHighlight: String

        static let reader = ReaderStrings(
            highlight: String(localized: "highlight.action", defaultValue: "Highlight"),
            copy: String(localized: "button.copy", defaultValue: "Copy"),
            removeHighlight: String(localized: "highlight.remove", defaultValue: "Remove Highlight"),
            highlighted: String(localized: "highlight.created", defaultValue: "Highlighted"),
            copied: String(localized: "highlight.copied", defaultValue: "Copied"),
            removedHighlight: String(localized: "highlight.removed", defaultValue: "Highlight Removed")
        )
    }


    // MARK: - Public API (with inline header)

    static func convertWithHeader(
        markdown: String,
        header: ArticleHeader,
        highlights: [(id: String, startOffset: Int, endOffset: Int)],
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        fontFamily: ReadingFontFamily,
        theme: ReadingTheme,
        strings: ReaderStrings = .reader
    ) -> String {
        let preprocessed = MarkdownRenderer.preprocessed(markdown, title: header.title)
        let document = Document(parsing: preprocessed)
        var visitor = MarkdownHTMLVisitor()
        let bodyHTML = visitor.visitDocument(document)

        let highlightsJSON = highlights.map { h in
            "{id:\"\(escapeJS(h.id))\",startOffset:\(h.startOffset),endOffset:\(h.endOffset)}"
        }.joined(separator: ",")

        let colors = themeColors(theme)
        let cssFontFamily = cssFontFamilyValue(fontFamily)
        let lineHeightRatio = (fontSize + lineSpacing) / fontSize
        let stringsJSON = jsObject(strings)

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
        <style>
        \(cssTemplate(
            fontSize: fontSize,
            lineHeight: lineHeightRatio,
            fontFamily: cssFontFamily,
            bg: colors.bg,
            text1: colors.text1,
            text2: colors.text2
        ))
        \(headerCSS)
        </style>
        </head>
        <body>
        <div class="reader-shell">
        \(headerHTML(header, accentHex: "#0071E3"))
        <div class="article-body">\(bodyHTML)</div>
        </div>
        <script>
        window.existingHighlights = [\(highlightsJSON)];
        window.folioStrings = \(stringsJSON);
        \(articleJS)
        </script>
        </body>
        </html>
        """
    }

    // MARK: - Theme Colors

    private struct ThemeColors {
        let bg: String
        let text1: String
        let text2: String
    }

    private static func themeColors(_ theme: ReadingTheme) -> ThemeColors {
        ThemeColors(bg: theme.bgHex, text1: theme.textHex, text2: theme.secondaryTextHex)
    }

    // MARK: - Font Family

    private static func cssFontFamilyValue(_ family: ReadingFontFamily) -> String {
        family.cssName
    }

    // MARK: - CSS Template

    private static func cssTemplate(
        fontSize: CGFloat,
        lineHeight: CGFloat,
        fontFamily: String,
        bg: String,
        text1: String,
        text2: String
    ) -> String {
        """
        :root {
            --font-size: \(Int(fontSize))px;
            --line-height: \(String(format: "%.2f", lineHeight));
            --font-family: \(fontFamily);
            --bg: \(bg);
            --text-1: \(text1);
            --text-2: \(text2);
            --accent: #0071E3;
            --sep: rgba(0,0,0,0.05);
            --highlight: rgba(0,113,227,0.12);
            --code-bg: rgba(0,0,0,0.03);
            --blockquote-border: var(--text-2);
        }
        body {
            font-family: var(--font-family);
            font-size: var(--font-size);
            line-height: var(--line-height);
            color: var(--text-1);
            background: var(--bg);
            margin: 0;
            padding: 0 20px 28px;
            padding-top: calc(env(safe-area-inset-top, 0px) + 44px);
            -webkit-text-size-adjust: 100%;
            -webkit-tap-highlight-color: transparent;
        }
        .reader-shell { max-width: 720px; margin: 0 auto; }
        h2 { font-size: 20px; font-weight: bold; margin: 32px 0 14px; line-height: 1.4; }
        h3 { font-size: 18px; font-weight: bold; margin: 24px 0 10px; line-height: 1.4; }
        p { margin-bottom: 20px; }
        blockquote {
            padding: 12px 0 12px 16px;
            border-left: 2px solid var(--blockquote-border);
            margin: 20px 0;
            font-style: italic;
            opacity: 0.8;
        }
        pre {
            background: var(--code-bg);
            padding: 16px;
            border-radius: 8px;
            overflow-x: auto;
            margin: 20px 0;
        }
        code {
            font-family: ui-monospace, "SF Mono", monospace;
            font-size: 14px;
            background: var(--code-bg);
            padding: 2px 6px;
            border-radius: 4px;
        }
        pre code { background: none; padding: 0; }
        img { max-width: 100%; height: auto; border-radius: 8px; margin: 16px 0; display: block; }
        a { color: var(--accent); text-decoration: none; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; overflow-x: auto; display: block; }
        th, td { padding: 8px 12px; border: 0.5px solid var(--sep); text-align: left; font-size: 14px; }
        th { font-weight: 600; }
        hr { border: none; border-top: 0.5px solid var(--sep); margin: 24px 0; }
        ul, ol { padding-left: 24px; margin-bottom: 20px; }
        li { margin-bottom: 8px; }
        .hl {
            background: var(--highlight);
            border-radius: 2px;
            padding: 1px 0;
            cursor: pointer;
            position: relative;
        }
        .hl-popup {
            position: absolute;
            bottom: calc(100% + 8px);
            left: 50%;
            transform: translateX(-50%);
            display: none;
            background: var(--text-1);
            color: var(--bg);
            border-radius: 8px;
            padding: 6px 4px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.15);
            z-index: 50;
            white-space: nowrap;
            animation: popIn 0.15s ease;
        }
        .hl-popup.on { display: flex; }
        .hl-popup::after {
            content: '';
            position: absolute;
            top: 100%;
            left: 50%;
            transform: translateX(-50%);
            border: 5px solid transparent;
            border-top-color: var(--text-1);
        }
        .hl-popup-btn {
            padding: 6px 12px;
            font-size: 13px;
            font-weight: 500;
            border: none;
            background: none;
            color: inherit;
            border-radius: 4px;
            -webkit-tap-highlight-color: transparent;
        }
        .hl-popup-btn:active { opacity: 0.5; }
        .hl-popup-btn + .hl-popup-btn { border-left: 0.5px solid rgba(255,255,255,0.15); }
        @keyframes popIn {
            from { opacity: 0; transform: translateX(-50%) scale(0.9); }
            to { opacity: 1; transform: translateX(-50%) scale(1); }
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --code-bg: rgba(255,255,255,0.08);
                --blockquote-border: rgba(255,255,255,0.18);
            }
        }
        """
    }

    // MARK: - Escape Helpers

    private static func jsObject(_ strings: ReaderStrings) -> String {
        """
        {
            highlight:"\(escapeJS(strings.highlight))",
            copy:"\(escapeJS(strings.copy))",
            removeHighlight:"\(escapeJS(strings.removeHighlight))",
            highlighted:"\(escapeJS(strings.highlighted))",
            copied:"\(escapeJS(strings.copied))",
            removedHighlight:"\(escapeJS(strings.removedHighlight))"
        }
        """
    }

    /// Escapes a string for safe inclusion inside a JavaScript string literal.
    private static func escapeJS(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
