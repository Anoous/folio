import SwiftUI

struct FolioBackButton: View {
    let action: () -> Void

    var body: some View {
        Button("返回", systemImage: "chevron.left", action: action)
            .labelStyle(.iconOnly)
            .font(.system(size: 23, weight: .regular))
            .foregroundStyle(FolioPalette.inkGreenDeep)
            .frame(width: 44, height: 44)
    }
}
