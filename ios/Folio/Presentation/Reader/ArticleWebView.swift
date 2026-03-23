import SwiftUI
import WebKit

// MARK: - Custom WKWebView with "高亮" in system edit menu

class HighlightableWebView: WKWebView {
    var coordinator: ArticleWebView.Coordinator?

    override func buildMenu(with builder: any UIMenuBuilder) {
        // Add "高亮" action to the system edit menu (alongside Copy/Look Up/etc.)
        let highlightAction = UIAction(title: "高亮", image: UIImage(systemName: "highlighter")) { [weak self] _ in
            self?.coordinator?.handleHighlightFromMenu()
        }
        let highlightMenu = UIMenu(title: "", options: .displayInline, children: [highlightAction])
        builder.insertChild(highlightMenu, atStartOfMenu: .standardEdit)

        super.buildMenu(with: builder)
    }
}

/// A SwiftUI wrapper around WKWebView for rendering article HTML content
/// with highlight support, scroll tracking, and JS bridge communication.
struct ArticleWebView: UIViewRepresentable {
    let htmlContent: String
    let initialProgress: Double

    // Reading preferences (live-updated via JS, no page reload)
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let fontFamily: String      // CSS font-family string
    let themeBg: String         // hex background color
    let themeText: String       // hex primary text color
    let themeSecondary: String  // hex secondary text color

    let onHighlightCreate: (String, Int, Int) -> Void  // text, startOffset, endOffset
    let onHighlightRemove: (String) -> Void             // highlightId
    let onScrollProgress: (Double) -> Void
    let onImageTap: (String) -> Void                    // image src URL
    let onLinkTap: (String) -> Void                     // href URL
    let onToast: (String) -> Void                       // toast message
    let onContentReady: () -> Void                      // content loaded callback

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> HighlightableWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "folio")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController

        let webView = HighlightableWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        webView.coordinator = context.coordinator

        context.coordinator.webView = webView
        webView.loadHTMLString(htmlContent, baseURL: nil)

        return webView
    }

    func updateUIView(_ uiView: HighlightableWebView, context: Context) {
        let coord = context.coordinator

        // Reload only when HTML content changes
        if coord.lastLoadedHTML != htmlContent {
            coord.lastLoadedHTML = htmlContent
            uiView.loadHTMLString(htmlContent, baseURL: nil)
        }

        // Live-update reading preferences via JS (no reload, preserves scroll)
        let lineHeightRatio = (fontSize + lineSpacing) / fontSize
        let prefsKey = "\(fontSize)-\(lineSpacing)-\(fontFamily)-\(themeBg)-\(themeText)-\(themeSecondary)"
        if coord.lastPrefsKey != prefsKey {
            coord.lastPrefsKey = prefsKey
            let js = "setPreferences(\(fontSize), \(String(format: "%.2f", lineHeightRatio)), '\(fontFamily)', '\(themeBg)', '\(themeText)', '\(themeSecondary)')"
            coord.callJS(js)
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let parent: ArticleWebView
        weak var webView: WKWebView?
        var lastLoadedHTML: String?
        var lastPrefsKey: String?

        init(parent: ArticleWebView) {
            self.parent = parent
            super.init()
        }

        // MARK: WKScriptMessageHandler

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            switch type {
            case "highlight.create":
                if let text = body["text"] as? String,
                   let start = body["startOffset"] as? Int,
                   let end = body["endOffset"] as? Int {
                    parent.onHighlightCreate(text, start, end)
                }
            case "highlight.remove":
                if let id = body["id"] as? String {
                    parent.onHighlightRemove(id)
                }
            case "scroll.progress":
                if let percent = body["percent"] as? Double {
                    parent.onScrollProgress(percent)
                }
            case "image.tap":
                if let src = body["src"] as? String {
                    parent.onImageTap(src)
                }
            case "link.tap":
                if let href = body["href"] as? String {
                    parent.onLinkTap(href)
                }
            case "toast":
                if let msg = body["message"] as? String {
                    parent.onToast(msg)
                }
            case "content.ready":
                DispatchQueue.main.async { [self] in
                    parent.onContentReady()
                    if parent.initialProgress > 0 {
                        scrollToProgress(parent.initialProgress)
                    }
                }
            default:
                break
            }
        }

        // MARK: WKNavigationDelegate

        /// Blocks all external navigation; only the initial HTML load is allowed.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .other
                || navigationAction.request.url?.scheme == "about" {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }

        // MARK: Public Helpers

        /// Called when user taps "高亮" in the system edit menu.
        /// Gets the current selection from JS and creates a highlight.
        func handleHighlightFromMenu() {
            let js = """
            (function() {
                var sel = window.getSelection();
                if (!sel || sel.isCollapsed || sel.toString().trim().length < 1) return null;
                var range = sel.getRangeAt(0);
                var text = sel.toString();
                var start = getTextOffset(range.startContainer, range.startOffset);
                var end = getTextOffset(range.endContainer, range.endOffset);
                if (text.length > 500) { text = text.substring(0, 500); end = start + 500; }
                // Create visual highlight
                try {
                    var mark = document.createElement('mark');
                    mark.className = 'hl';
                    mark.setAttribute('data-id', 'temp-' + Date.now());
                    range.surroundContents(mark);
                    if (typeof attachHighlightPopup === 'function') attachHighlightPopup(mark);
                    sel.removeAllRanges();
                } catch(ex) {}
                return JSON.stringify({text: text, startOffset: start, endOffset: end});
            })()
            """
            webView?.evaluateJavaScript(js) { [weak self] result, error in
                guard let jsonString = result as? String,
                      let data = jsonString.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let text = dict["text"] as? String,
                      let start = dict["startOffset"] as? Int,
                      let end = dict["endOffset"] as? Int else { return }
                DispatchQueue.main.async {
                    self?.parent.onHighlightCreate(text, start, end)
                    self?.parent.onToast("已高亮")
                }
            }
        }

        /// Evaluates arbitrary JavaScript in the web view.
        func callJS(_ script: String) {
            webView?.evaluateJavaScript(script, completionHandler: nil)
        }

        /// Scrolls the article to the given reading progress (0...1).
        /// Uses a small delay so the layout is settled before scrolling.
        func scrollToProgress(_ percent: Double) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.callJS("scrollToProgress(\(percent))")
            }
        }
    }
}
