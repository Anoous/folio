import SwiftUI

struct HighlightNoteCard: View {
    let highlight: DemoHighlight
    let shouldFocus: Bool
    let onChange: (String) -> Void
    let onDelete: () -> Void
    @State private var note: String
    @FocusState private var isNoteFocused: Bool

    init(
        highlight: DemoHighlight,
        shouldFocus: Bool,
        onChange: @escaping (String) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.highlight = highlight
        self.shouldFocus = shouldFocus
        self.onChange = onChange
        self.onDelete = onDelete
        _note = State(initialValue: highlight.note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(FolioPalette.annotationHighlight)
                    .frame(width: 3)

                Text(highlight.quote)
                    .font(FolioTypography.editorial(16, relativeTo: .body))
                    .foregroundStyle(.primary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            TextField(text: $note, axis: .vertical) {
                Text(.highlightNotePlaceholder)
            }
            .lineLimit(2...5)
            .focused($isNoteFocused)
            .padding(12)
            .background(FolioPalette.canvas, in: .rect(cornerRadius: 11))
            .onChange(of: note) { _, newValue in
                onChange(newValue)
            }
            .accessibilityIdentifier("highlight-note-\(highlight.id)")

            Button(.deleteHighlight, systemImage: "trash", role: .destructive, action: onDelete)
                .font(.footnote)
        }
        .padding(16)
        .background(FolioPalette.surface, in: .rect(cornerRadius: FolioMetrics.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: FolioMetrics.cardRadius)
                .stroke(FolioPalette.paperLine, lineWidth: 0.8)
        }
        .task {
            if shouldFocus {
                isNoteFocused = true
            }
        }
    }
}
