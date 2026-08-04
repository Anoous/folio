import SwiftUI

struct LibraryView: View {
    let articles: [DemoArticle]
    let onOpenArticle: (DemoArticle) -> Void
    let onOpenSettings: () -> Void
    let transitionNamespace: Namespace.ID
    @State private var showsFilters = false
    @State private var selectedFilter = LibraryFilter.all

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 13) {
                    Text("资料库")
                        .font(FolioTypography.editorialBold(34, relativeTo: .largeTitle))
                        .foregroundStyle(FolioPalette.inkGreenDeep)
                        .lineLimit(1)

                    Spacer()

                    FolioFilterButton(action: showFilters)

                    Button(action: onOpenSettings) {
                        FolioAvatar(size: FolioMetrics.minimumTapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("打开设置")
                }
                .padding(.top, 18)
                .padding(.bottom, 17)

                LazyVStack(spacing: 0) {
                    ForEach(filteredArticles) { article in
                        LibraryArticleRow(
                            article: article,
                            transitionNamespace: transitionNamespace,
                            onOpen: { onOpenArticle(article) }
                        )
                    }
                }
            }
            .padding(.horizontal, FolioMetrics.libraryInset)
        }
        .scrollIndicators(.hidden)
        .background(FolioPalette.canvas)
        .confirmationDialog("筛选资料库", isPresented: $showsFilters) {
            Button("全部内容", action: showAllArticles)
            Button("处理中", action: showProcessingArticles)
            Button("受限", action: showLimitedArticles)
            Button("取消", role: .cancel, action: dismissFilters)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func showFilters() {
        showsFilters = true
    }

    private var filteredArticles: [DemoArticle] {
        switch selectedFilter {
        case .all:
            articles
        case .processing:
            articles.filter { $0.status == .processing }
        case .limited:
            articles.filter { $0.status == .limited }
        }
    }

    private func showAllArticles() {
        selectedFilter = .all
    }

    private func showProcessingArticles() {
        selectedFilter = .processing
    }

    private func showLimitedArticles() {
        selectedFilter = .limited
    }

    private func dismissFilters() {
        showsFilters = false
    }
}

#Preview {
    @Previewable @Namespace var transitionNamespace

    LibraryView(
        articles: DemoContent.articles,
        onOpenArticle: { _ in },
        onOpenSettings: {},
        transitionNamespace: transitionNamespace
    )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FolioTabBar(
                selectedTab: .constant(.library)
            )
                .padding(.horizontal, FolioMetrics.compactInset)
                .padding(.vertical, 8)
        }
}
