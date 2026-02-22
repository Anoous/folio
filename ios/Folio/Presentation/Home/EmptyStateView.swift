import SwiftUI

struct EmptyStateView: View {
    let onPasteURL: ((URL) -> Void)?

    @State private var clipboardURL: URL?
    @State private var appeared = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "book.closed")
                .font(.system(size: 56))
                .foregroundStyle(Color.folio.textTertiary)

            VStack(spacing: Spacing.xs) {
                Text(String(localized: "empty.title", defaultValue: "Your library is empty"))
                    .font(Typography.listTitle)
                    .foregroundStyle(Color.folio.textPrimary)

                Text(String(localized: "empty.subtitle", defaultValue: "Save your first article to get started"))
                    .font(Typography.body)
                    .foregroundStyle(Color.folio.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Step-by-step guide
            VStack(alignment: .leading, spacing: Spacing.sm) {
                stepRow(number: "1", text: String(localized: "empty.step1", defaultValue: "Open Safari or WeChat"))
                stepRow(number: "2", text: String(localized: "empty.step2", defaultValue: "Find a great article"))
                stepRow(number: "3", text: String(localized: "empty.step3", defaultValue: "Tap the Share button"))
                stepRow(number: "4", text: String(localized: "empty.step4", defaultValue: "Choose Folio"))
            }
            .padding(.horizontal, Spacing.lg)

            // Divider
            HStack {
                Rectangle()
                    .fill(Color.folio.separator)
                    .frame(height: 1)
                Text(String(localized: "empty.or", defaultValue: "or"))
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textTertiary)
                Rectangle()
                    .fill(Color.folio.separator)
                    .frame(height: 1)
            }
            .padding(.horizontal, Spacing.xl)

            // Paste button
            if let url = clipboardURL {
                FolioButton(title: String(localized: "empty.paste", defaultValue: "Paste link to try"), style: .primary) {
                    onPasteURL?(url)
                }
                .padding(.horizontal, Spacing.xl)
            } else {
                Text(String(localized: "empty.addHint", defaultValue: "Tap + to add a link manually"))
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textTertiary)
            }
        }
        .padding(Spacing.screenPadding)
        .offset(y: appeared ? 0 : 8)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            checkClipboard()
            withAnimation(.easeOut(duration: 0.3)) {
                appeared = true
            }
        }
    }

    private func stepRow(number: String, text: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(number)
                .font(Typography.tag)
                .foregroundStyle(Color.folio.cardBackground)
                .frame(width: 24, height: 24)
                .background(Color.folio.accent)
                .clipShape(Circle())
            Text(text)
                .font(Typography.body)
                .foregroundStyle(Color.folio.textSecondary)
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
