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
    let onMicTap: () -> Void
    let onPhotoSelected: (UIImage) -> Void
    let onArticleAction: (ArticleRowAction, Article) -> Void
    let onRetrySync: () -> Void
    let onDismissSyncError: () -> Void
    let onRetryEcho: () -> Void

    var body: some View {
        List {
            statusRows
            headerRows
            captureRows
            readingRows
            processingRows
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
    private var headerRows: some View {
        HomeWorkbenchHeaderView(
            articleCount: viewModel.articles.count,
            readyCount: viewModel.readyArticleCount,
            processingCount: viewModel.processingArticles.count,
            echoCount: viewModel.echoCards.count
        )
        .plainWorkbenchRow()
    }

    @ViewBuilder
    private var captureRows: some View {
        HomeSectionHeaderView(title: "快速捕获", subtitle: "每天最常用的入口")
            .plainWorkbenchRow()

        HomeQuickCaptureView(
            onPasteURL: onPasteURL,
            onTextTap: onTextTap,
            onMicTap: onMicTap,
            onPhotoSelected: onPhotoSelected
        )
        .plainWorkbenchRow()

        HomeQuotaStatusView(snapshot: quotaSnapshot, onOpenSettings: onOpenSettings)
            .plainWorkbenchRow()
    }

    @ViewBuilder
    private var readingRows: some View {
        HomeSectionHeaderView(
            title: "继续阅读",
            subtitle: viewModel.continueReadingArticles.isEmpty ? "下一篇可读内容" : "从上次停下的位置继续"
        )
        .plainWorkbenchRow()

        HomeContinueReadingView(
            continueArticles: viewModel.continueReadingArticles,
            suggestedArticles: viewModel.suggestedReadingArticles,
            isLoading: viewModel.isLoading && viewModel.articles.isEmpty
        )
        .plainWorkbenchRow()
    }

    @ViewBuilder
    private var processingRows: some View {
        HomeSectionHeaderView(
            title: "处理队列",
            subtitle: "保存、分析、失败和本地就绪状态"
        )
        .plainWorkbenchRow()

        HomeProcessingQueueView(
            articles: viewModel.processingArticles,
            onRetry: { article in onArticleAction(.retry, article) }
        )
        .plainWorkbenchRow()
    }

    @ViewBuilder
    private var askRows: some View {
        HomeSectionHeaderView(
            title: "Ask Folio",
            subtitle: "只在有来源时回答"
        )
        .plainWorkbenchRow()

        HomeAskFolioCardView(
            isAuthenticated: isAuthenticated,
            readyArticleCount: viewModel.readyArticleCount,
            onAsk: onOpenSearch,
            onOpenSettings: onOpenSettings
        )
        .plainWorkbenchRow()
    }

    @ViewBuilder
    private var echoRows: some View {
        HomeSectionHeaderView(
            title: "今日 Echo",
            subtitle: "10 秒主动回忆"
        )
        .plainWorkbenchRow()

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
        } else {
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
        HomeSectionHeaderView(
            title: "最近资料库",
            subtitle: viewModel.articles.isEmpty ? "捕获完成后会按时间进入这里" : "\(viewModel.articles.count) 个条目"
        )
        .plainWorkbenchRow()

        if viewModel.articles.isEmpty {
            ContentUnavailableView(
                "资料库还是空的",
                systemImage: "tray",
                description: Text("使用上方入口保存第一条内容。")
            )
            .frame(maxWidth: .infinity, minHeight: 120)
            .plainWorkbenchRow()
        } else {
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
}
