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
                    .fill(FolioPaperPalette.controlSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(FolioPaperPalette.controlHighlight)
                    }
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.72), lineWidth: 1)
                            .blur(radius: 0.2)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(FolioPaperPalette.controlStroke, lineWidth: 1)
                    }
                    .shadow(color: FolioPaperPalette.shadowTint.opacity(0.16), radius: 18, x: 0, y: 9)
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
                .font(.system(size: 22, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(FolioPaperPalette.secondaryText)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .background {
            Circle()
                .fill(FolioPaperPalette.controlSurface)
                .overlay {
                    Circle()
                        .fill(FolioPaperPalette.controlHighlight)
                }
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.70), lineWidth: 1)
                }
                .overlay {
                    Circle()
                        .stroke(FolioPaperPalette.controlStroke, lineWidth: 1)
                }
                .shadow(color: FolioPaperPalette.shadowTint.opacity(0.14), radius: 14, x: 0, y: 8)
                .shadow(color: Color.white.opacity(0.8), radius: 1, x: 0, y: -1)
        }
    }
}

enum FolioPaperPalette {
    static let background = Color(red: 0.976, green: 0.988, blue: 0.965)
    static let paper = Color(red: 0.998, green: 0.996, blue: 0.984)
    static let ink = Color(red: 0.105, green: 0.135, blue: 0.122)
    static let secondaryInk = Color(red: 0.345, green: 0.402, blue: 0.365)
    static let primaryText = ink
    static let secondaryText = Color(red: 0.318, green: 0.380, blue: 0.345)
    static let tertiaryText = Color(red: 0.475, green: 0.535, blue: 0.495)
    static let quaternaryText = Color(red: 0.490, green: 0.560, blue: 0.520)
    static let cardSurface = Color(red: 0.998, green: 0.998, blue: 0.988)
    static let iconSurface = Color(red: 0.925, green: 0.965, blue: 0.940)
    static let accentSurface = Color(red: 0.920, green: 0.968, blue: 0.995)
    static let controlSurface = Color(red: 0.920, green: 0.958, blue: 0.936)
    static let controlHighlight = Color.white.opacity(0.54)
    static let controlStroke = Color(red: 0.760, green: 0.865, blue: 0.820).opacity(0.72)
    static let searchField = Color(red: 0.930, green: 0.964, blue: 0.946)
    static let listDivider = Color(red: 0.690, green: 0.785, blue: 0.735).opacity(0.58)
    static let tabInactive = Color(red: 0.420, green: 0.482, blue: 0.445)
    static let faintLine = Color(red: 0.690, green: 0.785, blue: 0.735).opacity(0.52)
    static let accentBlue = Color(red: 0.100, green: 0.520, blue: 0.875)
    static let freshMint = Color(red: 0.235, green: 0.675, blue: 0.560)
    static let shadowTint = Color(red: 0.250, green: 0.430, blue: 0.380)
}
