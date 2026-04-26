import SwiftUI

struct HomeSectionHeaderView: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.folio.textPrimary)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.xs)
    }
}
