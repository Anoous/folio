import SwiftUI

struct SelectableReaderParagraph: UIViewRepresentable {
    let text: String
    let paragraphIndex: Int
    let highlights: [DemoHighlight]
    let fontChoice: ReaderFontChoice
    let theme: ReaderTheme
    let onHighlight: (DemoTextSelection) -> Void
    let onAddNote: (DemoTextSelection) -> Void

    func makeCoordinator() -> ReaderParagraphCoordinator {
        ReaderParagraphCoordinator(
            paragraphIndex: paragraphIndex,
            onHighlight: onHighlight,
            onAddNote: onAddNote
        )
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.accessibilityTraits = .staticText
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.paragraphIndex = paragraphIndex
        context.coordinator.onHighlight = onHighlight
        context.coordinator.onAddNote = onAddNote
        textView.attributedText = attributedText
        textView.accessibilityLabel = text
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let fittingSize = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: ceil(fittingSize.height))
    }

    private var attributedText: NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 8
        let attributedText = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: fontChoice.uiFont(17, relativeTo: .body),
                .foregroundColor: UIColor(theme.textColor),
                .paragraphStyle: paragraphStyle
            ]
        )

        for highlight in highlights {
            guard highlight.range.location >= 0,
                  NSMaxRange(highlight.range) <= attributedText.length else {
                continue
            }
            attributedText.addAttribute(
                .backgroundColor,
                value: UIColor(FolioPalette.annotationHighlight),
                range: highlight.range
            )
        }
        return attributedText
    }
}
