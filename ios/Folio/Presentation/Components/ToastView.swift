import SwiftUI

struct ToastView: View {
    let message: String
    var icon: String?

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(Color.folio.textPrimary)
            }
            Text(message)
                .font(Typography.body)
                .foregroundStyle(Color.folio.textPrimary)
                .lineLimit(2)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    }
}

struct ToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    var icon: String?
    var duration: TimeInterval = 2.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isPresented {
                    ToastView(message: message, icon: icon)
                        .padding(.horizontal, Spacing.md)
                        .padding(.bottom, Spacing.xs)
                        .transition(
                            .asymmetric(
                                insertion: .opacity
                                    .combined(with: .offset(y: 8))
                                    .combined(with: .scale(scale: 0.96)),
                                removal: .opacity
                                    .combined(with: .offset(y: 4))
                            )
                        )
                        .onTapGesture { dismiss() }
                        .task {
                            try? await Task.sleep(for: .seconds(duration))
                            dismiss()
                        }
                }
            }
            .animation(
                isPresented
                    ? Motion.resolved(Motion.settle, reduceMotion: reduceMotion) ?? .default
                    : Motion.resolved(Motion.exit, reduceMotion: reduceMotion) ?? .default,
                value: isPresented
            )
    }

    private func dismiss() {
        guard isPresented else { return }
        isPresented = false
    }
}

extension View {
    func toast(isPresented: Binding<Bool>, message: String, icon: String? = nil, duration: TimeInterval = 2.5) -> some View {
        modifier(ToastModifier(isPresented: isPresented, message: message, icon: icon, duration: duration))
    }
}

#Preview {
    ToastView(message: "Article saved!", icon: "checkmark.circle.fill")
        .padding()
}
