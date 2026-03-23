import Foundation
import Markdown

// MARK: - Markdown → HTML Converter

/// Converts Markdown content + reading preferences + highlights into a complete
/// HTML document string suitable for rendering in WKWebView.
struct MarkdownToHTML {

    // MARK: - Public API

    static func convert(
        markdown: String,
        title: String?,
        highlights: [(id: String, startOffset: Int, endOffset: Int)],
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        fontFamily: ReadingFontFamily,
        theme: ReadingTheme
    ) -> String {
        let preprocessed = MarkdownRenderer.preprocessed(markdown, title: title)
        let document = Document(parsing: preprocessed)
        var visitor = MarkdownHTMLVisitor()
        let bodyHTML = visitor.visitDocument(document)

        let highlightsJSON = highlights.map { h in
            "{id:\"\(escapeJS(h.id))\",startOffset:\(h.startOffset),endOffset:\(h.endOffset)}"
        }.joined(separator: ",")

        let colors = themeColors(theme)
        let cssFontFamily = cssFontFamilyValue(fontFamily)
        // lineSpacing is in points; convert to a unitless ratio relative to fontSize
        let lineHeightRatio = (fontSize + lineSpacing) / fontSize

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
        \(cssTemplate(
            fontSize: fontSize,
            lineHeight: lineHeightRatio,
            fontFamily: cssFontFamily,
            bg: colors.bg,
            text1: colors.text1,
            text2: colors.text2
        ))
        </style>
        </head>
        <body>
        <div class="article-body">\(bodyHTML)</div>
        <script>
        window.existingHighlights = [\(highlightsJSON)];
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
        }
        body {
            font-family: var(--font-family);
            font-size: var(--font-size);
            line-height: var(--line-height);
            color: var(--text-1);
            background: var(--bg);
            margin: 0;
            padding: 0 20px 80px;
            -webkit-text-size-adjust: 100%;
            -webkit-tap-highlight-color: transparent;
        }
        h2 { font-size: 20px; font-weight: bold; margin: 32px 0 14px; line-height: 1.4; }
        h3 { font-size: 18px; font-weight: bold; margin: 24px 0 10px; line-height: 1.4; }
        p { margin-bottom: 20px; }
        blockquote {
            padding: 12px 0 12px 16px;
            border-left: 2px solid var(--text-2);
            margin: 20px 0;
            font-style: italic;
            opacity: 0.8;
        }
        pre {
            background: rgba(0,0,0,0.03);
            padding: 16px;
            border-radius: 8px;
            overflow-x: auto;
            margin: 20px 0;
        }
        code {
            font-family: ui-monospace, "SF Mono", monospace;
            font-size: 14px;
            background: rgba(0,0,0,0.03);
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
        """
    }

    // MARK: - Escape Helpers

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

// MARK: - article.js (inline)

extension MarkdownToHTML {

    /// The JavaScript that powers text-selection highlights, scroll progress
    /// tracking, link interception, and image taps inside the WKWebView reader.
    // swiftlint:disable:next function_body_length
    static let articleJS: String = """
    (function() {
        "use strict";

        var activePopup = null;

        // ── Swift bridge ─────────────────────────────────────
        function msg(type, data) {
            var payload = Object.assign({type: type}, data || {});
            window.webkit.messageHandlers.folio.postMessage(payload);
        }

        // ── Popup management ─────────────────────────────────
        function closeAllPopups() {
            document.querySelectorAll('.hl-popup').forEach(function(p) { p.remove(); });
            if (activePopup) { activePopup.remove(); activePopup = null; }
        }

        // ── Text offset calculation ──────────────────────────
        function getTextOffset(node, offset) {
            var body = document.querySelector('.article-body');
            if (!body) return 0;
            var walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT);
            var pos = 0;
            while (walker.nextNode()) {
                if (walker.currentNode === node) return pos + offset;
                pos += walker.currentNode.length;
            }
            return pos;
        }

        // ── Clipboard helper (execCommand fallback) ──────────
        function copyText(text) {
            if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(text).catch(function() {
                    fallbackCopy(text);
                });
            } else {
                fallbackCopy(text);
            }
        }

        function fallbackCopy(text) {
            var ta = document.createElement('textarea');
            ta.value = text;
            ta.style.position = 'fixed';
            ta.style.left = '-9999px';
            document.body.appendChild(ta);
            ta.select();
            document.execCommand('copy');
            document.body.removeChild(ta);
        }

        // ── Create-highlight floating menu ───────────────────
        function showCreateMenu(range) {
            closeAllPopups();
            var rect = range.getBoundingClientRect();
            var menu = document.createElement('div');
            menu.className = 'hl-popup on';
            menu.style.position = 'fixed';
            menu.style.left = (rect.left + rect.width / 2) + 'px';
            menu.style.top = (rect.top - 8) + 'px';
            menu.style.transform = 'translateX(-50%) translateY(-100%)';

            var hlBtn = document.createElement('button');
            hlBtn.className = 'hl-popup-btn';
            hlBtn.textContent = '\\u9AD8\\u4EAE';
            menu.appendChild(hlBtn);

            var cpBtn = document.createElement('button');
            cpBtn.className = 'hl-popup-btn';
            cpBtn.textContent = '\\u590D\\u5236';
            menu.appendChild(cpBtn);

            document.body.appendChild(menu);
            activePopup = menu;

            hlBtn.onclick = function(e) {
                e.stopPropagation();
                var sel = window.getSelection();
                if (sel.rangeCount) {
                    var r = sel.getRangeAt(0);
                    var text = sel.toString();
                    var start = getTextOffset(r.startContainer, r.startOffset);
                    var end = getTextOffset(r.endContainer, r.endOffset);
                    if (text.length > 500) { text = text.substring(0, 500); end = start + 500; }
                    try {
                        var mark = document.createElement('mark');
                        mark.className = 'hl';
                        mark.setAttribute('data-id', 'temp-' + Date.now());
                        r.surroundContents(mark);
                        attachHighlightPopup(mark);
                        sel.removeAllRanges();
                    } catch(ex) {}
                    msg('highlight.create', {text: text, startOffset: start, endOffset: end});
                    msg('toast', {message: '\\u5DF2\\u9AD8\\u4EAE'});
                }
                closeAllPopups();
            };

            cpBtn.onclick = function(e) {
                e.stopPropagation();
                var text = window.getSelection().toString();
                copyText(text);
                msg('toast', {message: '\\u5DF2\\u590D\\u5236'});
                closeAllPopups();
            };
        }

        // ── Attach remove-popup on existing highlight taps ───
        function attachHighlightPopup(mark) {
            mark.onclick = function(e) {
                e.stopPropagation();
                closeAllPopups();
                var popup = document.createElement('div');
                popup.className = 'hl-popup on';

                var rmBtn = document.createElement('button');
                rmBtn.className = 'hl-popup-btn';
                rmBtn.textContent = '\\u79FB\\u9664\\u9AD8\\u4EAE';
                popup.appendChild(rmBtn);

                var cpBtn = document.createElement('button');
                cpBtn.className = 'hl-popup-btn';
                cpBtn.textContent = '\\u590D\\u5236';
                popup.appendChild(cpBtn);

                mark.appendChild(popup);
                activePopup = popup;

                rmBtn.onclick = function(ev) {
                    ev.stopPropagation();
                    var id = mark.getAttribute('data-id');
                    var inner = mark.innerHTML.replace(/<div[^>]*class="hl-popup[^"]*"[^>]*>[\\s\\S]*?<\\/div>/g, '');
                    mark.outerHTML = inner;
                    msg('highlight.remove', {id: id});
                    msg('toast', {message: '\\u5DF2\\u79FB\\u9664\\u9AD8\\u4EAE'});
                };

                cpBtn.onclick = function(ev) {
                    ev.stopPropagation();
                    var text = mark.textContent.trim();
                    copyText(text);
                    msg('toast', {message: '\\u5DF2\\u590D\\u5236'});
                    closeAllPopups();
                };
            };
        }

        // ── Render existing highlights on load ───────────────
        function highlightRange(id, start, end) {
            var body = document.querySelector('.article-body');
            if (!body) return;
            var walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT);
            var pos = 0, startNode = null, startOff = 0, endNode = null, endOff = 0;
            while (walker.nextNode()) {
                var nodeLen = walker.currentNode.length;
                if (!startNode && pos + nodeLen > start) {
                    startNode = walker.currentNode;
                    startOff = start - pos;
                }
                if (pos + nodeLen >= end) {
                    endNode = walker.currentNode;
                    endOff = end - pos;
                    break;
                }
                pos += nodeLen;
            }
            if (startNode && endNode) {
                try {
                    var range = document.createRange();
                    range.setStart(startNode, startOff);
                    range.setEnd(endNode, endOff);
                    var mark = document.createElement('mark');
                    mark.className = 'hl';
                    mark.setAttribute('data-id', id);
                    range.surroundContents(mark);
                    attachHighlightPopup(mark);
                } catch(ex) {}
            }
        }

