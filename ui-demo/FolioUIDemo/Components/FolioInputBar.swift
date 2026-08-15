import SwiftUI

struct FolioInputBar: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let placeholder: String
    let isEnabled: Bool
    var sendSymbol = "arrow.up"
    let action: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(placeholder, text: $text, axis: .vertical)
                .font(.body)
                .lineLimit(1...4)
                .focused($isFocused)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.send)
                .onSubmit(action)
                .padding(.leading, 6)
                .padding(.vertical, 10)
                .accessibilityIdentifier("ask-question-field")

            Button("发送", systemImage: sendSymbol, action: action)
                .labelStyle(.iconOnly)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isEnabled ? .white : FolioPalette.tertiaryText)
                .frame(width: FolioMetrics.minimumTapTarget, height: FolioMetrics.minimumTapTarget)
                .background(isEnabled ? FolioPalette.inkGreenDeep : FolioPalette.evidence.opacity(0.8))
                .clipShape(.circle)
                .disabled(!isEnabled)
                .accessibilityIdentifier("ask-send")
        }
        .padding(.leading, 12)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .frame(minHeight: 56)
        .background(FolioPalette.surface)
        .clipShape(.rect(cornerRadius: 29))
        .overlay {
            RoundedRectangle(cornerRadius: 29)
                .stroke(FolioPalette.paperLine, lineWidth: 0.8)
        }
        .shadow(color: FolioPalette.inkGreenDeep.opacity(0.06), radius: 14, y: 6)
    }
}
