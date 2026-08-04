import SwiftUI

struct FolioTabButton: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let selectionNamespace: Namespace.ID
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    selectionIndicator
                }

                HStack(spacing: 5) {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .regular))
                        .symbolRenderingMode(.hierarchical)

                    Text(title)
                        .font(.footnote)
                        .lineLimit(1)
                }
                .foregroundStyle(isSelected ? FolioPalette.inkGreenDeep : FolioPalette.tertiaryText)
            }
            .frame(
                width: FolioMetrics.tabBarItemWidth,
                height: FolioMetrics.tabBarItemHeight
            )
            .contentShape(.capsule)
        }
        .buttonStyle(FolioPressButtonStyle(scalesOnPress: false))
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "已选中" : "")
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        if reduceMotion {
            selectionCapsule
                .transition(.opacity)
        } else {
            selectionCapsule
                .matchedGeometryEffect(
                    id: "selected-tab-indicator",
                    in: selectionNamespace
                )
        }
    }

    private var selectionCapsule: some View {
        FolioGlassLens(
            shape: Capsule(),
            tint: FolioPalette.inkGreen
        )
            .padding(3)
    }
}
