import SwiftUI

struct InsightFeedbackButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FolioTypography.editorial(15, relativeTo: .subheadline))
            .foregroundStyle(isSelected ? .white : FolioPalette.inkGreenDeep)
            .padding(.horizontal, 14)
            .frame(minHeight: 42)
            .background(isSelected ? FolioPalette.inkGreenDeep : FolioPalette.surface)
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(FolioPalette.inkGreenDeep, lineWidth: 0.8)
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
