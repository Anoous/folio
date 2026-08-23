import SwiftUI

struct ArticleNoteEditor: View {
    let onChange: (String) -> Void
    @State private var text: String

    init(text: String, onChange: @escaping (String) -> Void) {
        _text = State(initialValue: text)
        self.onChange = onChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(.articleNoteTitle)
                .font(.headline)
                .foregroundStyle(FolioPalette.inkGreenDeep)

            TextField(text: $text, axis: .vertical) {
                Text(.articleNotePlaceholder)
            }
            .lineLimit(3...6)
            .padding(14)
            .background(FolioPalette.surface, in: .rect(cornerRadius: FolioMetrics.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: FolioMetrics.controlRadius)
                    .stroke(FolioPalette.paperLine, lineWidth: 0.8)
            }
            .onChange(of: text) { _, newValue in
                onChange(newValue)
            }
            .accessibilityIdentifier("article-note-field")
        }
    }
}
