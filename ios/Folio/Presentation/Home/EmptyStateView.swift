import SwiftUI

struct EmptyStateView: View {
    let onPasteURL: ((URL) -> Void)?

    @State private var clipboardURL: URL?
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

            // Clipboard shortcut — subtle, inline
            if let url = clipboardURL {
                Button {
                    onPasteURL?(url)
                    withAnimation { clipboardURL = nil }
                } label: {
                    Text(String(localized: "empty.pasteClipboard", defaultValue: "Add copied link"))
                        .font(Typography.cardMeta)
                        .foregroundStyle(Color.folio.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, Spacing.xs)
                .transition(.opacity)
            }

            Spacer()
        }
        .padding(Spacing.screenPadding)
        .offset(y: appeared ? 0 : 8)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            checkClipboard()
            withAnimation(Motion.resolved(Motion.settle, reduceMotion: reduceMotion) ?? .default) {
                appeared = true
            }
        }
    }

    private func checkClipboard() {
        if let url = UIPasteboard.general.url {
            clipboardURL = url
        } else if let string = UIPasteboard.general.string,
                  let url = URL(string: string), url.scheme?.hasPrefix("http") == true {
            clipboardURL = url
        }
    }
}

#Preview {
    EmptyStateView(onPasteURL: nil)
}
