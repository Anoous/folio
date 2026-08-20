import SwiftUI

struct SettingsHeaderView: View {
    let onBack: () -> Void

    var body: some View {
        HStack {
            FolioBackButton(action: onBack)
            Spacer()
            Text("设置")
                .font(FolioTypography.editorialBold(24, relativeTo: .title2))
                .foregroundStyle(FolioPalette.inkGreenDeep)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.top, 13)
    }
}
