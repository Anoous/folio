import SwiftUI

/// A floating capsule that opens a compose sheet for capturing links and thoughts.
struct ComposeBar: View {
    @State private var showCompose = false
    let onSave: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button { showCompose = true } label: {
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
        .sheet(isPresented: $showCompose) {
            ComposeSheet(onSave: { content in
                showCompose = false
                onSave(content)
            })
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
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

/// Half-sheet compose view for entering links and thoughts.
struct ComposeSheet: View {
    @State private var text = ""
    @FocusState private var isFocused: Bool
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.md) {
                TextField(
                    String(localized: "compose.placeholder",
                           defaultValue: "Your thought or link..."),
                    text: $text,
                    axis: .vertical
                )
                .lineLimit(1...10)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .font(Typography.body)
                .padding(Spacing.md)

                Spacer()
            }
            .navigationTitle(String(localized: "compose.title", defaultValue: "Capture"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "button.cancel", defaultValue: "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(hasContent ? Color.accentColor : Color.folio.textTertiary)
                    }
                    .disabled(!hasContent)
                }
            }
        }
        .onAppear { isFocused = true }
    }

    private func save() {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(content)
    }
}