        function renderExistingHighlights() {
            if (!window.existingHighlights || !window.existingHighlights.length) return;
            var sorted = window.existingHighlights.slice().sort(function(a, b) {
                return b.startOffset - a.startOffset;
            });
            sorted.forEach(function(h) {
                highlightRange(h.id, h.startOffset, h.endOffset);
            });
        }

        // ── Text selection → highlight menu ──────────────────
        document.addEventListener('touchend', function(e) {
            if (!e.target.closest('.article-body')) return;
            setTimeout(function() {
                var sel = window.getSelection();
                if (!sel || sel.isCollapsed || sel.toString().trim().length < 3) return;
                var range = sel.getRangeAt(0);
                var ancestor = range.commonAncestorContainer;
                if (ancestor.closest && ancestor.closest('.hl')) return;
                if (ancestor.parentElement && ancestor.parentElement.closest('.hl')) return;
                showCreateMenu(range);
            }, 200);
        });

        // ── Dismiss popups on background tap ─────────────────
        document.addEventListener('click', function(e) {
            if (!e.target.closest('.hl') && !e.target.closest('.hl-popup')) {
                closeAllPopups();
            }
        });

        // ── Scroll progress ──────────────────────────────────
        var scrollThrottle = null;
        window.addEventListener('scroll', function() {
            if (scrollThrottle) return;
            scrollThrottle = setTimeout(function() {
                scrollThrottle = null;
                var pct = window.scrollY / Math.max(1, document.body.scrollHeight - window.innerHeight);
                msg('scroll.progress', {percent: Math.min(1, Math.max(0, pct))});
            }, 100);
        });

