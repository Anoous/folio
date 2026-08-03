import SwiftUI

struct ReaderParagraph: View {
    let text: String
    let fontChoice: ReaderFontChoice
    let theme: ReaderTheme

    var body: some View {
        Text(text)
            .font(fontChoice.regularFont(17, relativeTo: .body))
            .foregroundStyle(theme.textColor)
            .lineSpacing(8)
            .fixedSize(horizontal: false, vertical: true)
    }
}
