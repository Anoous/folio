import SwiftUI

struct ReaderContentView: View {
    let article: DemoArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(article.readerTitle)
                .font(FolioTypography.editorialBold(28, relativeTo: .title))
                .foregroundStyle(FolioPalette.inkGreenDeep)
                .lineSpacing(8)
                .padding(.top, FolioMetrics.articleContentTopSpacing)

            ForEach(Array(article.originalParagraphs.enumerated()), id: \.offset) { index, paragraph in
                ReaderParagraph(text: paragraph)
                    .padding(.top, index == 0 ? 25 : 26)

                if index == 1 {
                    Text(article.pullQuote)
                        .font(FolioTypography.editorial(18, relativeTo: .body))
                        .lineSpacing(9)
                        .padding(20)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(Color(.sRGB, red: 0.67, green: 0.43, blue: 0.12))
                                .frame(width: 2)
                        }
                        .background(FolioPalette.evidence.opacity(0.58))
                        .clipShape(.rect(cornerRadius: 12))
                        .padding(.top, 25)
                }
            }
            .padding(.bottom, 30)
        }
    }
}

#Preview {
    ScrollView {
        ReaderContentView(article: DemoContent.primaryArticle)
            .padding(.horizontal, FolioMetrics.readingInset)
    }
    .background(FolioPalette.canvas)
}
