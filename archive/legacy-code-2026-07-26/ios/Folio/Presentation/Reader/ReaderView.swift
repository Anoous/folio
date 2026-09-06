import SwiftUI
import SwiftData

struct ReaderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthViewModel.self) private var authViewModel: AuthViewModel?
    @Environment(\.heroNamespace) private var heroNamespace

    let article: Article
    var onDismiss: (() -> Void)? = nil

    @State private var viewModel: ReaderViewModel?
    @State private var showsShareSheet = false
    @State private var showsReadingPreferences = false
    @State private var showsWebView = false
    @State private var showsDeleteConfirmation = false
    @Environment(\.openURL) private var openURL
    @State private var showToastState = false
    @State private var tappedImageURL: URL?

    // Ink entrance
    @State private var contentVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion



    // Swipe-to-dismiss
    @GestureState private var dragOffset: CGFloat = 0

    // Reading preferences
    @AppStorage(ReadingPreferenceKeys.fontSize) private var fontSize: Double = 17
    @AppStorage(ReadingPreferenceKeys.lineSpacing) private var lineSpacing: Double = 11.9
    @AppStorage(ReadingPreferenceKeys.theme) private var themeRawValue: String = ReadingTheme.system.rawValue
    @AppStorage(ReadingPreferenceKeys.fontFamily) private var fontFamilyRawValue: String = ReadingFontFamily.notoSerif.rawValue

    private var readingTheme: ReadingTheme {
        ReadingTheme(rawValue: themeRawValue) ?? .system
    }

    private var readingFontFamily: ReadingFontFamily {
        ReadingFontFamily(rawValue: fontFamilyRawValue) ?? .notoSerif
    }

    var body: some View {
        Group {
            if let viewModel {
                readerContent(viewModel: viewModel)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .offset(x: dragOffset)
        .scaleEffect(1 - abs(dragOffset) / 1000)
        .gesture(
            onDismiss == nil ? nil : DragGesture()
                .updating($dragOffset) { value, state, _ in
                    if value.translation.width > 0 {
                        state = value.translation.width
                    }
                }
                .onEnded { value in
                    let shouldDismiss = value.translation.width > 120 || value.predictedEndTranslation.width > 200
                    if shouldDismiss {
                        onDismiss?()
                    }
                }
        )
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(onDismiss != nil ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if let onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.folio.accent)
                }
            }
            ToolbarItem(placement: .principal) {
                Text(article.displayTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(readingTheme.textColor)
                    .lineLimit(1)
            }
            ToolbarItem(placement: .topBarTrailing) {
                readerMoreMenu(iconFont: nil, extraPadding: false)
            }
        }
        .overlay(alignment: .top) {
            if onDismiss != nil {
                ReaderFloatingChromeView(
                    title: article.displayTitle,
                    textColor: readingTheme.textColor,
                    onDismiss: { onDismiss?() },
                    moreMenu: {
                        readerMoreMenu(iconFont: .system(size: 20), extraPadding: true)
                    }
                )
            }
        }
        .toast(isPresented: $showToastState, message: viewModel?.toastMessage ?? "", icon: viewModel?.toastIcon)
        .onChange(of: viewModel?.showToast) { _, newValue in
            showToastState = newValue ?? false
        }
        .onChange(of: showToastState) { _, newValue in
            viewModel?.showToast = newValue
        }
        .onAppear {
            if viewModel == nil {
                let vm = ReaderViewModel(
                    article: article,
                    context: modelContext,
                    isAuthenticated: authViewModel?.isAuthenticated ?? false
                )
                vm.markAsRead()
                viewModel = vm
            }
        }
        .onDisappear {
            viewModel?.persistProgressIfNeeded()
        }
        .task {
            await viewModel?.fetchContentIfNeeded()
            await viewModel?.fetchHighlights()
        }
        .sheet(isPresented: $showsReadingPreferences) {
            ReadingPreferenceView()
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showsShareSheet) {
            if let url = viewModel?.shareURL() {
                ShareSheet(activityItems: [url])
            }
        }
        .sheet(isPresented: $showsWebView) {
            if let urlString = article.url, let url = URL(string: urlString) {
                WebViewContainer(url: url)
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { tappedImageURL != nil },
            set: { if !$0 { tappedImageURL = nil } }
        )) {
            if let url = tappedImageURL {
                ImageViewerOverlay(url: url, altText: "")
            }
        }
        .alert(
            String(localized: "reader.deleteConfirm", defaultValue: "Delete this article?"),
            isPresented: $showsDeleteConfirmation
        ) {
            Button(String(localized: "button.cancel", defaultValue: "Cancel"), role: .cancel) {}
            Button(String(localized: "reader.delete", defaultValue: "Delete"), role: .destructive) {
                viewModel?.deleteArticle()
                if let onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            }
        } message: {
            Text(String(localized: "reader.deleteMessage", defaultValue: "This article will be permanently removed."))
        }
    }

    // MARK: - Reader Content

    @ViewBuilder
    private func readerContent(viewModel: ReaderViewModel) -> some View {
        VStack(spacing: 0) {
            Group {
                if article.sourceType == .screenshot || article.sourceType == .voice {
                    ScrollView {
                        ReaderMediaContentView(article: article) { url in
                            tappedImageURL = url
                        }
                            .padding(.top, Spacing.md)
                            .padding(.bottom, 32)
                    }
                    .opacity(contentVisible ? 1 : 0)
                    .onAppear {
                        if !contentVisible {
                            withAnimation(Motion.ink) { contentVisible = true }
                        }
                    }
                } else if article.markdownContent != nil {
                    ReaderWebArticleContentView(
                        article: article,
                        viewModel: viewModel,
                        fontSize: fontSize,
                        lineSpacing: lineSpacing,
                        readingFontFamily: readingFontFamily,
                        readingTheme: readingTheme,
                        onImageTap: { src in
                            tappedImageURL = URL(string: src)
                        },
                        onLinkTap: { href in
                            if let url = URL(string: href) {
                                UIApplication.shared.open(url)
                            }
                        },
                        onContentReady: {
                            if !contentVisible {
                                withAnimation(Motion.ink) { contentVisible = true }
                            }
                        }
                    )
                    .opacity(contentVisible ? 1 : 0)
                } else if viewModel.isLoadingContent {
                    VStack(spacing: Spacing.md) {
                        ProgressView()
                        Text(String(localized: "reader.loadingContent", defaultValue: "Loading content..."))
                            .font(Typography.caption)
                            .foregroundStyle(Color.folio.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, Spacing.xl)
                } else {
                    ReaderContentUnavailableView(
                        article: article,
                        error: viewModel.contentLoadError,
                        onRetry: {
                            Task { await viewModel.fetchContentIfNeeded() }
                        },
                        onOpenOriginal: openOriginal
                    )
                }
            }

        }
        .background(readingTheme.backgroundColor)
        .overlay(alignment: .top) {
            ReadingProgressBar(progress: viewModel.readingProgress)
        }
        .safeAreaInset(edge: .bottom) {
            ReaderBottomToolbar(
                article: article,
                readingProgress: viewModel.readingProgress,
                readingTheme: readingTheme,
                onOpenOriginal: openOriginal,
                onToggleFavorite: { viewModel.toggleFavorite() },
                onShare: { showsShareSheet = true }
            )
        }
        .task {
            if reduceMotion {
                contentVisible = true
                return
            }
            if article.markdownContent == nil {
                try? await Task.sleep(for: .milliseconds(200))
                withAnimation(Motion.ink) { contentVisible = true }
            }
        }
    }



    @ViewBuilder
    private func readerMoreMenu(iconFont: Font?, extraPadding: Bool) -> some View {
        Menu {
            Button(
                article.isFavorite
                    ? String(localized: "reader.unfavorite", defaultValue: "Remove Favorite")
                    : String(localized: "reader.favorite", defaultValue: "Favorite")
            ) {
                viewModel?.toggleFavorite()
            }

            Button(String(localized: "reader.copyMarkdown", defaultValue: "Copy Markdown")) {
                viewModel?.copyMarkdown()
            }

            Button(String(localized: "reader.readingPrefs", defaultValue: "Reading Preferences")) {
                showsReadingPreferences = true
            }

            Button(
                article.isArchived
                    ? String(localized: "reader.unarchive", defaultValue: "Unarchive")
                    : String(localized: "reader.archive", defaultValue: "Archive")
            ) {
                viewModel?.archiveArticle()
            }

            if article.url != nil {
                Button(String(localized: "reader.openInBrowser", defaultValue: "Open Original")) {
                    openOriginal()
                }
            }

            Button(String(localized: "reader.delete", defaultValue: "Delete"), role: .destructive) {
                showsDeleteConfirmation = true
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(iconFont)
                .foregroundStyle(Color.folio.textPrimary)
                .contentShape(Rectangle())
                .frame(width: extraPadding ? nil : 28, height: extraPadding ? nil : 28)
        }
        .accessibilityLabel(String(localized: "button.more", defaultValue: "More options"))
    }

    // MARK: - Open Original

    private func openOriginal() {
        guard let urlString = article.url, let url = URL(string: urlString) else { return }
        if ReaderOriginalLinkPolicy.shouldOpenExternally(url) {
            openURL(url)
        } else {
            showsWebView = true
        }
    }

}

#Preview {
    NavigationStack {
        ReaderView(article: {
            let a = Article(url: "https://example.com", title: "SwiftUI Best Practices for Modern iOS Apps", sourceType: .web)
            a.summary = "This article covers the latest SwiftUI patterns and best practices for building high-quality iOS applications."
            a.markdownContent = """
            # Introduction

            SwiftUI has evolved significantly since its introduction. This guide covers **best practices** for building modern apps.

            ## Architecture

            Use MVVM with `@Observable` for clean separation of concerns.

            ```swift
            @Observable
            class ViewModel {
                var items: [Item] = []
            }
            ```

            > Always prefer composition over inheritance in SwiftUI.

            ## Key Takeaways

            - Use the environment for dependency injection
            - Prefer small, focused views
            - Test your view models independently
            """
            a.siteName = "Swift Blog"
            a.author = "Jane Developer"
            a.keyPoints = [
                "Use MVVM with @Observable",
                "Prefer composition over inheritance",
                "Test view models independently",
            ]
            return a
        }())
    }
}
