import SwiftUI

struct ReaderFloatingChromeView<MoreMenu: View>: View {
    let title: String
    let textColor: Color
    let onDismiss: () -> Void
    let moreMenu: MoreMenu

    init(
        title: String,
        textColor: Color,
        onDismiss: @escaping () -> Void,
        @ViewBuilder moreMenu: () -> MoreMenu
    ) {
        self.title = title
        self.textColor = textColor
        self.onDismiss = onDismiss
        self.moreMenu = moreMenu()
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.folio.accent)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "button.back", defaultValue: "Back"))

            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            moreMenu
                .frame(width: 36, height: 36)
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, 8)
    }
}
