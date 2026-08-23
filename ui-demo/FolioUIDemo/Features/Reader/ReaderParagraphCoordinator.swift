import SwiftUI

final class ReaderParagraphCoordinator: NSObject, UITextViewDelegate {
    var paragraphIndex: Int
    var onHighlight: (DemoTextSelection) -> Void
    var onAddNote: (DemoTextSelection) -> Void

    init(
        paragraphIndex: Int,
        onHighlight: @escaping (DemoTextSelection) -> Void,
        onAddNote: @escaping (DemoTextSelection) -> Void
    ) {
        self.paragraphIndex = paragraphIndex
        self.onHighlight = onHighlight
        self.onAddNote = onAddNote
    }

    func textView(
        _ textView: UITextView,
        editMenuForTextIn range: NSRange,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        guard let selection = selection(in: textView, range: range) else {
            return UIMenu(children: suggestedActions)
        }

        let highlightAction = UIAction(
            title: String(localized: .readerHighlightSelection),
            image: UIImage(systemName: "highlighter")
        ) { [weak self] _ in
            self?.onHighlight(selection)
        }
        let noteAction = UIAction(
            title: String(localized: .readerAddNoteToSelection),
            image: UIImage(systemName: "note.text.badge.plus")
        ) { [weak self] _ in
            self?.onAddNote(selection)
        }
        let folioActions = UIMenu(options: .displayInline, children: [highlightAction, noteAction])
        return UIMenu(children: [folioActions] + suggestedActions)
    }

    private func selection(in textView: UITextView, range: NSRange) -> DemoTextSelection? {
        guard range.location != NSNotFound,
              range.length > 0,
              NSMaxRange(range) <= (textView.text as NSString).length else {
            return nil
        }

        let selectedText = (textView.text as NSString).substring(with: range)
        return DemoTextSelection(
            paragraphIndex: paragraphIndex,
            range: range,
            text: selectedText
        )
    }
}
