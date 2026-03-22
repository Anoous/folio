import SwiftUI

struct EmptyStateView: View {
    let onPasteURL: ((URL) -> Void)?

    @State private var appeared = false
    @State private var isPasteButtonPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Mark "F"
            Text("F")
                .font(Font.custom("LXGWWenKaiTC-Light", size: 64))
                .fontWeight(.light)
                .foregroundStyle(Color.folio.textQuaternary)
                .opacity(0.3)
                .lineSpacing(0)
                .padding(.bottom, 40)

            // Headline — LXGWWenKaiTC-Regular 22pt, lineHeight 1.45
            Text("你读过的，\nFolio 都记得。")
                .font(Typography.v3EmptyHeadline)
                .foregroundStyle(Color.folio.textPrimary)
                .multilineTextAlignment(.center)
                .lineSpacing(22 * (1.45 - 1))
                .padding(.bottom, 12)

            // Description
            Text("从任何 App 分享一个链接。\nFolio 阅读它，理解它，\n然后帮你记住。")
                .font(.system(size: 15))
                .foregroundStyle(Color.folio.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(15 * (1.65 - 1))
                .padding(.bottom, 44)

            // Paste Button
            Button {
                handlePaste()
            } label: {
                Text("粘贴链接")
                    .font(.system(size: 15, weight: .medium))
                    .tracking(0.2)
                    .foregroundStyle(Color.folio.background)
                    .padding(.vertical, 13)
                    .padding(.horizontal, 32)
                    .background(Color.folio.textPrimary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .scaleEffect(isPasteButtonPressed ? 0.96 : 1.0)
            .opacity(isPasteButtonPressed ? 0.8 : 1.0)
            .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
                withAnimation(Motion.quick) {
                    isPasteButtonPressed = pressing
                }
            }, perform: {})
            .animation(Motion.quick, value: isPasteButtonPressed)

            // Subtext
            Text("或从 Safari、微信、Twitter 分享到 Folio")
                .font(.system(size: 12))
                .foregroundStyle(Color.folio.textQuaternary)
                .multilineTextAlignment(.center)
                .lineSpacing(12 * (1.6 - 1))
                .padding(.top, 20)
        }
        .padding(.top, 120)
        .padding(.horizontal, 52)
        .padding(.bottom, 60)
        .offset(y: appeared ? 0 : 8)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(Motion.resolved(Motion.settle, reduceMotion: reduceMotion) ?? .default) {
                appeared = true
            }
        }
    }

    private func handlePaste() {
        let string = UIPasteboard.general.string ?? ""
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true {
            onPasteURL?(url)
        }
    }
}

#Preview {
    ZStack {
        Color.folio.background.ignoresSafeArea()
        EmptyStateView(onPasteURL: nil)
    }
}
