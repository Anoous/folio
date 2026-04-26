import SwiftUI

struct FolioTabBarView: View {
    enum Selection {
        case today
        case library
        case ask
        case me
    }

    let selection: Selection
    let onSelect: (Selection) -> Void

    var body: some View {
        GlassPillView(cornerRadius: 34) {
            HStack(spacing: 0) {
                tabItem(.today, title: "今日", systemImage: "house.fill")
                tabItem(.library, title: "资料库", systemImage: "books.vertical")
                tabItem(.ask, title: "提问", systemImage: "bubble.left")
                tabItem(.me, title: "我", systemImage: "person")
            }
            .padding(.horizontal, 10)
            .frame(height: 64)
        }
        .frame(maxWidth: .infinity)
    }

    private func tabItem(_ item: Selection, title: String, systemImage: String) -> some View {
        Button {
            onSelect(item)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: item == .today ? 21 : 21, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .frame(height: 28)

                Text(title)
                    .font(.system(size: 12, weight: item == selection ? .semibold : .regular))
            }
            .foregroundStyle(item == selection ? FolioPaperPalette.accentBlue : Color.gray.opacity(0.92))
            .frame(maxWidth: .infinity, minHeight: 56)
            .background {
                if item == selection {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.28))
                        .blur(radius: 0.1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
