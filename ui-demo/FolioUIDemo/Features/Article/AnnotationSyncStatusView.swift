import SwiftUI

struct AnnotationSyncStatusView: View {
    let state: DemoAnnotationSyncState

    var body: some View {
        HStack(spacing: 10) {
            if state == .syncing {
                ProgressView()
                    .controlSize(.small)
                    .tint(FolioPalette.inkGreen)
            } else {
                Image(systemName: "checkmark.icloud")
                    .foregroundStyle(FolioPalette.inkGreen)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(state == .syncing ? .annotationSyncing : .annotationSynced)
                    .font(.subheadline.bold())
                    .foregroundStyle(FolioPalette.inkGreenDeep)

                Text(.annotationSyncDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(FolioPalette.subtleGreen, in: .rect(cornerRadius: FolioMetrics.controlRadius))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("annotation-sync-status")
    }
}
