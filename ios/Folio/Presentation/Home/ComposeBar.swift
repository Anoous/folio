import SwiftUI

/// Bottom bar for saving links and thoughts. Separate from search.
struct ComposeBar: View {
    @State private var text = ""
    @FocusState private var isFocused: Bool
    let onSave: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .bottom, spacing: Spacing.xs) {
            TextField(
                String(localized: "compose.placeholder",
                       defaultValue: "Paste a link or jot a thought..."),
                text: $text,
                axis: .vertical
            )
            .lineLimit(1...6)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .font(Typography.body)
            .padding(.vertical, Spacing.xs)

            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: save) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(ScaleButtonStyle())
                .accessibilityLabel(String(localized: "compose.save", defaultValue: "Save"))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
        .animation(Motion.resolved(Motion.settle, reduceMotion: reduceMotion), value: text.isEmpty)
    }

    private func save() {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""
        isFocused = false
        onSave(content)
    }

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
