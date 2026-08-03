import SwiftUI

struct FolioTabBar: View {
    @Binding var selectedTab: DemoTab
    let navigationNamespace: Namespace.ID
    var onSelect: ((DemoTab) -> Void)?
    var onQuickSave: (() -> Void)?
    @Namespace private var glassNamespace
    @Namespace private var selectionNamespace
    @State private var isQuickSaveExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        selectedTab: Binding<DemoTab>,
        navigationNamespace: Namespace.ID,
        onSelect: ((DemoTab) -> Void)? = nil,
        onQuickSave: (() -> Void)? = nil
    ) {
        _selectedTab = selectedTab
        self.navigationNamespace = navigationNamespace
        self.onSelect = onSelect
        self.onQuickSave = onQuickSave
    }

    var body: some View {
        GlassEffectContainer(spacing: FolioMetrics.tabBarSpacing) {
            HStack(spacing: FolioMetrics.tabBarSpacing) {
                HStack(spacing: 0) {
                    FolioTabButton(
                        title: "阅读",
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
                .background(reduceTransparency ? FolioPalette.surface.opacity(0.96) : .clear, in: .capsule)
                .glassEffect(navigationGlass, in: .capsule)
                .glassEffectID("folio-navigation", in: glassNamespace)
                .glassEffectTransition(.matchedGeometry)

                if onQuickSave != nil {
                    FolioQuickSaveControl(
                        isExpanded: $isQuickSaveExpanded,
                        glassNamespace: glassNamespace,
                        navigationNamespace: navigationNamespace,
                        onSave: quickSave
                    )
                }
            }
            .fixedSize(horizontal: true, vertical: false)
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
            isQuickSaveExpanded = false
        }

        if let onSelect {
            onSelect(tab)
        } else {
            selectedTab = tab
        }
    }

    private func quickSave() {
        onQuickSave?()
    }

    private var navigationGlass: Glass {
        reduceTransparency ? .identity : .regular.interactive()
    }
}
