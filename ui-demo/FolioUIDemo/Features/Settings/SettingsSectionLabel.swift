import SwiftUI

struct SettingsSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 14))
            .foregroundStyle(FolioPalette.secondaryText)
            .padding(.bottom, 9)
    }
}
