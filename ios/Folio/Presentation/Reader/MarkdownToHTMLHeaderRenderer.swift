import Foundation

// MARK: - Inline Header HTML & CSS

extension MarkdownToHTML {

    static var headerCSS: String {
        """
        .reader-header {
            padding: 0;
        }
        .reader-title {
            font-size: 26px;
            font-weight: 700;
            line-height: 1.35;
            margin: 0 0 16px;
            font-family: var(--font-family);
        }
        .reader-meta {
            display: flex;
            justify-content: space-between;
            align-items: center;
            font-size: 13px;
            color: var(--text-2);
            margin-bottom: 20px;
        }
        .reader-meta-left { display: flex; gap: 4px; align-items: center; }
        .reader-meta-dot { opacity: 0.5; }
        .reader-insight {
            background: rgba(0,113,227,0.06);
            border-radius: 12px;
            padding: 14px 16px;
            margin-bottom: 24px;
        }
        .reader-insight-header {
            display: flex;
            align-items: flex-start;
            gap: 10px;
            cursor: pointer;
            -webkit-tap-highlight-color: transparent;
        }
        .reader-insight-icon { font-size: 14px; flex-shrink: 0; padding-top: 2px; }
        .reader-insight-text {
            font-size: 15px;
            font-weight: 500;
            line-height: 1.55;
            color: var(--text-1);
            flex: 1;
            display: -webkit-box;
            -webkit-line-clamp: 2;
            -webkit-box-orient: vertical;
            overflow: hidden;
        }
        .reader-insight-text.expanded {
            -webkit-line-clamp: unset;
            overflow: visible;
        }
        .reader-insight-chevron {
            font-size: 12px;
            color: var(--text-2);
            opacity: 0.5;
            transition: transform 0.25s ease;
            flex-shrink: 0;
            padding-top: 4px;
        }
        .reader-insight-chevron.expanded { transform: rotate(180deg); }
        .reader-insight-details {
            display: none;
            padding-top: 12px;
            margin-top: 12px;
            border-top: 0.5px solid var(--sep);
        }
        .reader-insight-details.show { display: block; }
        .reader-insight-point {
            display: flex;
            gap: 8px;
            padding: 4px 0;
            font-size: 14px;
            color: var(--text-2);
            line-height: 1.6;
        }
        .reader-insight-point-dot { color: var(--text-2); opacity: 0.4; flex-shrink: 0; }
        .reader-divider {
            border: none;
            border-top: 0.5px solid var(--sep);
            margin: 0 0 24px;
        }
        """
    }

    static func headerHTML(_ header: ArticleHeader, accentHex: String) -> String {
        var metaLeft = ""
        if let siteName = header.siteName, !siteName.isEmpty {
            metaLeft += "<span>\(escapeHeaderHTML(siteName))</span>"
        }
        if let author = header.author, !author.isEmpty {
            if !metaLeft.isEmpty { metaLeft += "<span class=\"reader-meta-dot\">&middot;</span>" }
            metaLeft += "<span>\(escapeHeaderHTML(author))</span>"
        }
        if !metaLeft.isEmpty { metaLeft += "<span class=\"reader-meta-dot\">&middot;</span>" }
        metaLeft += "<span>\(escapeHeaderHTML(header.readingTime))</span>"

        var insightHTML = ""
        if let summary = header.summary, !summary.isEmpty {
            let hasPoints = !header.keyPoints.isEmpty
            let chevron = hasPoints ? "<span class=\"reader-insight-chevron\" id=\"insight-chevron\">&#9662;</span>" : ""
            var pointsHTML = ""
            if hasPoints {
                pointsHTML = "<div class=\"reader-insight-details\" id=\"insight-details\">"
                for point in header.keyPoints {
                    pointsHTML += "<div class=\"reader-insight-point\"><span class=\"reader-insight-point-dot\">&middot;</span><span>\(escapeHeaderHTML(point))</span></div>"
                }
                pointsHTML += "</div>"
            }
            insightHTML = """
            <div class="reader-insight">
                <div class="reader-insight-header" id="insight-toggle">
                    <span class="reader-insight-icon">\u{2726}</span>
                    <span class="reader-insight-text" id="insight-text">\(escapeHeaderHTML(summary))</span>
                    \(chevron)
                </div>
                \(pointsHTML)
            </div>
            """
        }

        return """
        <div class="reader-header" id="reader-header">
            <h1 class="reader-title" id="reader-title">\(escapeHeaderHTML(header.title))</h1>
            <div class="reader-meta">
                <div class="reader-meta-left">\(metaLeft)</div>
                <span>\(escapeHeaderHTML(header.dateLabel))</span>
            </div>
            \(insightHTML)
            <hr class="reader-divider">
        </div>
        """
    }

    private static func escapeHeaderHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
