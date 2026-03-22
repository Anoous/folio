import SwiftUI

struct ManualNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var text: String
    @FocusState private var isFocused: Bool
    let onSave: (String) -> Void

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($isFocused)
                .font(Typography.cardSummary)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.xs)
                .navigationTitle(String(localized: "note.title", defaultValue: "New Note"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "button.cancel", defaultValue: "Cancel")) {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "note.save", defaultValue: "Save")) {
                            let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            onSave(content)
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                    }
                }
                .onAppear { isFocused = true }
        }
        .presentationDetents([.medium, .large])
    }
}
