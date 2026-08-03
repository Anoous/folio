import SwiftUI

struct FolioSegmentedControl: View {
    @Binding var selectedIndex: Int
    let titles: [String]
    @Namespace private var selectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 0) {
            ForEach(titles.indices, id: \.self) { index in
                Button(action: { select(index) }) {
                    ZStack {
                        if selectedIndex == index {
                            if reduceMotion {
                                Capsule()
                                    .fill(selectionFill)
                                    .overlay(selectionHighlight)
                                    .shadow(color: selectionShadow, radius: 3, y: 1)
                                    .transition(.opacity)
                            } else {
                                Capsule()
                                    .fill(selectionFill)
                                    .overlay(selectionHighlight)
                                    .shadow(color: selectionShadow, radius: 3, y: 1)
                                    .matchedGeometryEffect(
                                        id: "selected-segment-indicator",
                                        in: selectionNamespace
                                    )
                            }
                        }

                        Text(titles[index])
                            .font(FolioTypography.editorial(15, relativeTo: .subheadline))
                            .foregroundStyle(
                                selectedIndex == index
                                    ? FolioPalette.inkGreenDeep
                                    : FolioPalette.secondaryText
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: FolioMetrics.segmentedControlVisualHeight)
                    .contentShape(.capsule)
                }
                    .frame(minHeight: FolioMetrics.minimumTapTarget)
                    .contentShape(.rect)
                    .buttonStyle(.plain)
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
        .frame(maxWidth: .infinity)
        .animation(FolioMotion.segmentSelection(reduceMotion: reduceMotion), value: selectedIndex)
        .sensoryFeedback(.selection, trigger: selectedIndex)
    }

    private func select(_ index: Int) {
        selectedIndex = index
    }

    private var selectionFill: Color {
        reduceTransparency
            ? FolioPalette.surface
            : FolioPalette.subtleGreen.opacity(0.82)
    }

    private var selectionHighlight: some View {
        Capsule()
            .stroke(Color.white.opacity(reduceTransparency ? 0.4 : 0.72), lineWidth: 0.75)
    }

    private var selectionShadow: Color {
        Color.black.opacity(reduceTransparency ? 0.04 : 0.07)
    }
}
