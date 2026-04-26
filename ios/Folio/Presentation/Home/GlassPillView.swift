import SwiftUI

struct GlassPillView<Content: View>: View {
    let cornerRadius: CGFloat
    let content: Content

    init(cornerRadius: CGFloat = 28, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.26))
                    }
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.64), lineWidth: 1)
                            .blur(radius: 0.2)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.05), radius: 18, x: 0, y: 8)
                    .shadow(color: Color.white.opacity(0.72), radius: 1, x: 0, y: -1)
            }
    }
}

struct GlassCircleButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(FolioPaperPalette.ink)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .background {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle()
                        .fill(Color.white.opacity(0.30))
                }
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.70), lineWidth: 1)
                }
                .overlay {
                    Circle()
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 8)
                .shadow(color: Color.white.opacity(0.8), radius: 1, x: 0, y: -1)
        }
    }
}

enum FolioPaperPalette {
    static let background = Color(red: 0.980, green: 0.973, blue: 0.949)
    static let paper = Color(red: 0.992, green: 0.980, blue: 0.957)
    static let ink = Color(red: 0.110, green: 0.110, blue: 0.118)
    static let secondaryInk = Color(red: 0.435, green: 0.416, blue: 0.380)
    static let faintLine = Color.black.opacity(0.12)
    static let accentBlue = Color(red: 0.000, green: 0.478, blue: 1.000)
}
