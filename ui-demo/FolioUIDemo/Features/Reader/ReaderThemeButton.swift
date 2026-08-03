import SwiftUI

struct ReaderThemeButton: View {
    let theme: ReaderTheme
    @Binding var selection: ReaderTheme

    private var isSelected: Bool {
        selection == theme
    }

    var body: some View {
        Button(action: selectTheme) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    VStack(alignment: .leading, spacing: 5) {
                        Capsule().frame(width: 28, height: 3)
                        Capsule().frame(width: 18, height: 3)
                        Capsule().frame(height: 3)
                        Capsule().frame(width: 38, height: 3)
                    }
                    .foregroundStyle(theme.textColor.opacity(0.22))
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(FolioPalette.inkGreenDeep)
                            .padding(7)
                    }
                }
                .background(theme.backgroundColor, in: .rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            isSelected ? FolioPalette.inkGreenDeep : FolioPalette.paperLine,
                            lineWidth: isSelected ? 2 : 1
                        )
                }

                Text(theme.title)
                    .font(.footnote)
                    .foregroundStyle(isSelected ? FolioPalette.inkGreenDeep : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.title)
        .accessibilityValue(isSelected ? "已选择" : "未选择")
    }

    private func selectTheme() {
        selection = theme
    }
}