        // ── Image tap ────────────────────────────────────────
        document.addEventListener('click', function(e) {
            if (e.target.tagName === 'IMG') {
                msg('image.tap', {src: e.target.src, alt: e.target.alt || ''});
            }
        });

        // ── Link interception ────────────────────────────────
        document.addEventListener('click', function(e) {
            var a = e.target.closest('a');
            if (a && a.href) {
                e.preventDefault();
                msg('link.tap', {href: a.href});
            }
        });

        // ── Called from Swift ─────────────────────────────────
        window.scrollToProgress = function(pct) {
            window.scrollTo(0, (document.body.scrollHeight - window.innerHeight) * pct);
        };

        window.setPreferences = function(fontSize, lineHeight, fontFamily, bgColor, textColor, secondaryColor) {
            var r = document.documentElement.style;
            r.setProperty('--font-size', fontSize + 'px');
            r.setProperty('--line-height', lineHeight);
            r.setProperty('--font-family', fontFamily);
            r.setProperty('--bg', bgColor);
            r.setProperty('--text-1', textColor);
            r.setProperty('--text-2', secondaryColor);
        };

        // ── Init ─────────────────────────────────────────────
        document.addEventListener('DOMContentLoaded', function() {
            renderExistingHighlights();
            msg('content.ready', {height: document.body.scrollHeight});
        });
    })();
    """
}

// MARK: - HTML Visitor

/// A `MarkupVisitor` that emits an HTML string from the swift-markdown AST.
private struct MarkdownHTMLVisitor: MarkupVisitor {
    typealias Result = String

    // MARK: - Document

    mutating func defaultVisit(_ markup: any Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    mutating func visitDocument(_ document: Document) -> String {
        document.children.map { visit($0) }.joined()
    }

    // MARK: - Block Elements

    mutating func visitHeading(_ heading: Heading) -> String {
        let level = min(heading.level, 6)
        let inner = heading.children.map { visit($0) }.joined()
        return "<h\(level)>\(inner)</h\(level)>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        let inner = paragraph.children.map { visit($0) }.joined()
        return "<p>\(inner)</p>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        let inner = blockQuote.children.map { visit($0) }.joined()
        return "<blockquote>\(inner)</blockquote>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let code = escapeHTML(codeBlock.code.trimmingCharacters(in: .newlines))
        if let lang = codeBlock.language, !lang.isEmpty {
            return "<pre><code class=\"language-\(escapeHTML(lang))\">\(code)</code></pre>\n"
        }
        return "<pre><code>\(code)</code></pre>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
        let inner = orderedList.children.map { visit($0) }.joined()
        return "<ol>\(inner)</ol>\n"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        let inner = unorderedList.children.map { visit($0) }.joined()
        return "<ul>\(inner)</ul>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        let inner = listItem.children.map { visit($0) }.joined()
        return "<li>\(inner)</li>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        "<hr>\n"
    }

    mutating func visitTable(_ table: Markdown.Table) -> String {
        var html = "<table>"
        for child in table.children {
            if let head = child as? Markdown.Table.Head {
                html += "<thead><tr>"
                for cell in head.children {
                    if let tableCell = cell as? Markdown.Table.Cell {
                        let inner = tableCell.children.map { visit($0) }.joined()
                        html += "<th>\(inner)</th>"
                    }
                }
                html += "</tr></thead>"
            } else if let body = child as? Markdown.Table.Body {
                html += "<tbody>"
                for row in body.children {
                    if let tableRow = row as? Markdown.Table.Row {
                        html += "<tr>"
                        for cell in tableRow.children {
                            if let tableCell = cell as? Markdown.Table.Cell {
                                let inner = tableCell.children.map { visit($0) }.joined()
                                html += "<td>\(inner)</td>"
                            }
                        }
                        html += "</tr>"
                    }
                }
                html += "</tbody>"
            }
        }
        html += "</table>\n"
        return html
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        html.rawHTML
    }

    // MARK: - Inline Elements

    mutating func visitText(_ text: Markdown.Text) -> String {
        escapeHTML(text.string)
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        let inner = strong.children.map { visit($0) }.joined()
        return "<strong>\(inner)</strong>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        let inner = emphasis.children.map { visit($0) }.joined()
        return "<em>\(inner)</em>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        let inner = strikethrough.children.map { visit($0) }.joined()
        return "<del>\(inner)</del>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(escapeHTML(inlineCode.code))</code>"
    }

    mutating func visitLink(_ link: Markdown.Link) -> String {
        let href = link.destination ?? ""
        let inner = link.children.map { visit($0) }.joined()
        return "<a href=\"\(escapeHTML(href))\">\(inner)</a>"
    }

    mutating func visitImage(_ image: Markdown.Image) -> String {
        let src = image.source ?? ""
        let alt = image.plainText
        return "<img src=\"\(escapeHTML(src))\" alt=\"\(escapeHTML(alt))\">"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
        "\n"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
        "<br>\n"
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String {
        inlineHTML.rawHTML
    }

    // MARK: - Helpers

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
