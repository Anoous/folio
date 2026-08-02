import SwiftUI

struct FolioInputBar: View {
    @Binding var text: String
    let placeholder: String
    let isEnabled: Bool
    var sendSymbol = "arrow.up"
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $text)
                .font(FolioTypography.editorial(17, relativeTo: .body))
                .textInputAutocapitalization(.never)
                .submitLabel(.send)
                .onSubmit(action)

            Button("发送", systemImage: sendSymbol, action: action)
                .labelStyle(.iconOnly)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(isEnabled ? FolioPalette.inkGreenDeep : FolioPalette.tertiaryText.opacity(0.25))
                .clipShape(.circle)
                .disabled(!isEnabled)
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .frame(height: 56)
        .background(FolioPalette.surface.opacity(0.96))
        .clipShape(.rect(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke(FolioPalette.paperLine, lineWidth: 0.8)
        }
    }
}
