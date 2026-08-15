import SwiftUI

struct LibraryView: View {
    let articles: [DemoArticle]
    let onOpenArticle: (DemoArticle) -> Void
    let onOpenSettings: () -> Void
    let transitionNamespace: Namespace.ID

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 13) {
                    Text("资料库")
                        .font(FolioTypography.editorialBold(34, relativeTo: .largeTitle))
                        .foregroundStyle(FolioPalette.inkGreenDeep)
                        .lineLimit(1)

                    Spacer()

                    Button(action: onOpenSettings) {
                        FolioAvatar(size: FolioMetrics.minimumTapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("打开设置")
                }
                .padding(.top, 18)
                .padding(.bottom, 17)

                LazyVStack(spacing: 0) {
                    ForEach(articles) { article in
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
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    @Previewable @Namespace var transitionNamespace
    @Previewable @State var selectedTab = DemoTab.library
    @Previewable @State var quickSavePhase = QuickSavePhase.idle
    @Previewable @State var quickSaveText = ""

    LibraryView(
        articles: DemoContent.articles,
        onOpenArticle: { _ in },
        onOpenSettings: {},
        transitionNamespace: transitionNamespace
    )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FolioTabBar(
                selectedTab: $selectedTab,
                quickSavePhase: $quickSavePhase,
                quickSaveText: $quickSaveText
            )
                .padding(.horizontal, FolioMetrics.compactInset)
                .padding(.vertical, 8)
        }
}
