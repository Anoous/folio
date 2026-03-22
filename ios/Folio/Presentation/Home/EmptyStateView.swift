import SwiftUI

struct EmptyStateView: View {
    let onPasteURL: ((URL) -> Void)?

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Spacer()

            Text(String(localized: "empty.title", defaultValue: "Your collection\nis empty"))
                .font(Typography.emptyHeadline)
                .foregroundStyle(Color.folio.textSecondary)
                .multilineTextAlignment(.center)

            Text(String(localized: "empty.subtitle", defaultValue: "Share a link from any app"))
                .font(Typography.cardSummary)
                .foregroundStyle(Color.folio.textTertiary)

            // System paste button — no permission dialog, user-initiated
            PasteButton(payloadType: String.self) { strings in
                guard let string = strings.first else { return }
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true {
                    onPasteURL?(url)
                }
            }
            .labelStyle(.titleOnly)
            .tint(Color.folio.accent)
            .padding(.top, Spacing.xs)

            Spacer()
        }
        .padding(Spacing.screenPadding)
        .offset(y: appeared ? 0 : 8)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(Motion.resolved(Motion.settle, reduceMotion: reduceMotion) ?? .default) {
                appeared = true
            }
        }
    }
}

#Preview {
    EmptyStateView(onPasteURL: nil)
}
