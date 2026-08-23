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
                            store: store,
                            article: article,
                            onBack: store.pop,
                            initialMode: .original
                        )
                        .navigationTransition(
                            .zoom(sourceID: article.id, in: articleTransition)
                        )
                    case .insight:
                        ArticleDetailView(
                            store: store,
                            article: DemoContent.primaryArticle,
                            onBack: store.pop,
                            initialMode: .insight
                        )
                    case .evidence:
                        ArticleDetailView(
                            store: store,
                            article: DemoContent.primaryArticle,
                            onBack: store.pop,
                            initialMode: .insight,
                            initiallyShowsEvidence: true
                        )
                    case .reader:
                        ArticleDetailView(
                            store: store,
                            article: DemoContent.primaryArticle,
                            onBack: store.pop,
                            initialMode: .original
                        )
                    case .searchResult(let result):
                        ArticleDetailView(
                            store: store,
                            article: result.article,
                            onBack: store.pop,
                            initialMode: .original,
                            initialParagraphIndex: result.paragraphIndex
                        )
                        .navigationTransition(
                            .zoom(sourceID: result.article.id, in: articleTransition)
                        )
                    case .settings:
                        SettingsView(
                            store: store,
                            onBack: store.pop,
                            onShowShareSuccess: { store.open(.shareSuccess) },
                            onShowDevices: { store.open(.deviceSessions) }
                        )
                    case .deviceSessions:
                        DeviceSessionsView(store: store, onBack: store.pop)
                    case .askAnswer:
                        AskAnswerView(
                            onBack: store.pop,
                            onOpenSource: { store.open(.insight) }
                        )
                    case .askInsufficient:
                        AskInsufficientView(
                            onBack: store.pop,
                            onSuggestion: { store.open(.askAnswer) }
                        )
                    case .shareSuccess:
                        ShareSaveSuccessView(onDone: store.pop)
                    }
                }
        }
    }
}
