import SwiftUI

struct DemoNavigationView: View {
    @Bindable var store: DemoStore
    @Namespace private var articleTransition

    var body: some View {
        NavigationStack(path: $store.path) {
            DemoTabShellView(store: store, articleTransition: articleTransition)
                .navigationDestination(for: DemoRoute.self) { route in
                    switch route {
                    case .article(let article):
                        ArticleDetailView(
                            article: article,
                            onBack: store.pop,
                            initialMode: .original
                        )
                        .navigationTransition(
                            .zoom(sourceID: article.id, in: articleTransition)
                        )
                    case .insight:
                        ArticleDetailView(
                            article: DemoContent.primaryArticle,
                            onBack: store.pop,
                            initialMode: .insight
                        )
                        .navigationTransition(
                            .zoom(sourceID: DemoContent.primaryArticle.id, in: articleTransition)
                        )
                    case .evidence:
                        ArticleDetailView(
                            article: DemoContent.primaryArticle,
                            onBack: store.pop,
                            initialMode: .insight,
                            initiallyShowsEvidence: true
                        )
                    case .reader:
                        ArticleDetailView(
                            article: DemoContent.primaryArticle,
                            onBack: store.pop,
                            initialMode: .original
                        )
                    case .settings:
                        SettingsView(onBack: store.pop, onShowShareSuccess: { store.open(.shareSuccess) })
                    case .askAnswer:
                        AskAnswerView(
                            onBack: store.pop,
                            onOpenSource: { store.open(.insight) }
                        )
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            FolioTabBar(
                                selectedTab: $store.selectedTab,
                                onSelect: store.selectTab,
                                onQuickSave: store.saveURL
                            )
                            .padding(.horizontal, FolioMetrics.compactInset)
                            .padding(.vertical, 8)
                        }
                    case .askInsufficient:
                        AskInsufficientView(onSuggestion: { store.open(.askAnswer) })
                            .safeAreaInset(edge: .bottom, spacing: 0) {
                                FolioTabBar(
                                    selectedTab: $store.selectedTab,
                                    onSelect: store.selectTab,
                                    onQuickSave: store.saveURL
                                )
                                .padding(.horizontal, FolioMetrics.compactInset)
                                .padding(.vertical, 8)
                            }
                    case .shareSuccess:
                        ShareSaveSuccessView(onDone: store.pop)
                    }
                }
        }
    }
}
