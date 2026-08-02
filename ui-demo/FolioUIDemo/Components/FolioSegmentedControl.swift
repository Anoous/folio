import SwiftUI

struct FolioSegmentedControl: View {
    @Binding var selectedIndex: Int
    let titles: [String]
    @Namespace private var selectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(titles.indices, id: \.self) { index in
                    Button(action: { select(index) }) {
                        Text(titles[index])
                            .font(FolioTypography.editorial(15, relativeTo: .subheadline))
                            .foregroundStyle(
                                selectedIndex == index
                                    ? FolioPalette.inkGreenDeep
                                    : FolioPalette.secondaryText
                            )
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: FolioMetrics.segmentedControlVisualHeight)
                            .contentShape(.capsule)
                            .glassEffect(
                                selectedIndex == index ? selectedGlass : .identity,
                                in: .capsule
                            )
                            .glassEffectID(
                                selectedIndex == index ? "selected-segment" : nil,
                                in: selectionNamespace
                            )
                            .glassEffectTransition(.matchedGeometry)
                    }
                        .frame(minHeight: FolioMetrics.minimumTapTarget)
                        .contentShape(.rect)
                        .buttonStyle(FolioPressButtonStyle())
                        .accessibilityAddTraits(selectedIndex == index ? .isSelected : [])
                }
            }
            .frame(maxWidth: FolioMetrics.segmentedControlMaxWidth)
            .background {
                Capsule()
                    .fill(
                        reduceTransparency
                            ? FolioPalette.surface.opacity(0.96)
                            : FolioPalette.evidence.opacity(0.24)
                    )
                    .frame(height: FolioMetrics.segmentedControlVisualHeight)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(FolioMotion.toolbarMorph(reduceMotion: reduceMotion), value: selectedIndex)
        .sensoryFeedback(.selection, trigger: selectedIndex)
    }

    private func select(_ index: Int) {
        selectedIndex = index
    }

    private var selectedGlass: Glass {
        reduceTransparency ? .identity : .clear.tint(FolioPalette.subtleGreen).interactive()
    }
}
