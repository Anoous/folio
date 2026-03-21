import SwiftUI

/// A text field styled as a capsule. Tap it = start typing (keyboard + toolbar appear).
/// Two steps: tap & type → send.
struct ComposeBar: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let onSave: (String) -> Void

    var body: some View {
        // The capsule IS the text field — tapping it starts typing directly
        HStack(spacing: Spacing.xs) {
            Image(systemName: "square.and.pencil")
                .font(.body)
                .foregroundStyle(Color.folio.textSecondary)

            TextField(
                String(localized: "compose.capture", defaultValue: "Capture"),
                text: $text
            )
            .textFieldStyle(.plain)
            .focused($isFocused)
            .font(Typography.body)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.xs)
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

/// Send/close buttons above the keyboard.
struct ComposeToolbarContent: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let onSave: (String) -> Void

    private var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Button {
                text = ""
                isFocused = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.folio.textTertiary)
            }
            .buttonStyle(.plain)

            Spacer()

            if hasContent {
                Button {
                    let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    text = ""
                    isFocused = false
                    onSave(content)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(ScaleButtonStyle())
                .accessibilityLabel(String(localized: "compose.save", defaultValue: "Save"))
            }
        }
    }
}
