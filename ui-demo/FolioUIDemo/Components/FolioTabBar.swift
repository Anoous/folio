import SwiftUI

struct FolioTabBar: View {
    @Binding var selectedTab: DemoTab
    @Binding var quickSavePhase: QuickSavePhase
    @Binding var quickSaveText: String
    var onSelect: ((DemoTab) -> Void)?
    var onQuickSave: ((URL) -> DemoCaptureResult)?
    var onRecoverQuickSave: ((DemoCaptureFailure) -> Void)?
    @Namespace private var glassNamespace
    @Namespace private var selectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        selectedTab: Binding<DemoTab>,
        quickSavePhase: Binding<QuickSavePhase>,
        quickSaveText: Binding<String>,
        onSelect: ((DemoTab) -> Void)? = nil,
        onQuickSave: ((URL) -> DemoCaptureResult)? = nil,
        onRecoverQuickSave: ((DemoCaptureFailure) -> Void)? = nil
    ) {
        _selectedTab = selectedTab
        _quickSavePhase = quickSavePhase
        _quickSaveText = quickSaveText
        self.onSelect = onSelect
        self.onQuickSave = onQuickSave
        self.onRecoverQuickSave = onRecoverQuickSave
    }

    var body: some View {
        GlassEffectContainer(spacing: FolioMetrics.tabBarSpacing) {
            HStack(spacing: FolioMetrics.tabBarSpacing) {
                if quickSavePhase == .idle {
                    HStack(spacing: 0) {
                        FolioTabButton(
                            title: "资料库",
                            symbol: "books.vertical",
                            isSelected: selectedTab == .library,
                            selectionNamespace: selectionNamespace,
                            action: selectLibrary
                        )

                        FolioTabButton(
                            title: "问答",
                            symbol: "sparkles",
                            isSelected: selectedTab == .ask,
                            selectionNamespace: selectionNamespace,
                            action: selectAsk
                        )
                    }
                    .background(
                        reduceTransparency ? FolioPalette.surface.opacity(0.96) : .clear,
                        in: .capsule
                    )
                    .glassEffect(navigationGlass, in: .capsule)
                    .glassEffectID("folio-navigation", in: glassNamespace)
                    .glassEffectTransition(.matchedGeometry)
                }

                FolioQuickSaveControl(
                    phase: $quickSavePhase,
                    text: $quickSaveText,
                    glassNamespace: glassNamespace,
                    onSave: handleQuickSave,
                    onRecover: handleQuickSaveRecovery
                )
            }
            .frame(maxWidth: quickSavePhase.isExpanded ? .infinity : nil)
            .fixedSize(horizontal: !quickSavePhase.isExpanded, vertical: false)
        }
        .frame(maxWidth: .infinity)
        .animation(FolioMotion.segmentSelection(reduceMotion: reduceMotion), value: selectedTab)
        .sensoryFeedback(.selection, trigger: selectedTab)
    }

    private func selectLibrary() {
        select(.library)
    }

    private func selectAsk() {
        select(.ask)
    }

    private func select(_ tab: DemoTab) {
        withAnimation(FolioMotion.toolbarMorph(reduceMotion: reduceMotion)) {
            quickSavePhase = .idle
            quickSaveText = ""
        }

        if let onSelect {
            onSelect(tab)
        } else {
            selectedTab = tab
        }
    }

    private var navigationGlass: Glass {
        reduceTransparency ? .identity : .regular.interactive()
    }

    private func handleQuickSave(_ url: URL) -> DemoCaptureResult {
        onQuickSave?(url) ?? .success(.accepted(host: url.host() ?? "链接"))
    }

    private func handleQuickSaveRecovery(_ failure: DemoCaptureFailure) {
        onRecoverQuickSave?(failure)
    }
}
