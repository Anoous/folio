import SwiftUI

struct DeviceSessionRow: View {
    let session: DemoDeviceSession
    let onRevoke: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: session.symbol)
                .font(.title3)
                .foregroundStyle(FolioPalette.inkGreenDeep)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.name)
                        .font(.body.weight(.medium))

                    if session.isCurrent {
                        Text("当前")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(FolioPalette.inkGreenDeep)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(FolioPalette.subtleGreen, in: .capsule)
                    }
                }

                Text(session.detail)
                    .font(.caption)
                    .foregroundStyle(FolioPalette.secondaryText)
            }

            Spacer()

            if !session.isCurrent {
                Button("撤销", action: onRevoke)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FolioPalette.danger)
                    .frame(minHeight: FolioMetrics.minimumTapTarget)
                    .accessibilityIdentifier("device-revoke-\(session.id)")
            }
        }
        .frame(minHeight: 70)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FolioPalette.paperLine)
                .frame(height: 0.5)
        }
    }
}
