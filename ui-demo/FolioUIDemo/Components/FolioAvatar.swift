import SwiftUI

struct FolioAvatar: View {
    let size: Double

    var body: some View {
        Image(.profileAvatar)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(.circle)
            .accessibilityLabel("Folio 用户头像")
    }
}
