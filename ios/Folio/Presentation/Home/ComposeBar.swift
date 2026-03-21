import SwiftUI

/// Capsule button + hidden TextField trick for keyboard-attached input.
/// Tap capsule → hidden field focuses → keyboard appears → toolbar shows real input.
struct ComposeBar: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let onSave: (String) -> Void

    var body: some View {
        ZStack {
            // Hidden TextField to own the keyboard
            TextField("", text: $text, axis: .vertical)
                .focused($isFocused)
                .frame(width: 0, height: 0)
                .opacity(0)
                .allowsHitTesting(false)

            // Visible capsule (hidden when focused — keyboard toolbar takes over)
            if !isFocused {
                Button { isFocused = true } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "square.and.pencil")
                            .font(.body)
                        Text(String(localized: "compose.capture", defaultValue: "Capture"))
                            .font(Typography.body)
                    }
                    .foregroundStyle(Color.folio.textSecondary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }
                .buttonStyle(ScaleButtonStyle())
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xs)
            }
        }
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

/// The input bar that lives in .toolbar(.keyboard).
struct ComposeToolbarContent: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let onSave: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

            Text(text.isEmpty
                 ? String(localized: "compose.placeholder", defaultValue: "Your thought or link...")
                 : text)
                .font(Typography.body)
                .foregroundStyle(text.isEmpty ? Color.folio.textTertiary : Color.folio.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

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
