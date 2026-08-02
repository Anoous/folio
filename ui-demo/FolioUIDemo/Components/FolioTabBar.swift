import SwiftUI

struct FolioTabBar: View {
    @Binding var selectedTab: DemoTab
    let navigationNamespace: Namespace.ID
    var onSelect: ((DemoTab) -> Void)?
    var onQuickSave: (() -> Void)?
    @Namespace private var glassNamespace
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
                FolioTabButton(
                    title: "资料库",
                    symbol: "books.vertical",
                    isSelected: selectedTab == .library,
                    action: selectLibrary
                )
                .background(reduceTransparency ? FolioPalette.surface.opacity(0.96) : .clear, in: .capsule)
                .glassEffect(tabGlass(isSelected: selectedTab == .library), in: .capsule)
                .glassEffectID("folio-library", in: glassNamespace)
                .glassEffectTransition(.matchedGeometry)

                FolioTabButton(
                    title: "提问",
                    symbol: "sparkles",
                    isSelected: selectedTab == .ask,
                    action: selectAsk
                )
                .background(reduceTransparency ? FolioPalette.surface.opacity(0.96) : .clear, in: .capsule)
                .glassEffect(tabGlass(isSelected: selectedTab == .ask), in: .capsule)
                .glassEffectID("folio-ask", in: glassNamespace)
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
        .animation(FolioMotion.toolbarMorph(reduceMotion: reduceMotion), value: selectedTab)
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

    private func tabGlass(isSelected: Bool) -> Glass {
        guard !reduceTransparency else { return .identity }
        return isSelected
            ? .regular.tint(FolioPalette.subtleGreen).interactive()
            : .regular.interactive()
    }
}
