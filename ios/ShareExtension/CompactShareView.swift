import SwiftUI

enum ShareState {
    case saving
    case saved
    case duplicate
    case offline
    case quotaExceeded
}

struct CompactShareView: View {
    let state: ShareState
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            switch state {
            case .saving:
                ProgressView()
                Text("Adding...")
                    .font(.headline)

            case .saved:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.green)
                Text("Added to Folio")
                    .font(.headline)
                Text("AI will organize it in the background")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .duplicate:
                Image(systemName: "pin.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
                Text("Already saved")
                    .font(.headline)

            case .offline:
                Image(systemName: "wifi.slash")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("Added to Folio")
                    .font(.headline)
                Text("Content will be fetched when online")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .quotaExceeded:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
                Text("Monthly limit reached")
                    .font(.headline)
                Text("Upgrade to Pro for unlimited saves")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}
