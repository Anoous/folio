import SwiftUI

enum FolioButtonStyle {
    case primary
    case secondary
}

struct FolioButton: View {
    let title: String
    let style: FolioButtonStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typography.body)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .padding(.horizontal, Spacing.md)
                .foregroundStyle(foregroundColor)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                .overlay {
                    if style == .secondary {
                        RoundedRectangle(cornerRadius: CornerRadius.medium)
                            .stroke(Color.folio.separator, lineWidth: 1)
                    }
                }
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: Color.folio.cardBackground
        case .secondary: Color.folio.textPrimary
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: Color.folio.accent
        case .secondary: Color.clear
        }
    }
}

#Preview {
    VStack(spacing: Spacing.md) {
        FolioButton(title: "Primary Button", style: .primary) {}
        FolioButton(title: "Secondary Button", style: .secondary) {}
    }
    .padding()
}
