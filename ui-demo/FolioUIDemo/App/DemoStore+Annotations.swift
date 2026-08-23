import Foundation

extension DemoStore {
    func highlights(for articleID: UUID) -> [DemoHighlight] {
        highlights
            .filter { $0.articleID == articleID }
            .sorted {
                if $0.paragraphIndex == $1.paragraphIndex {
                    $0.rangeLocation < $1.rangeLocation
                } else {
                    $0.paragraphIndex < $1.paragraphIndex
                }
            }
    }

    func highlights(for articleID: UUID, paragraphIndex: Int) -> [DemoHighlight] {
        highlights(for: articleID).filter { $0.paragraphIndex == paragraphIndex }
    }

    func articleNote(for articleID: UUID) -> String {
        articleNotes[articleID] ?? ""
    }

    @discardableResult
    func addHighlight(
        to article: DemoArticle,
        selection: DemoTextSelection
    ) -> DemoHighlight? {
        guard article.originalParagraphs.indices.contains(selection.paragraphIndex),
              selection.range.location >= 0,
              selection.range.length > 0 else {
            return nil
        }

        let paragraph = article.originalParagraphs[selection.paragraphIndex] as NSString
        let paragraphRange = NSRange(location: 0, length: paragraph.length)
        guard NSLocationInRange(selection.range.location, paragraphRange),
              NSMaxRange(selection.range) <= paragraph.length else {
            return nil
        }

        if let existing = highlights.first(where: {
            $0.articleID == article.id
                && $0.paragraphIndex == selection.paragraphIndex
                && $0.range == selection.range
        }) {
            return existing
        }

        let highlight = DemoHighlight(
            articleID: article.id,
            paragraphIndex: selection.paragraphIndex,
            rangeLocation: selection.range.location,
            rangeLength: selection.range.length,
            quote: selection.text
        )
        highlights.append(highlight)
        markAnnotationsChanged()
        return highlight
    }

    func updateArticleNote(_ text: String, for articleID: UUID) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            articleNotes[articleID] = nil
        } else {
            articleNotes[articleID] = text
        }
        markAnnotationsChanged()
    }

    func updateHighlightNote(_ text: String, highlightID: UUID) {
        guard let index = highlights.firstIndex(where: { $0.id == highlightID }) else { return }
        highlights[index].note = text
        markAnnotationsChanged()
    }

    func removeHighlight(_ highlight: DemoHighlight) {
        highlights.removeAll { $0.id == highlight.id }
        markAnnotationsChanged()
    }

    func removeAnnotations(for articleID: UUID) {
        highlights.removeAll { $0.articleID == articleID }
        articleNotes[articleID] = nil
    }

    private func markAnnotationsChanged() {
        annotationSyncTask?.cancel()
        annotationSyncState = .syncing
        annotationSyncTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(480))
            guard !Task.isCancelled else { return }
            self?.annotationSyncState = .synced
            self?.annotationSyncTask = nil
        }
    }
}
