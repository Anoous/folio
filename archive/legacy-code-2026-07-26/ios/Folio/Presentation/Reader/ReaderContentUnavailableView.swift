import SwiftUI

struct ReaderContentUnavailableView: View {
    let article: Article
    let error: String?
    let onRetry: () -> Void
    let onOpenOriginal: () -> Void

    var body: some View {
        VStack(spacing: Spacing.md) {
            stateContent

            if article.url != nil {
                FolioButton(
                    title: String(localized: "reader.openOriginal", defaultValue: "Open Original"),
                    style: .secondary,
                    action: onOpenOriginal
                )
                .frame(width: 200)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }

    @ViewBuilder
    private var stateContent: some View {
        if let error {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 40))
                .foregroundStyle(Color.folio.error)

            Text(String(localized: "reader.loadFailed", defaultValue: "Failed to load content"))
                .font(Typography.body)
                .foregroundStyle(Color.folio.textPrimary)

            Text(error)
                .font(Typography.caption)
                .foregroundStyle(Color.folio.textTertiary)
                .multilineTextAlignment(.center)

            FolioButton(
                title: String(localized: "reader.retryLoad", defaultValue: "Retry"),
                style: .primary,
                action: onRetry
            )
            .frame(width: 200)
        } else if article.status == .processing {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(Color.folio.warning)

            Text(String(localized: "reader.stillProcessing", defaultValue: "AI is still analyzing this article"))
                .font(Typography.body)
                .foregroundStyle(Color.folio.textSecondary)

            Text(String(localized: "reader.checkBackSoon", defaultValue: "Check back in a moment"))
                .font(Typography.caption)
                .foregroundStyle(Color.folio.textTertiary)
        } else if article.status == .failed {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.folio.error)

            Text(String(localized: "reader.processingFailed", defaultValue: "Processing failed"))
                .font(Typography.body)
                .foregroundStyle(Color.folio.textPrimary)

            if let fetchError = article.fetchError {
                Text(fetchError)
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textTertiary)
                    .multilineTextAlignment(.center)
            }
        } else {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(Color.folio.textTertiary)

            Text(String(localized: "reader.noContent", defaultValue: "Content not yet available"))
                .font(Typography.body)
                .foregroundStyle(Color.folio.textSecondary)
        }
    }
}
