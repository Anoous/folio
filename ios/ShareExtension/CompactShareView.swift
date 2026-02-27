import SwiftUI

enum ShareState {
    case saving
    case saved
    case duplicate
    case offline
    case quotaExceeded
    case quotaWarning(remaining: Int)
    case extracting
    case extracted
}

struct CompactShareView: View {
    @Environment(\.openURL) private var openURL
    let state: ShareState
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: Spacing.md) {
            switch state {
            case .saving:
                ProgressView()
                Text(String(localized: "share.saving", defaultValue: "Adding..."))
                    .font(Typography.listTitle)

            case .saved:
                statusIcon("checkmark.circle.fill", color: Color.folio.success)
                Text(String(localized: "share.saved", defaultValue: "Added to Folio"))
                    .font(Typography.listTitle)
                Text(String(localized: "share.savedSubtitle", defaultValue: "AI will organize it in the background"))
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textSecondary)
                openFolioButton

            case .duplicate:
                statusIcon("pin.fill", color: Color.folio.warning)
                Text(String(localized: "share.duplicate", defaultValue: "Already saved"))
                    .font(Typography.listTitle)

            case .offline:
                statusIcon("wifi.slash", color: Color.folio.textSecondary)
                Text(String(localized: "share.offline", defaultValue: "Added to Folio"))
                    .font(Typography.listTitle)
                Text(String(localized: "share.offlineSubtitle", defaultValue: "Content will be fetched when online"))
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textSecondary)

            case .quotaExceeded:
                statusIcon("exclamationmark.triangle.fill", color: Color.folio.error)
                Text(String(localized: "share.quotaExceeded", defaultValue: "Monthly limit reached"))
                    .font(Typography.listTitle)
                Text(String(localized: "share.quotaExceededSubtitle", defaultValue: "Upgrade to Pro for unlimited saves"))
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textSecondary)

            case .quotaWarning(let remaining):
                statusIcon("checkmark.circle.fill", color: Color.folio.success)
                Text(String(localized: "share.saved", defaultValue: "Added to Folio"))
                    .font(Typography.listTitle)
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.folio.warning)
                    Text("\(remaining) " + String(localized: "share.quotaWarning", defaultValue: "saves remaining this month"))
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.warning)
                }

            case .extracting:
                ProgressView()
                Text(String(localized: "share.extracting", defaultValue: "Extracting article..."))
                    .font(Typography.listTitle)
                Text(String(localized: "share.extractingSubtitle", defaultValue: "Getting content ready for reading"))
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textSecondary)

            case .extracted:
                statusIcon("doc.richtext", color: Color.folio.success)
                Text(String(localized: "share.extracted", defaultValue: "Article ready"))
                    .font(Typography.listTitle)
                openFolioButton
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
    }

    private func statusIcon(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 44))
            .foregroundStyle(color)
    }

    private var openFolioButton: some View {
        Button {
            if let url = URL(string: "folio://library") {
                openURL(url)
            }
            onDismiss()
        } label: {
            Text(String(localized: "share.openApp", defaultValue: "Open Folio"))
                .font(Typography.caption)
                .foregroundStyle(Color.folio.accent)
        }
    }
}
