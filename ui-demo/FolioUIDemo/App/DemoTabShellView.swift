import SwiftUI

struct DemoTabShellView: View {
    @Bindable var store: DemoStore
    let articleTransition: Namespace.ID
    @State private var quickSavePhase = QuickSavePhase.idle
    @State private var quickSaveText = ""
    @FocusState private var isAskQuestionFocused: Bool
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
            .allowsHitTesting(store.selectedTab == .library)
            .accessibilityHidden(store.selectedTab != .library)

            AskHomeView(
                onOpenSettings: { store.open(.settings) },
                onOpenSource: { store.open(.insight) },
                onReturnHome: { store.selectTab(.library) },
                isQuestionFocused: $isAskQuestionFocused
            )
            .opacity(store.selectedTab == .ask ? 1 : 0)
            .allowsHitTesting(store.selectedTab == .ask)
            .accessibilityHidden(store.selectedTab != .ask)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(!quickSavePhase.isExpanded)
        .accessibilityHidden(quickSavePhase.isExpanded)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isAskQuestionFocused {
                FolioTabBar(
                    selectedTab: $store.selectedTab,
                    quickSavePhase: $quickSavePhase,
                    quickSaveText: $quickSaveText,
                    onSelect: store.selectTab,
                    onQuickSave: store.saveURL
                )
                .padding(.horizontal, FolioMetrics.compactInset)
                .padding(.vertical, 8)
                .transition(rootNavigationTransition)
            }
        }
        .animation(FolioMotion.toolbarMorph(reduceMotion: reduceMotion), value: isAskQuestionFocused)
        .onChange(of: quickSavePhase, coordinateQuickSaveFocus)
        .onChange(of: store.selectedTab, coordinateTabFocus)
        .onChange(of: store.path, coordinateNavigationFocus)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var rootNavigationTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .move(edge: .bottom).combined(with: .opacity)
    }

    private func coordinateQuickSaveFocus(
        _ oldPhase: QuickSavePhase,
        _ newPhase: QuickSavePhase
    ) {
        guard !oldPhase.isExpanded, newPhase.isExpanded else { return }
        isAskQuestionFocused = false
    }

    private func coordinateTabFocus(_ oldTab: DemoTab, _ newTab: DemoTab) {
        guard oldTab != newTab, newTab != .ask else { return }
        isAskQuestionFocused = false
    }

    private func coordinateNavigationFocus(_ oldPath: [DemoRoute], _ newPath: [DemoRoute]) {
        guard oldPath.isEmpty, !newPath.isEmpty else { return }
        isAskQuestionFocused = false
    }
}
