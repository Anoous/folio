import SwiftUI

enum ShareState {
    case saved(domain: String)
    case duplicate(domain: String)
    case quotaExceeded
    case error
    case processing
}

struct CompactShareView: View {
    let state: ShareState
    @State private var saveCompleted = false

    var body: some View {
        VStack(spacing: Spacing.sm) {
            switch state {
            case .saved(let domain):
                statusIcon("checkmark.circle.fill", color: Color.folio.success)
                domainLabel(domain)

            case .duplicate(let domain):
                statusIcon("pin.fill", color: Color.folio.warning)
                Text(String(localized: "share.duplicate", defaultValue: "Already saved"))
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textSecondary)
                domainLabel(domain)

            case .quotaExceeded:
                statusIcon("exclamationmark.triangle.fill", color: Color.folio.warning)
                Text(String(localized: "share.quotaExceeded", defaultValue: "Monthly limit reached"))
                    .font(Typography.listTitle)
                    .foregroundStyle(Color.folio.textSecondary)

            case .error:
                statusIcon("xmark.circle.fill", color: Color.folio.error)
                Text(String(localized: "share.error", defaultValue: "Save failed"))
                    .font(Typography.listTitle)

            case .processing:
                ProgressView()
                    .controlSize(.large)
                Text(String(localized: "share.processing", defaultValue: "正在识别..."))
                    .font(Typography.listTitle)
                    .foregroundStyle(Color.folio.textSecondary)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.success, trigger: saveCompleted)
        .onAppear {
            if case .saved = state {
                saveCompleted = true
            }
        }
    }

    private func statusIcon(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 44))
            .foregroundStyle(color)
    }

    private func domainLabel(_ domain: String) -> some View {
        Text(domain)
            .font(Typography.caption)
            .foregroundStyle(Color.folio.textTertiary)
    }
}
