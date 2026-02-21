import SwiftUI
import WebKit

/// A WKWebView wrapper with a progress bar and basic navigation controls.
struct WebViewContainer: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var progress: Double = 0
    @State private var isLoading: Bool = true
    @State private var canGoBack: Bool = false
    @State private var canGoForward: Bool = false
    @State private var currentTitle: String = ""
    @State private var webView: WKWebView?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                WebViewRepresentable(
                    url: url,
                    progress: $progress,
                    isLoading: $isLoading,
                    canGoBack: $canGoBack,
                    canGoForward: $canGoForward,
                    currentTitle: $currentTitle,
                    webView: $webView
                )

                // Progress bar
                if isLoading {
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.folio.accent)
                            .frame(width: geometry.size.width * progress, height: 2)
                            .animation(.linear(duration: 0.2), value: progress)
                    }
                    .frame(height: 2)
                }
            }
            .navigationTitle(currentTitle.isEmpty ? url.host ?? "" : currentTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Text(String(localized: "reader.done", defaultValue: "Done"))
                            .foregroundStyle(Color.folio.accent)
                    }
                }

                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        webView?.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(canGoBack ? Color.folio.accent : Color.folio.textTertiary)
                    }
                    .disabled(!canGoBack)

                    Button {
                        webView?.goForward()
                    } label: {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(canGoForward ? Color.folio.accent : Color.folio.textTertiary)
                    }
                    .disabled(!canGoForward)

                    Spacer()

                    if isLoading {
                        Button {
                            webView?.stopLoading()
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(Color.folio.textSecondary)
                        }
                    } else {
                        Button {
                            webView?.reload()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(Color.folio.textSecondary)
                        }
                    }

                    Button {
                        guard let currentURL = webView?.url ?? URL(string: url.absoluteString) else { return }
                        UIApplication.shared.open(currentURL)
                    } label: {
                        Image(systemName: "safari")
                            .foregroundStyle(Color.folio.textSecondary)
                    }
                }
            }
        }
    }
}

// MARK: - WKWebView Representable

struct WebViewRepresentable: UIViewRepresentable {
    let url: URL

    @Binding var progress: Double
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var currentTitle: String
    @Binding var webView: WKWebView?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // Observe loading progress
        context.coordinator.progressObservation = webView.observe(\.estimatedProgress) { view, _ in
            DispatchQueue.main.async {
                self.progress = view.estimatedProgress
            }
        }

        context.coordinator.loadingObservation = webView.observe(\.isLoading) { view, _ in
            DispatchQueue.main.async {
                self.isLoading = view.isLoading
                self.canGoBack = view.canGoBack
                self.canGoForward = view.canGoForward
                self.currentTitle = view.title ?? ""
            }
        }

        DispatchQueue.main.async {
            self.webView = webView
        }

        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebViewRepresentable
        var progressObservation: NSKeyValueObservation?
        var loadingObservation: NSKeyValueObservation?

        init(_ parent: WebViewRepresentable) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.canGoBack = webView.canGoBack
            parent.canGoForward = webView.canGoForward
            parent.currentTitle = webView.title ?? ""
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
    }
}

#Preview {
    WebViewContainer(url: URL(string: "https://example.com")!)
}
