import SwiftUI
import WebKit

/// A SwiftUI wrapper around WKWebView for rendering article HTML content
/// with highlight support, scroll tracking, and JS bridge communication.
struct ArticleWebView: UIViewRepresentable {
    let htmlContent: String
    let initialProgress: Double
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

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "folio")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.preferences.javaScriptEnabled = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator

        // Disable default long-press context menu via CSS injection
        let disableMenuCSS = """
        var style = document.createElement('style');
        style.textContent = '-webkit-touch-callout: none;';
        document.head.appendChild(style);
        """
        let userScript = WKUserScript(
            source: disableMenuCSS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(userScript)

        context.coordinator.webView = webView
        webView.loadHTMLString(htmlContent, baseURL: nil)

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Reload only when the HTML content has actually changed.
        // The coordinator tracks the last loaded content to avoid spurious reloads.
        if context.coordinator.lastLoadedHTML != htmlContent {
            context.coordinator.lastLoadedHTML = htmlContent
            uiView.loadHTMLString(htmlContent, baseURL: nil)
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let parent: ArticleWebView
        weak var webView: WKWebView?
        var lastLoadedHTML: String?

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
