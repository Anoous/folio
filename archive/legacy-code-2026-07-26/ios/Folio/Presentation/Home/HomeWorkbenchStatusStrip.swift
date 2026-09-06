import SwiftUI

struct HomeWorkbenchStatusStrip: View {
    let processingCount: Int
    let continueReadingCount: Int
    let askableCount: Int

    var body: some View {
        GlassPillView(cornerRadius: 18) {
            HStack(spacing: 0) {
                metric(
                    systemImage: "progress.indicator",
                    value: "\(processingCount) 篇处理中",
                    color: FolioPaperPalette.freshMint
                )

                divider

                metric(
                    systemImage: "book",
                    value: "\(continueReadingCount) 篇可继续阅读",
                    color: FolioPaperPalette.accentBlue
                )

                divider

                metric(
                    systemImage: "text.bubble",
                    value: "可向 \(askableCount) 篇资料提问",
                    color: FolioPaperPalette.freshMint
                )
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
        }
        .padding(.horizontal, 20)
    }

    private func metric(systemImage: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(color)
                .frame(width: 20)

            Text(value)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(FolioPaperPalette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Rectangle()
            .fill(FolioPaperPalette.controlStroke)
            .frame(width: 1, height: 34)
            .padding(.horizontal, 5)
    }
}
