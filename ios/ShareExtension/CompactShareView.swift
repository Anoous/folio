import SwiftUI

enum ShareState {
    case saving
    case saved
    case duplicate
    case offline
    case quotaExceeded
    case quotaWarning(remaining: Int)
}

struct CompactShareView: View {
    @Environment(\.openURL) private var openURL
    let state: ShareState
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            switch state {
            case .saving:
                ProgressView()
                Text(String(localized: "share.saving", defaultValue: "Adding..."))
                    .font(.headline)

            case .saved:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.green)
                Text(String(localized: "share.saved", defaultValue: "Added to Folio"))
                    .font(.headline)
                Text(String(localized: "share.savedSubtitle", defaultValue: "AI will organize it in the background"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    if let url = URL(string: "folio://library") {
                        openURL(url)
                    }
                    onDismiss()
                } label: {
                    Text(String(localized: "share.openApp", defaultValue: "Open Folio"))
                        .font(.caption)
                        .foregroundStyle(.blue)
                }

            case .duplicate:
                Image(systemName: "pin.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
                Text(String(localized: "share.duplicate", defaultValue: "Already saved"))
                    .font(.headline)

            case .offline:
                Image(systemName: "wifi.slash")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text(String(localized: "share.offline", defaultValue: "Added to Folio"))
                    .font(.headline)
                Text(String(localized: "share.offlineSubtitle", defaultValue: "Content will be fetched when online"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .quotaExceeded:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.red)
                Text(String(localized: "share.quotaExceeded", defaultValue: "Monthly limit reached"))
                    .font(.headline)
                Text(String(localized: "share.quotaExceededSubtitle", defaultValue: "Upgrade to Pro for unlimited saves"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .quotaWarning(let remaining):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.green)
                Text(String(localized: "share.saved", defaultValue: "Added to Folio"))
                    .font(.headline)
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text("\(remaining) " + String(localized: "share.quotaWarning", defaultValue: "saves remaining this month"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}
