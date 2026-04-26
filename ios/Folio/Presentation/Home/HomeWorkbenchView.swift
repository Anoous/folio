import SwiftUI

struct HomeWorkbenchView: View {
    var viewModel: HomeViewModel
    let quotaSnapshot: HomeQuotaSnapshot
    let isAuthenticated: Bool
    let isNetworkAvailable: Bool
    let activeMilestone: Milestone?
    let onDismissMilestone: (Milestone) -> Void
    let onOpenSearch: () -> Void
    let onOpenSettings: () -> Void
    let onPasteURL: (URL) -> Void
    let onTextTap: () -> Void
    let onPhotoSelected: (UIImage) -> Void
    let onArticleAction: (ArticleRowAction, Article) -> Void
    let onRetrySync: () -> Void
    let onDismissSyncError: () -> Void
    let onRetryEcho: () -> Void

    var body: some View {
        List {
            statusRows
            captureRows
            quotaRows
            processingRows
            readingRows
            askRows
            echoRows
            milestoneRows
            libraryRows
            bottomSpacer
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.folio.background)
    }

    @ViewBuilder
    private var statusRows: some View {
        if !isNetworkAvailable {
            HomeOfflineBannerView()
                .plainWorkbenchRow()
        }

        if let syncError = viewModel.syncError {
            HomeSyncErrorBannerView(
                message: syncError,
                onRetry: onRetrySync,
                onDismiss: onDismissSyncError
            )
            .plainWorkbenchRow()
        }
    }

    @ViewBuilder
    private var captureRows: some View {
        HomeQuickCaptureView(
            onPasteURL: onPasteURL,
            onTextTap: onTextTap,
            onPhotoSelected: onPhotoSelected
        )
        .plainWorkbenchRow()
    }

    @ViewBuilder
    private var quotaRows: some View {
        if quotaSnapshot.shouldShowOnWorkbench {
            HomeQuotaStatusView(snapshot: quotaSnapshot, onOpenSettings: onOpenSettings)
                .plainWorkbenchRow()
        }
    }

    @ViewBuilder
    private var readingRows: some View {
        if shouldShowReading {
            HomeSectionHeaderView(
                title: "继续阅读",
                subtitle: nil
            )
            .plainWorkbenchRow()

            HomeContinueReadingView(
                continueArticles: viewModel.continueReadingArticles,
                suggestedArticles: viewModel.suggestedReadingArticles,
                isLoading: viewModel.isLoading && viewModel.articles.isEmpty
            )
            .plainWorkbenchRow()
        }
    }

    @ViewBuilder
    private var processingRows: some View {
        if !viewModel.processingArticles.isEmpty {
            HomeSectionHeaderView(
                title: "处理中",
                subtitle: nil
            )
            .plainWorkbenchRow()

            HomeProcessingQueueView(
                articles: viewModel.processingArticles,
                onRetry: { article in onArticleAction(.retry, article) }
            )
            .plainWorkbenchRow()
        }
    }

    @ViewBuilder
    private var askRows: some View {
        if viewModel.readyArticleCount > 0 {
            HomeAskFolioCardView(
                isAuthenticated: isAuthenticated,
                readyArticleCount: viewModel.readyArticleCount,
                onAsk: onOpenSearch,
                onOpenSettings: onOpenSettings
            )
            .plainWorkbenchRow()
        }
    }

    @ViewBuilder
    private var echoRows: some View {
        if let echoCard = viewModel.intersectionEchoCard {
            EchoCardView(
                card: EchoCardData(from: echoCard),
                onReview: { result, completion in
                    viewModel.submitEchoReview(
                        cardID: echoCard.id,
                        result: result,
                        completion: completion
                    )
                }
            )
            .plainWorkbenchRow()
        } else if viewModel.isEchoLoading || viewModel.echoError != nil {
            HomeEchoSummaryView(
                isAuthenticated: isAuthenticated,
                isLoading: viewModel.isEchoLoading,
                errorMessage: viewModel.echoError,
                remainingToday: viewModel.echoRemainingToday,
                weeklyCount: viewModel.echoWeeklyCount,
                weeklyLimit: viewModel.echoWeeklyLimit,
                onRetry: onRetryEcho,
                onOpenSettings: onOpenSettings
            )
            .plainWorkbenchRow()
        }
    }

    @ViewBuilder
    private var milestoneRows: some View {
        if let activeMilestone {
            MilestoneCardView(
                milestone: activeMilestone,
                articleCount: viewModel.articles.count,
                onDismiss: { onDismissMilestone(activeMilestone) }
            )
            .plainWorkbenchRow()
        }
    }

    @ViewBuilder
    private var libraryRows: some View {
        if !viewModel.articles.isEmpty {
            HomeSectionHeaderView(
                title: "最近",
                subtitle: nil
            )
            .plainWorkbenchRow()

            ForEach(Array(viewModel.feedSections.enumerated()), id: \.element.group) { _, section in
                HomeSectionHeaderView(title: section.group.rawValue, subtitle: nil)
                    .plainWorkbenchRow()

                ForEach(section.items) { item in
                    switch item {
                    case .article(let article):
                        HomeArticleRow(
                            article: article,
                            articleCount: viewModel.articles.count,
                            articleIndex: viewModel.articles.firstIndex(where: { $0.id == article.id })
                        ) { action in
                            onArticleAction(action, article)
                        }
                        .listRowInsets(EdgeInsets(
                            top: 0,
                            leading: Spacing.screenPadding,
                            bottom: 0,
                            trailing: Spacing.screenPadding
                        ))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    case .echo:
                        EmptyView()
                    }
                }
            }
        }
    }

    private var bottomSpacer: some View {
        Color.clear
            .frame(height: Spacing.xl)
            .plainWorkbenchRow()
    }

    private var shouldShowReading: Bool {
        (viewModel.isLoading && viewModel.articles.isEmpty)
            || !viewModel.continueReadingArticles.isEmpty
            || !viewModel.suggestedReadingArticles.isEmpty
    }
}
