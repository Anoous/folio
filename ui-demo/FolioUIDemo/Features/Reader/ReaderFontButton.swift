import SwiftUI

struct ReaderFontButton: View {
    let font: ReaderFontChoice
    @Binding var selection: ReaderFontChoice

    private var isSelected: Bool {
        selection == font
    }

    var body: some View {
        Button(action: selectFont) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(font.title)
                        .font(font.emphasizedFont(17, relativeTo: .headline))

                    Text(font.licenseNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("阅读预览")
                    .font(font.regularFont(17, relativeTo: .body))
                    .foregroundStyle(.secondary)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? FolioPalette.inkGreenDeep : FolioPalette.paperLine)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 64)
            .background(FolioPalette.surface.opacity(0.82), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? FolioPalette.inkGreenDeep : FolioPalette.paperLine.opacity(0.8),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(font.title)
        .accessibilityValue(isSelected ? "已选择，\(font.licenseNote)" : font.licenseNote)
    }

    private func selectFont() {
        selection = font
    }
}
