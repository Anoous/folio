import SwiftUI

struct UnifiedInputBar: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let onSend: (String) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: Spacing.xs) {
            TextField(
                String(localized: "input.placeholder",
                       defaultValue: "Search, jot a thought, or paste a link..."),
                text: $text,
                axis: .vertical
            )
            .lineLimit(1...6)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .font(Typography.body)
            .padding(.vertical, Spacing.xs)

            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    text = ""
                    isFocused = false
                    onSend(content)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
        .animation(.easeInOut(duration: 0.15), value: text.isEmpty)
    }
}

extension UnifiedInputBar {
    /// Returns true if the trimmed text is a single URL with no other meaningful text.
    static func isURLOnly(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let matches = detector?.matches(in: trimmed, range: range) ?? []
        guard matches.count == 1, let match = matches.first else { return false }
        return match.range.length == range.length
    }
}
