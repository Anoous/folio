import SwiftUI

struct KnowledgeSparkView: View {
    let insights: [SparkInsightDTO]
    let onFollowup: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Spark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.folio.textTertiary)
                    .tracking(0.5)

                ForEach(insights) { insight in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(insight.insight)
                            .font(Font.custom("LXGWWenKaiTC-Regular", size: 17))
                            .foregroundStyle(Color.folio.textPrimary)
                            .lineSpacing(6)

                        Text(insight.whyItMatters)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.folio.textSecondary)
                            .lineSpacing(4)

                        Button(action: { onFollowup(insight.followupQuestion) }) {
                            Text("→ \(insight.followupQuestion)")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.folio.accent)
                                .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
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
