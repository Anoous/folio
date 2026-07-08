import SwiftUI

struct FolioTabBarView: View {
    let selection: HomeTab
    let onSelect: (HomeTab) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    var body: some View {
        GlassPillView(cornerRadius: 31) {
            HStack(spacing: 0) {
                ForEach(HomeTab.allCases) { item in
                    tabItem(item)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 58)
        }
        .frame(maxWidth: .infinity)
        .animation(Motion.resolved(.spring(duration: 0.26, bounce: 0.08), reduceMotion: reduceMotion), value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func tabItem(_ item: HomeTab) -> some View {
        Button {
            guard item != selection else { return }
            onSelect(item)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 20, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .frame(height: 26)

                Text(item.title)
                    .font(.system(size: 11, weight: item == selection ? .semibold : .regular))
            }
            .foregroundStyle(item == selection ? FolioPaperPalette.accentBlue : FolioPaperPalette.tabInactive)
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .background {
                if item == selection {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.34))
                        .blur(radius: 0.1)
                        .matchedGeometryEffect(id: "selected-tab-background", in: selectionNamespace)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(item == selection ? .isSelected : [])
    }
}
