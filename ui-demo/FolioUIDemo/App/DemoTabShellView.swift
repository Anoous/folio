import SwiftUI

struct DemoTabShellView: View {
    @Bindable var store: DemoStore
    let articleTransition: Namespace.ID
    @State private var quickSavePhase = QuickSavePhase.idle
    @State private var quickSaveText = ""
    @State private var blocksReturnHitTesting = false
    @FocusState private var isAskQuestionFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch store.selectedTab {
            case .library:
                LibraryView(
                    store: store,
                    onOpenSettings: { store.open(.settings) },
                    onBeginSaving: beginQuickSave,
                    onShowShareDemo: { store.open(.shareSuccess) },
                    transitionNamespace: articleTransition
                )

            case .ask:
                AskHomeView(
                    onOpenSettings: { store.open(.settings) },
                    onOpenSource: { store.open(.insight) },
                    isQuestionFocused: $isAskQuestionFocused
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(!quickSavePhase.isExpanded && !blocksReturnHitTesting)
        .accessibilityHidden(quickSavePhase.isExpanded || blocksReturnHitTesting)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ZStack {
                if !isAskQuestionFocused {
                    FolioTabBar(
                        selectedTab: $store.selectedTab,
                        quickSavePhase: $quickSavePhase,
                        quickSaveText: $quickSaveText,
                        onSelect: store.selectTab,
                        onQuickSave: store.captureURL,
                        onRecoverQuickSave: recoverQuickSave
                    )
                    .transition(.opacity)
                }
            }
            .frame(height: FolioMetrics.tabBarHeight)
            .padding(.horizontal, FolioMetrics.compactInset)
            .padding(.vertical, 8)
        }
        .animation(
            FolioMotion.chromeVisibility(reduceMotion: reduceMotion),
            value: isAskQuestionFocused
        )
        .onChange(of: quickSavePhase, coordinateQuickSaveFocus)
        .onChange(of: store.selectedTab, coordinateTabFocus)
        .onChange(of: store.path, coordinateNavigationFocus)
        .alert(item: $store.activeNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("好"))
            )
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func beginQuickSave() {
        withAnimation(FolioMotion.toolbarMorph(reduceMotion: reduceMotion)) {
            quickSavePhase = .editing
        }
    }

    private func recoverQuickSave(_ failure: DemoCaptureFailure) {
        switch failure {
        case .offline:
            store.isOnline = true
        case .timeout:
            break
        case .sessionExpired:
            store.expireSession()
        case .capacityFull:
            store.open(.settings)
        }
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
        if oldPath.isEmpty, !newPath.isEmpty {
            isAskQuestionFocused = false
        }

        guard !oldPath.isEmpty, newPath.isEmpty else { return }
        blocksReturnHitTesting = true

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            guard store.path.isEmpty else { return }
            blocksReturnHitTesting = false
        }
    }
}
