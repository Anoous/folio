import SwiftUI

struct ReaderParagraph: View {
    let text: String

    var body: some View {
        Text(text)
            .font(FolioTypography.editorial(17, relativeTo: .body))
            .foregroundStyle(.primary)
            .lineSpacing(8)
            .fixedSize(horizontal: false, vertical: true)
    }
}
