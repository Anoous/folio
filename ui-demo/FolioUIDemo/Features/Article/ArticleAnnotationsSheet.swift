import SwiftUI

struct ArticleAnnotationsSheet: View {
    @Bindable var store: DemoStore
    let article: DemoArticle
    let focusedHighlightID: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    AnnotationSyncStatusView(
                        state: store.annotationSyncState
                    )

                    ArticleNoteEditor(
                        text: store.articleNote(for: article.id),
                        onChange: updateArticleNote
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Text(.highlightsAndNotesTitle)
                            .font(.headline)
                            .foregroundStyle(FolioPalette.inkGreenDeep)

                        if articleHighlights.isEmpty {
                            ContentUnavailableView(
                                .noHighlightsTitle,
                                systemImage: "highlighter",
                                description: Text(.noHighlightsDescription)
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        } else {
                            ForEach(articleHighlights) { highlight in
                                HighlightNoteCard(
                                    highlight: highlight,
                                    shouldFocus: focusedHighlightID == highlight.id,
                                    onChange: { updateHighlightNote($0, highlightID: highlight.id) },
                                    onDelete: { store.removeHighlight(highlight) }
                                )
                            }
                        }
                    }

                    ShareLink(item: store.markdownExport(for: article)) {
                        Label(.exportMarkdown, systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(FolioPressButtonStyle(scalesOnPress: false))
                    .foregroundStyle(FolioPalette.inkGreenDeep)
                    .background(FolioPalette.evidence, in: .rect(cornerRadius: FolioMetrics.cardRadius))
                    .accessibilityIdentifier("annotation-export-markdown")
                }
                .padding(20)
            }
            .background(FolioPalette.canvas)
            .accessibilityIdentifier("annotations-sheet")
            .navigationTitle(.annotationsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(.done, action: close)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var articleHighlights: [DemoHighlight] {
        store.highlights(for: article.id)
    }

    private func updateArticleNote(_ text: String) {
        store.updateArticleNote(text, for: article.id)
    }

    private func updateHighlightNote(_ text: String, highlightID: UUID) {
        store.updateHighlightNote(text, highlightID: highlightID)
    }

    private func close() {
        dismiss()
    }
}
