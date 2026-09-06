import SwiftUI

struct HomeSyncErrorBannerView: View {
    let message: String
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: "exclamationmark.icloud.fill")
                .foregroundStyle(Color.folio.error)

            Text(message)
                .font(Typography.caption)
                .foregroundStyle(Color.folio.error)
                .lineLimit(2)

            Spacer(minLength: Spacing.xs)

            Button("重试", action: onRetry)
                .font(Typography.caption)
                .foregroundStyle(Color.folio.accent)
                .buttonStyle(.plain)

            Button("关闭", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .font(Typography.caption)
                .foregroundStyle(Color.folio.textTertiary)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.xs)
    }
}
