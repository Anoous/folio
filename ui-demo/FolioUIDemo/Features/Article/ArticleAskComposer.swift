import SwiftUI

struct ArticleAskComposer: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let canSubmit: Bool
    let onAddContext: () -> Void
    let onVoicePrompt: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button("引用当前文章", systemImage: "plus", action: onAddContext)
                .labelStyle(.iconOnly)
                .font(.body.bold())
                .foregroundStyle(FolioPalette.inkGreenDeep)
                .frame(
                    width: FolioMetrics.minimumTapTarget,
                    height: FolioMetrics.minimumTapTarget
                )
                .background {
                    Circle()
                        .fill(.thinMaterial)
                        .overlay {
                            Circle()
                                .fill(FolioPalette.surface.opacity(0.78))
                        }
                }
                .overlay {
                    Circle()
                        .stroke(FolioPalette.paperLine.opacity(0.8), lineWidth: 0.8)
                }
                .buttonStyle(FolioPressButtonStyle())
                .accessibilityIdentifier("article-ask-context")

            HStack(alignment: .bottom, spacing: 4) {
                TextField("问这篇文章…", text: $text, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...3)
                    .focused($isFocused)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.send)
                    .onSubmit(onSubmit)
                    .padding(.leading, 12)
                    .padding(.vertical, 11)
                    .accessibilityIdentifier("article-ask-field")

                Button("填入语音示例问题", systemImage: "microphone", action: onVoicePrompt)
                    .labelStyle(.iconOnly)
                    .font(.body)
                    .foregroundStyle(FolioPalette.secondaryText)
                    .frame(
                        width: FolioMetrics.minimumTapTarget,
                        height: FolioMetrics.minimumTapTarget
                    )
                    .buttonStyle(FolioPressButtonStyle())
                    .accessibilityIdentifier("article-ask-voice")

                Button("发送", systemImage: "arrow.up", action: onSubmit)
                    .labelStyle(.iconOnly)
                    .font(.body.bold())
                    .foregroundStyle(canSubmit ? .white : FolioPalette.tertiaryText)
                    .frame(
                        width: FolioMetrics.minimumTapTarget,
                        height: FolioMetrics.minimumTapTarget
                    )
                    .background(
                        canSubmit ? FolioPalette.inkGreenDeep : FolioPalette.evidence,
                        in: .circle
                    )
                    .disabled(!canSubmit)
                    .buttonStyle(FolioPressButtonStyle())
                    .accessibilityIdentifier("article-ask-send")
            }
            .padding(.leading, 2)
            .padding(.trailing, 5)
            .padding(.vertical, 5)
            .frame(minHeight: 54)
            .background {
                RoundedRectangle(cornerRadius: 28)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 28)
                            .fill(FolioPalette.surface.opacity(0.72))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 28)
                    .stroke(FolioPalette.paperLine.opacity(0.8), lineWidth: 0.8)
            }
            .shadow(
                color: FolioPalette.inkGreenDeep.opacity(0.14),
                radius: 18,
                y: 8
            )
        }
    }
}

#Preview {
    @Previewable @State var text = ""
    @Previewable @FocusState var isFocused: Bool

    ArticleAskComposer(
        text: $text,
        isFocused: $isFocused,
        canSubmit: !text.isEmpty,
        onAddContext: {},
        onVoicePrompt: {},
        onSubmit: {}
    )
    .padding()
    .background(FolioPalette.canvas)
}
