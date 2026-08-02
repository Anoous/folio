import SwiftUI

struct SettingsStorageCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: "icloud")
                    .font(.system(size: 23, weight: .regular))
                    .foregroundStyle(FolioPalette.inkGreenDeep)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("云端空间使用情况")
                            .font(FolioTypography.editorial(15, relativeTo: .body))
                        Spacer()
                        Text("620 MB")
                            .foregroundStyle(FolioPalette.inkGreenDeep)
                        Text("/ 1 GB")
                            .foregroundStyle(FolioPalette.secondaryText)
                    }
                    .font(.system(size: 13))

                    ProgressView(value: 0.62)
                        .tint(FolioPalette.inkGreenDeep)
                }

                Image(systemName: "chevron.right")
                    .foregroundStyle(FolioPalette.tertiaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 66)
            .background(FolioPalette.surface)
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(FolioPalette.paperLine, lineWidth: 0.8)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
