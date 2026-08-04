import SwiftUI

struct DemoTabShellView: View {
    @Bindable var store: DemoStore
    let articleTransition: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LibraryView(
                articles: store.libraryArticles,
                onOpenArticle: { article in store.open(.article(article)) },
                onOpenSettings: { store.open(.settings) },
                transitionNamespace: articleTransition
            )
            .opacity(store.selectedTab == .library ? 1 : 0)
            .scaleEffect(reduceMotion || store.selectedTab == .library ? 1 : 0.985, anchor: .bottom)
            .offset(x: reduceMotion || store.selectedTab == .library ? 0 : -12)
            .allowsHitTesting(store.selectedTab == .library)
            .accessibilityHidden(store.selectedTab != .library)

            AskHomeView(
                onOpenSettings: { store.open(.settings) },
                onAnswer: { store.open(.askAnswer) },
                onInsufficientEvidence: { store.open(.askInsufficient) }
            )
            .opacity(store.selectedTab == .ask ? 1 : 0)
            .scaleEffect(reduceMotion || store.selectedTab == .ask ? 1 : 0.985, anchor: .bottom)
            .offset(x: reduceMotion || store.selectedTab == .ask ? 0 : 12)
            .allowsHitTesting(store.selectedTab == .ask)
            .accessibilityHidden(store.selectedTab != .ask)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(FolioMotion.pageSwitch(reduceMotion: reduceMotion), value: store.selectedTab)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FolioTabBar(
                selectedTab: $store.selectedTab,
                onSelect: store.selectTab,
                onQuickSave: store.saveURL
            )
            .padding(.horizontal, FolioMetrics.compactInset)
            .padding(.vertical, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
