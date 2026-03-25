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

    @ViewBuilder
    private var screenshotContentView: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Screenshot image thumbnail (only for .screenshot with localImagePath)
            if article.sourceType == .screenshot,
               let localPath = article.localImagePath,
               let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier) {
                let imageURL = containerURL.appendingPathComponent(localPath)
                if let uiImage = UIImage(contentsOfFile: imageURL.path) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .onTapGesture {
                                tappedImageURL = imageURL
                            }

                        Button {
                            tappedImageURL = imageURL
                        } label: {
                            HStack(spacing: 4) {
                                Text("查看原图")
                                    .font(.system(size: 14))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                            }
                            .foregroundStyle(Color.folio.accent)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, Spacing.screenPadding)
                }
            }

            // Text content (OCR text or voice transcription)
            if let content = article.markdownContent, !content.isEmpty {
                Text(content)
                    .font(Typography.body)
                    .foregroundStyle(Color.folio.textPrimary)
                    .lineSpacing(17 * 0.65)
                    .padding(.horizontal, Spacing.screenPadding)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Insight Panel

    private var insightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (always visible)
            Button {
                withAnimation(Motion.settle) { isInsightExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Text("✦")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.folio.accent)

                    Text(article.displaySummary ?? "")
                        .font(Typography.v3InsightMain)
                        .foregroundStyle(Color.folio.textPrimary)
                        .lineSpacing(15 * 0.55)
                        .lineLimit(isInsightExpanded ? nil : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.folio.textQuaternary)
                        .rotationEffect(.degrees(isInsightExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            // Detail (expanded only)
            if isInsightExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle()
                        .fill(Color.folio.separator)
                        .frame(height: 0.5)
                        .padding(.top, 14)
                        .padding(.bottom, 12)

                    ForEach(article.keyPoints, id: \.self) { point in
                        HStack(alignment: .top, spacing: 0) {
                            Text("·")
                                .foregroundStyle(Color.folio.textQuaternary)
                                .frame(width: 24)
                            Text(point)
                                .font(.system(size: 14))
                                .foregroundStyle(Color.folio.textSecondary)
                                .lineSpacing(14 * 0.6)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(Color.folio.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.bottom, 24)
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

    private func dismissMenuThen(_ action: @escaping () -> Void) {
        showMoreMenu = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: action)
    }

    private var readerMenuSheet: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                menuRow(
                    icon: article.isFavorite ? "bookmark.fill" : "bookmark",
                    label: article.isFavorite
                        ? String(localized: "reader.unfavorite", defaultValue: "取消收藏")
                        : String(localized: "reader.favorite", defaultValue: "收藏")
                ) {
                    dismissMenuThen { viewModel?.toggleFavorite() }
                }

                menuSeparator

                menuRow(icon: "doc.on.doc", label: String(localized: "reader.copyMarkdown", defaultValue: "复制 Markdown")) {
                    dismissMenuThen { viewModel?.copyMarkdown() }
                }

                menuSeparator

                menuRow(icon: "textformat.size", label: String(localized: "reader.readingPrefs", defaultValue: "阅读偏好")) {
                    dismissMenuThen { showsReadingPreferences = true }
                }

                menuSeparator

                menuRow(
                    icon: article.isArchived ? "archivebox.fill" : "archivebox",
                    label: article.isArchived
                        ? String(localized: "reader.unarchive", defaultValue: "取消归档")
                        : String(localized: "reader.archive", defaultValue: "归档")
                ) {
                    dismissMenuThen { viewModel?.archiveArticle() }
                }

                if article.url != nil {
                    menuSeparator

                    menuRow(icon: "globe", label: String(localized: "reader.openInBrowser", defaultValue: "查看原文")) {
                        dismissMenuThen { openOriginal() }
                    }
                }

                menuSeparator

                menuRow(icon: "trash", label: String(localized: "reader.delete", defaultValue: "删除"), isDestructive: true) {
                    dismissMenuThen { showsDeleteConfirmation = true }
                }
            }
            .padding(.horizontal, Spacing.screenPadding)

            Spacer().frame(height: Spacing.lg)

            // Cancel button
            Button {
                showMoreMenu = false
            } label: {
                Text(String(localized: "button.cancel", defaultValue: "取消"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.folio.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.folio.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, Spacing.screenPadding)
        }
        .padding(.top, Spacing.md)
        .padding(.bottom, 34)
        .background(Color.folio.background)
    }

    private func menuRow(icon: String, label: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .imageScale(.medium)
                    .symbolRenderingMode(.monochrome)
                    .fontWeight(.regular)
                    .foregroundStyle(isDestructive ? Color.folio.error : Color.folio.textPrimary)
                    .frame(width: 24, alignment: .center)

                Text(label)
                    .font(.system(size: 16))
                    .foregroundStyle(isDestructive ? Color.folio.error : Color.folio.textPrimary)

                Spacer()
            }
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private var menuSeparator: some View {
        Rectangle()
            .fill(Color.folio.separator)
            .frame(height: 0.5)
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

// MARK: - Share Sheet (UIKit wrapper)

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
