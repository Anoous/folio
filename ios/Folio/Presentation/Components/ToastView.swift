import SwiftUI

struct ToastView: View {
    let message: String
    let icon: String?

    init(message: String, icon: String? = nil) {
        self.message = message
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(Typography.caption)
            }
            Text(message)
                .font(Typography.caption)
        }
        .foregroundStyle(Color.folio.cardBackground)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.folio.accent.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
    }
}

struct ToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    let icon: String?
    let duration: TimeInterval

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isPresented {
                    ToastView(message: message, icon: icon)
                        .padding(.top, Spacing.lg)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    isPresented = false
                                }
                            }
                        }
                }
            }
            .animation(.easeIn(duration: 0.3), value: isPresented)
    }
}

extension View {
    func toast(isPresented: Binding<Bool>, message: String, icon: String? = nil, duration: TimeInterval = 2.0) -> some View {
        modifier(ToastModifier(isPresented: isPresented, message: message, icon: icon, duration: duration))
    }
}

#Preview {
    ToastView(message: "Article saved!", icon: "checkmark.circle.fill")
        .padding()
}
