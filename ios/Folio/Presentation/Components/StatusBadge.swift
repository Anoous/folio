import SwiftUI

enum ContentStatus {
    case unread
    case processing
    case failed
    case offline
    case pendingSync
    case clientReady
}

struct StatusBadge: View {
    let status: ContentStatus

    var body: some View {
        switch status {
        case .unread:
            Circle()
                .fill(Color.folio.unread)
                .frame(width: 8, height: 8)
                .accessibilityLabel(Text(String(localized: "status.unread", defaultValue: "Unread")))
        case .processing:
            Image(systemName: "hourglass")
                .font(.caption2)
                .foregroundStyle(Color.folio.warning)
                .symbolEffect(.pulse, options: .repeating)
                .accessibilityLabel(Text(String(localized: "status.processing", defaultValue: "Processing")))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(Color.folio.error)
                .accessibilityLabel(Text(String(localized: "status.failed", defaultValue: "Failed")))
        case .offline:
            Image(systemName: "icloud.slash")
                .font(.caption2)
                .foregroundStyle(Color.folio.textTertiary)
                .accessibilityLabel(Text(String(localized: "status.offline", defaultValue: "Offline")))
        case .pendingSync:
            Image(systemName: "arrow.up.icloud")
                .font(.caption2)
                .foregroundStyle(Color.folio.textTertiary)
                .accessibilityLabel(Text(String(localized: "status.pendingSync", defaultValue: "Pending sync")))
        case .clientReady:
            Image(systemName: "doc.richtext")
                .font(.caption2)
                .foregroundStyle(Color.folio.success)
                .accessibilityLabel(Text(String(localized: "status.clientReady", defaultValue: "Content ready")))
        }
    }

    /// User-facing description of the status
    var statusText: String {
        switch status {
        case .unread: return String(localized: "status.unread", defaultValue: "Unread")
        case .processing: return String(localized: "status.processingText", defaultValue: "AI is analyzing...")
        case .failed: return String(localized: "status.failedText", defaultValue: "Processing failed")
        case .offline: return String(localized: "status.offlineText", defaultValue: "Saved offline")
        case .pendingSync: return String(localized: "status.pendingSyncText", defaultValue: "Waiting to sync")
        case .clientReady: return String(localized: "status.clientReadyText", defaultValue: "Content ready, AI analyzing...")
        }
    }
}

#Preview {
    HStack(spacing: Spacing.md) {
        StatusBadge(status: .unread)
        StatusBadge(status: .processing)
        StatusBadge(status: .failed)
        StatusBadge(status: .offline)
        StatusBadge(status: .clientReady)
    }
    .padding()
}
