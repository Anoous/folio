import SwiftUI

struct VoiceRecordingView: View {
    let onSave: (String) -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.folio.textTertiary)
            Text("Voice Recording — Coming Soon")
                .font(Typography.body)
                .foregroundStyle(Color.folio.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.folio.background)
    }
}
