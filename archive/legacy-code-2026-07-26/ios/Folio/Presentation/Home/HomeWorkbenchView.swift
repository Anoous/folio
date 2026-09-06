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

    private var metrics: HomeWorkbenchMetrics {
        viewModel.workbenchMetrics
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                statusRows
                captureRows
                echoRows
                workbenchMetricRows
                milestoneRows
                lowerBreathingRoom
                libraryRows
                bottomSpacer
            }
        }
        .contentMargins(.bottom, 154, for: .scrollContent)
        .background(FolioPaperPalette.background)
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
        } else if viewModel.isEchoLoading || viewModel.echoError != nil || !isAuthenticated {
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
            .padding(.bottom, 30)
        }
    }

    private var workbenchMetricRows: some View {
        HomeWorkbenchStatusStrip(
            processingCount: metrics.processingCount,
            continueReadingCount: metrics.continueReadingCount,
            askableCount: metrics.askableCount
        )
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
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xs)

            ForEach(Array(viewModel.feedSections.enumerated()), id: \.element.group) { _, section in
                HomeSectionHeaderView(title: section.group.rawValue, subtitle: nil)
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.top, Spacing.md)

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
                        .padding(.horizontal, Spacing.screenPadding)
                        .padding(.vertical, 4)

                    case .echo:
                        EmptyView()
                    }
                }
            }
        }
    }

    private var lowerBreathingRoom: some View {
        Color.clear
            .frame(height: 218)
    }

    private var bottomSpacer: some View {
        Color.clear
            .frame(height: 32)
    }

    private var shouldShowReading: Bool {
        (viewModel.isLoading && viewModel.articles.isEmpty)
            || !viewModel.continueReadingArticles.isEmpty
            || !viewModel.suggestedReadingArticles.isEmpty
    }
}
