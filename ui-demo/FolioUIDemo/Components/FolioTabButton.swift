import SwiftUI

struct FolioTabButton: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: isSelected ? 5 : 0) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .contentTransition(.symbolEffect(.replace))

                Text(title)
                    .font(.footnote)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(maxWidth: isSelected ? nil : 0)
                    .opacity(isSelected ? 1 : 0)
                    .clipped()
            }
            .foregroundStyle(isSelected ? FolioPalette.inkGreenDeep : FolioPalette.tertiaryText)
            .padding(.horizontal, isSelected ? 8 : 0)
            .frame(minWidth: FolioMetrics.tabBarItemHeight, minHeight: FolioMetrics.tabBarItemHeight)
            .contentShape(.capsule)
        }
        .buttonStyle(FolioPressButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "已选中" : "")
    }
}
