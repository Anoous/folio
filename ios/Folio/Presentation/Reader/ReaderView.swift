import SwiftUI
import SwiftData

struct ReaderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AuthViewModel.self) private var authViewModel: AuthViewModel?

    let article: Article

    @State private var viewModel: ReaderViewModel?
    @State private var showsMoreMenu = false
    @State private var showsShareSheet = false
    @State private var showsReadingPreferences = false
    @State private var showsWebView = false
    @State private var showsDeleteConfirmation = false

    // Reading preferences
    @AppStorage("reader_fontSize") private var fontSize: Double = 17
    @AppStorage("reader_lineSpacing") private var lineSpacing: Double = 11.9

    var body: some View {
        Group {
            if let viewModel {
                readerContent(viewModel: viewModel)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(Color.folio.textPrimary)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                moreMenuButton
            }
        }
        .toast(isPresented: Binding(
            get: { viewModel?.showToast ?? false },
            set: { viewModel?.showToast = $0 }
        ), message: viewModel?.toastMessage ?? "", icon: viewModel?.toastIcon)
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
        .sheet(isPresented: $showsReadingPreferences) {
            ReadingPreferenceView()
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showsWebView) {
            if let url = URL(string: article.url) {
                WebViewContainer(url: url)
            }
        }
        .confirmationDialog(
            String(localized: "reader.deleteConfirm", defaultValue: "Delete this article?"),
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "reader.delete", defaultValue: "Delete"), role: .destructive) {
                viewModel?.deleteArticle()
                dismiss()
            }
        }
    }

    // MARK: - Reader Content

    @ViewBuilder
    private func readerContent(viewModel: ReaderViewModel) -> some View {
        GeometryReader { outerGeometry in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // Article title
                    Text(article.title ?? article.url)
                        .font(Typography.articleTitle)
                        .foregroundStyle(Color.folio.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Meta info card
                    ArticleMetaInfoView(
                        article: article,
                        wordCount: viewModel.wordCount,
                        readingTimeMinutes: viewModel.estimatedReadTimeMinutes
                    )

                    // AI Summary
                    if let summary = article.summary {
                        aiSummarySection(summary: summary)
                    }

                    // Key Points
                    if !article.keyPoints.isEmpty {
                        keyPointsSection(keyPoints: article.keyPoints)
                    }

                    // Markdown body
                    if let content = article.markdownContent {
                        MarkdownRenderer(
                            markdownText: content,
                            fontSize: CGFloat(fontSize),
                            lineSpacing: CGFloat(lineSpacing)
                        )
                    } else {
                        contentUnavailableView
                    }

                    Spacer(minLength: Spacing.xl)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.md)
                .background(
                    GeometryReader { innerGeometry in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: innerGeometry.frame(in: .named("scroll")).origin.y
                        )
                    }
                )
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                updateReadingProgress(offset: offset, outerHeight: outerGeometry.size.height)
            }
            .safeAreaInset(edge: .bottom) {
                bottomToolbar
            }
        }
    }

    // MARK: - AI Summary Section

    private func aiSummarySection(summary: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xxs) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(Color.folio.accent)
                Text(String(localized: "reader.aiSummary", defaultValue: "AI Summary"))
                    .font(Typography.tag)
                    .foregroundStyle(Color.folio.accent)
            }

            Text(summary)
                .font(Typography.body)
                .foregroundStyle(Color.folio.textSecondary)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.folio.accent.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    // MARK: - Key Points Section

    private func keyPointsSection(keyPoints: [String]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(String(localized: "reader.keyPoints", defaultValue: "Key Points"))
                .font(Typography.tag)
                .foregroundStyle(Color.folio.textSecondary)

            ForEach(Array(keyPoints.enumerated()), id: \.offset) { _, point in
                HStack(alignment: .top, spacing: Spacing.xs) {
                    Text("\u{2022}")
                        .foregroundStyle(Color.folio.accent)
                    Text(point)
                        .font(Typography.body)
                        .foregroundStyle(Color.folio.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.folio.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .stroke(Color.folio.separator, lineWidth: 0.5)
        )
    }

    // MARK: - Content Unavailable

    private var contentUnavailableView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(Color.folio.textTertiary)

            Text(String(localized: "reader.noContent", defaultValue: "Content not yet available"))
                .font(Typography.body)
                .foregroundStyle(Color.folio.textSecondary)

            FolioButton(
                title: String(localized: "reader.openOriginal", defaultValue: "Open Original"),
                style: .secondary
            ) {
                showsWebView = true
            }
            .frame(width: 200)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }

    // MARK: - More Menu

    private var moreMenuButton: some View {
        Menu {
            Button {
                viewModel?.toggleFavorite()
            } label: {
                Label(
                    article.isFavorite
                        ? String(localized: "reader.unfavorite", defaultValue: "Remove Favorite")
                        : String(localized: "reader.favorite", defaultValue: "Favorite"),
                    systemImage: article.isFavorite ? "heart.fill" : "heart"
                )
            }

            Button {
                viewModel?.copyMarkdown()
            } label: {
                Label(String(localized: "reader.copyMarkdown", defaultValue: "Copy Markdown"), systemImage: "doc.on.doc")
            }

            Button {
                showsReadingPreferences = true
            } label: {
                Label(String(localized: "reader.readingPrefs", defaultValue: "Reading Preferences"), systemImage: "textformat.size")
            }

            Button {
                viewModel?.archiveArticle()
            } label: {
                Label(
                    article.isArchived
                        ? String(localized: "reader.unarchive", defaultValue: "Unarchive")
                        : String(localized: "reader.archive", defaultValue: "Archive"),
                    systemImage: article.isArchived ? "archivebox.fill" : "archivebox"
                )
            }

            Button {
                showsWebView = true
            } label: {
                Label(String(localized: "reader.openInBrowser", defaultValue: "Open Original"), systemImage: "safari")
            }

            Divider()

            Button(role: .destructive) {
                showsDeleteConfirmation = true
            } label: {
                Label(String(localized: "reader.delete", defaultValue: "Delete"), systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(Color.folio.textPrimary)
        }
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack {
            Button {
                showsWebView = true
            } label: {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "safari")
                    Text(String(localized: "reader.original", defaultValue: "Original"))
                        .font(Typography.caption)
                }
                .foregroundStyle(Color.folio.textSecondary)
            }

            Spacer()

            // Reading progress indicator
            Text("\(Int(viewModel?.readingProgress ?? 0 * 100))%")
                .font(Typography.caption)
                .foregroundStyle(Color.folio.textTertiary)

            Spacer()

            Button {
                showsShareSheet = true
            } label: {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "square.and.arrow.up")
                    Text(String(localized: "reader.share", defaultValue: "Share"))
                        .font(Typography.caption)
                }
                .foregroundStyle(Color.folio.textSecondary)
            }
            .sheet(isPresented: $showsShareSheet) {
                if let url = viewModel?.shareURL() {
                    ShareSheet(activityItems: [url])
                }
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.sm)
        .background(.ultraThinMaterial)
    }

    // MARK: - Reading Progress Tracking

    private func updateReadingProgress(offset: CGFloat, outerHeight: CGFloat) {
        // offset is the Y position of the inner content within the scroll coordinate space.
        // As the user scrolls down, offset becomes increasingly negative.
        guard offset < 0 else { return }
        let scrolled = abs(offset)
        // Estimate total scrollable height as a rough multiple of screen
        let estimatedContentHeight = max(outerHeight * 3, outerHeight)
        let progress = scrolled / estimatedContentHeight
        viewModel?.updateReadingProgress(progress)
    }
}

// MARK: - Scroll Offset Preference Key

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
