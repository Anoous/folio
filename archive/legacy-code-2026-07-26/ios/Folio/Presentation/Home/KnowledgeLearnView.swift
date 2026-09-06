import SwiftUI

struct KnowledgeLearnView: View {
    let summary: String
    let items: [LearnItemDTO]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Learn")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.folio.textTertiary)
                    .tracking(0.5)

                Text(summary)
                    .font(Font.custom("LXGWWenKaiTC-Regular", size: 17))
                    .foregroundStyle(Color.folio.textPrimary)
                    .lineSpacing(6)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.folio.echoBg)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.type.uppercased())
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.folio.accent)
                            .tracking(1)

                        Text(item.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.folio.textPrimary)

                        Text(item.content)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.folio.textSecondary)
                            .lineSpacing(4)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.folio.echoBg)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
    }
}
