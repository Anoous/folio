import SwiftUI

struct EvidenceSheetView: View {
    let evidence: DemoEvidence
    let onOpenOriginal: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var selectedDetent = PresentationDetent.fraction(0.62)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("证据 1")
                    .font(FolioTypography.editorialBold(28, relativeTo: .title))
                    .foregroundStyle(FolioPalette.inkGreenDeep)

                Spacer()

                Button("关闭", systemImage: "xmark", action: dismiss.callAsFunction)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(reduceTransparency ? FolioPalette.surface : .clear, in: .circle)
                    .buttonStyle(FolioPressButtonStyle())
                    .glassEffect(actionGlass, in: .circle)
            }

            Text("“")
                .font(FolioTypography.wordmark(49))
                .foregroundStyle(FolioPalette.inkGreenDeep)
                .frame(height: 40)
                .padding(.top, 23)

            Text(evidence.quote)
                .font(FolioTypography.editorial(22, relativeTo: .title3))
                .lineSpacing(12)
                .padding(.horizontal, 21)
                .padding(.bottom, 27)
                .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
                .background(FolioPalette.evidence.opacity(0.68))
                .clipShape(.rect(cornerRadius: 14))

            HStack(spacing: 16) {
                FolioBrandIcon(monogram: "e", size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(evidence.sourceTitle)
                        .font(FolioTypography.editorial(18, relativeTo: .headline))
                    Text(evidence.sourceMetadata)
                        .font(.system(size: 13))
                        .foregroundStyle(FolioPalette.tertiaryText)
                }
            }
            .padding(.top, 28)

            Button("在原文中查看", systemImage: "chevron.right", action: openOriginal)
                .font(FolioTypography.editorial(18, relativeTo: .headline))
                .foregroundStyle(FolioPalette.inkGreenDeep)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(reduceTransparency ? FolioPalette.surface : .clear, in: .rect(cornerRadius: 18))
                .buttonStyle(FolioPressButtonStyle())
                .glassEffect(actionGlass.tint(FolioPalette.subtleGreen), in: .rect(cornerRadius: 18))
                .padding(.top, 28)
        }
        .padding(.horizontal, FolioMetrics.pageInset)
        .padding(.top, 15)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(FolioPalette.canvas.opacity(reduceTransparency ? 1 : 0.84))
        .presentationDetents([.fraction(0.62), .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.resizes)
        .presentationBackground(.thinMaterial)
        .presentationCornerRadius(24)
        .sensoryFeedback(.selection, trigger: selectedDetent)
    }

    private func openOriginal() {
        dismiss()
        onOpenOriginal()
    }

    private var actionGlass: Glass {
        reduceTransparency ? .identity : .regular.interactive()
    }
}
