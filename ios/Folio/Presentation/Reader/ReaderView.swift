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
    @State private var showMoreMenu = false
    @Environment(\.openURL) private var openURL
    @State private var isInsightExpanded = false
    @State private var metrics = ScaledArticleMetrics()
    @State private var showToastState = false
    @State private var tappedImageURL: URL?

    // Ink entrance
    @State private var titleVisible = false
    @State private var metaVisible = false
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
                    if value.translation.width > 80 {
                        onDismiss?()
                    }
                }
        )
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if let onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("页集")
                            .font(.system(size: 16))
                    }
                    .foregroundStyle(Color.folio.accent)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showMoreMenu = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Color.folio.textPrimary)
                }
                .accessibilityLabel(String(localized: "button.more", defaultValue: "More options"))
            }
        }
        .overlay(alignment: .topLeading) {
            // Inline back button for when ReaderView is outside NavigationStack (hero transition)
            if onDismiss != nil {
                Button {
                    onDismiss?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("页集")
                            .font(.system(size: 16))
                    }
                    .foregroundStyle(Color.folio.accent)
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.top, 12)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            // Inline more menu button for hero transition mode
            if onDismiss != nil {
                Button {
                    showMoreMenu = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.folio.textPrimary)
                        .padding(.horizontal, Spacing.screenPadding)
                        .padding(.top, 12)
                }
            }
        }
        .sheet(isPresented: $showMoreMenu) {
            readerMenuSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
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
            // Native SwiftUI header (non-scrolling)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Article title
                    Text(article.displayTitle)
                        .font(.custom("NotoSerifSC-Bold", size: metrics.titleSize))
                        .foregroundStyle(readingTheme.textColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .modifier(HeroGeometryModifier(id: "title-\(article.id)", namespace: heroNamespace))
                        .padding(.top, 40)
                        .opacity(titleVisible ? 1 : 0)

                    // Inline meta info
                    ArticleMetaInfoView(
                        article: article,
                        readingTimeMinutes: viewModel.estimatedReadTimeMinutes,
                        textColor: readingTheme.secondaryTextColor
                    )
                    .padding(.top, Spacing.lg)
                    .opacity(metaVisible ? 1 : 0)

                    // Insight panel
                    if let summary = article.displaySummary, !summary.isEmpty {
                        insightPanel
                            .padding(.top, Spacing.lg)
                            .opacity(metaVisible ? 1 : 0)
                    } else if !article.keyPoints.isEmpty {
                        insightPanel
                            .padding(.top, Spacing.lg)
                            .opacity(metaVisible ? 1 : 0)
                    }

                    // Divider before body
                    Divider()
                        .padding(.top, Spacing.md)
                }
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .fixedSize(horizontal: false, vertical: true)

            // Article body
            Group {
                if article.sourceType == .screenshot || article.sourceType == .voice {
                    // Native rendering for screenshot/voice articles
                    ScrollView {
                        screenshotContentView
                            .padding(.top, Spacing.md)
                            .padding(.bottom, 80)
                    }
                    .opacity(contentVisible ? 1 : 0)
                    .onAppear {
                        if !contentVisible {
                            withAnimation(Motion.ink) { contentVisible = true }
                        }
                    }
                } else if let markdown = article.markdownContent {
                    let highlightTuples = viewModel.highlights.map {
                        (id: $0.id, startOffset: $0.startOffset, endOffset: $0.endOffset)
                    }
                    ArticleWebView(
                        htmlContent: MarkdownToHTML.convert(
                            markdown: markdown,
                            title: article.title,
                            highlights: highlightTuples,
                            fontSize: CGFloat(fontSize),
                            lineSpacing: CGFloat(lineSpacing),
                            fontFamily: readingFontFamily,
                            theme: readingTheme
                        ),
                        initialProgress: article.readProgress,
                        fontSize: CGFloat(fontSize),
                        lineSpacing: CGFloat(lineSpacing),
                        fontFamily: readingFontFamily.cssName,
                        themeBg: readingTheme.bgHex,
                        themeText: readingTheme.textHex,
                        themeSecondary: readingTheme.secondaryTextHex,
                        onHighlightCreate: { text, start, end in
                            viewModel.createHighlight(text: text, startOffset: start, endOffset: end)
                        },
                        onHighlightRemove: { id in
                            viewModel.deleteHighlight(id: id)
                        },
                        onScrollProgress: { progress in
                            viewModel.updateReadingProgress(progress)
                        },
                        onImageTap: { src in
                            tappedImageURL = URL(string: src)
                        },
                        onLinkTap: { href in
                            if let url = URL(string: href) {
                                UIApplication.shared.open(url)
                            }
                        },
                        onToast: { message in
                            viewModel.showToastMessage(message, icon: nil)
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
                    contentUnavailableView
                }
            }
        }
        .background(readingTheme.backgroundColor)
        .overlay(alignment: .top) {
            ReadingProgressBar(progress: viewModel.readingProgress)
        }
        .safeAreaInset(edge: .bottom) {
            bottomToolbar
        }
        .task {
            guard !titleVisible else { return }
            if reduceMotion {
                titleVisible = true
                metaVisible = true
                contentVisible = true
                return
            }
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(Motion.ink) { titleVisible = true }
            try? await Task.sleep(for: .milliseconds(100))
            withAnimation(Motion.ink) { metaVisible = true }
            // contentVisible is triggered by onContentReady when WebView is used;
            // for non-WebView states (loading/error), show immediately.
            if article.markdownContent == nil {
                try? await Task.sleep(for: .milliseconds(100))
                withAnimation(Motion.ink) { contentVisible = true }
            }
        }
    }

    // MARK: - Screenshot / Voice Content

    @State private var screenshotImage: UIImage?

    @ViewBuilder
    private var screenshotContentView: some View {
        let hasOCRText = article.markdownContent != nil
            && !article.markdownContent!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        VStack(alignment: .leading, spacing: Spacing.md) {
            // Screenshot image (large display for .screenshot)
            if article.sourceType == .screenshot, let localPath = article.localImagePath {
                if let image = screenshotImage {
                    let imageURL = screenshotImageURL(localPath)
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: hasOCRText ? 300 : 400)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .onTapGesture { tappedImageURL = imageURL }
                        .accessibilityLabel(hasOCRText
                            ? String(article.markdownContent!.prefix(200))
                            : String(localized: "reader.screenshot", defaultValue: "Screenshot"))
                        .padding(.horizontal, Spacing.screenPadding)
                } else {
                    // Placeholder while loading
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.folio.separator.opacity(0.3))
                        .frame(height: 200)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 32))
                                .foregroundStyle(Color.folio.textQuaternary)
                        }
                        .padding(.horizontal, Spacing.screenPadding)
                }
            }

            // Text content (OCR text or voice transcription)
            if hasOCRText {
                Text(article.markdownContent!)
                    .font(Typography.body)
                    .foregroundStyle(Color.folio.textPrimary)
                    .lineSpacing(17 * 0.65)
                    .padding(.horizontal, Spacing.screenPadding)
                    .textSelection(.enabled)
            } else if article.sourceType == .screenshot {
                // No OCR text empty state
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.folio.textQuaternary)
                    Text(String(localized: "reader.noOCRText", defaultValue: "No text detected"))
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.textTertiary)
                    Text(String(localized: "reader.tapToViewImage", defaultValue: "Tap image to view full size"))
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.textQuaternary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.lg)
                .accessibilityLabel(String(localized: "reader.noOCRText", defaultValue: "No text detected"))
            }
        }
        .task {
            guard article.sourceType == .screenshot,
                  let localPath = article.localImagePath else { return }
            screenshotImage = await loadLocalImage(relativePath: localPath)
        }
    }

    private func screenshotImageURL(_ localPath: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier)?
            .appendingPathComponent(localPath)
    }

    private func loadLocalImage(relativePath: String) async -> UIImage? {
        await Task.detached {
            guard let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier
            ) else { return nil }
            let fileURL = containerURL.appendingPathComponent(relativePath)
            return UIImage(contentsOfFile: fileURL.path)
        }.value
    }

    // MARK: - Insight Panel

    private var insightPanel: some View {
        ReaderInsightPanel(article: article, isExpanded: $isInsightExpanded)
    }

    // MARK: - Content Unavailable

    private var contentUnavailableView: some View {
        VStack(spacing: Spacing.md) {
            if let error = viewModel?.contentLoadError {
                // Error state with retry
                Image(systemName: "exclamationmark.icloud")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.folio.error)

                Text(String(localized: "reader.loadFailed", defaultValue: "Failed to load content"))
                    .font(Typography.body)
                    .foregroundStyle(Color.folio.textPrimary)

                Text(error)
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textTertiary)
                    .multilineTextAlignment(.center)

                FolioButton(
                    title: String(localized: "reader.retryLoad", defaultValue: "Retry"),
                    style: .primary
                ) {
                    Task { await viewModel?.fetchContentIfNeeded() }
                }
                .frame(width: 200)
            } else if article.status == .processing {
                // Still processing
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.folio.warning)

                Text(String(localized: "reader.stillProcessing", defaultValue: "AI is still analyzing this article"))
                    .font(Typography.body)
                    .foregroundStyle(Color.folio.textSecondary)

                Text(String(localized: "reader.checkBackSoon", defaultValue: "Check back in a moment"))
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textTertiary)
            } else if article.status == .failed {
                // Failed
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.folio.error)

                Text(String(localized: "reader.processingFailed", defaultValue: "Processing failed"))
                    .font(Typography.body)
                    .foregroundStyle(Color.folio.textPrimary)

                if let fetchError = article.fetchError {
                    Text(fetchError)
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.textTertiary)
                        .multilineTextAlignment(.center)
                }
            } else {
                // Generic unavailable
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.folio.textTertiary)

                Text(String(localized: "reader.noContent", defaultValue: "Content not yet available"))
                    .font(Typography.body)
                    .foregroundStyle(Color.folio.textSecondary)
            }

            if article.url != nil {
                FolioButton(
                    title: String(localized: "reader.openOriginal", defaultValue: "Open Original"),
                    style: .secondary
                ) {
                    openOriginal()
                }
                .frame(width: 200)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }

    // MARK: - Menu Sheet

    private var readerMenuSheet: some View {
        ReaderMenuView(
            article: article,
            onDismiss: { showMoreMenu = false },
            onToggleFavorite: { viewModel?.toggleFavorite() },
            onCopyMarkdown: { viewModel?.copyMarkdown() },
            onReadingPreferences: { showsReadingPreferences = true },
            onToggleArchive: { viewModel?.archiveArticle() },
            onOpenOriginal: { openOriginal() },
            onDelete: { showsDeleteConfirmation = true }
        )
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack {
            // Globe: open original URL
            Button {
                openOriginal()
            } label: {
                Image(systemName: "globe")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.folio.textSecondary)
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel(String(localized: "reader.openOriginal", defaultValue: "Open Original"))
            .opacity(article.url != nil ? 1 : 0)
            .disabled(article.url == nil)

            Spacer()

            // Progress percentage
            Text("\(Int((viewModel?.readingProgress ?? 0) * 100))%")
                .font(.system(size: 13, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(Color.folio.textTertiary)
                .accessibilityLabel(String(localized: "reader.progressLabel", defaultValue: "Reading progress \(Int((viewModel?.readingProgress ?? 0) * 100)) percent"))

            Spacer()

            // Share button
            Button {
                showsShareSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.folio.textSecondary)
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel(String(localized: "reader.shareArticle", defaultValue: "Share article"))
            .sheet(isPresented: $showsShareSheet) {
                if let url = viewModel?.shareURL() {
                    ShareSheet(activityItems: [url])
                }
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.bottom, 34)
        .background(
            LinearGradient(
                stops: [
                    .init(color: Color.folio.background.opacity(0), location: 0),
                    .init(color: Color.folio.background, location: 0.3),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Open Original

    private static let externalBrowserHosts: Set<String> = [
        "x.com", "www.x.com", "twitter.com", "www.twitter.com",
        "mobile.x.com", "mobile.twitter.com"
    ]

    private func openOriginal() {
        guard let urlString = article.url, let url = URL(string: urlString) else { return }
        if let host = url.host(), Self.externalBrowserHosts.contains(host) {
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
