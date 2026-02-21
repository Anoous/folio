import SwiftUI

enum ContentStatus {
    case unread
    case processing
    case failed
    case offline
}

struct StatusBadge: View {
    let status: ContentStatus

    var body: some View {
        switch status {
        case .unread:
            Circle()
                .fill(Color.folio.unread)
                .frame(width: 8, height: 8)
        case .processing:
            Image(systemName: "hourglass")
                .font(.caption2)
                .foregroundStyle(Color.folio.warning)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(Color.folio.error)
        case .offline:
            Image(systemName: "icloud.slash")
                .font(.caption2)
                .foregroundStyle(Color.folio.textTertiary)
        }
    }
}

#Preview {
    HStack(spacing: Spacing.md) {
        StatusBadge(status: .unread)
        StatusBadge(status: .processing)
        StatusBadge(status: .failed)
        StatusBadge(status: .offline)
    }
    .padding()
}
