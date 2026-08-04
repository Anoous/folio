import SwiftUI

struct FolioGlassLens<Shape: InsettableShape>: View {
    let shape: Shape
    let tint: Color
    var isProminent = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        shape
            .fill(fillGradient)
            .overlay {
                shape
                    .strokeBorder(edgeGradient, lineWidth: isProminent ? 1.2 : 0.9)
            }
            .overlay {
                shape
                    .inset(by: isProminent ? 3.5 : 2.5)
                    .strokeBorder(innerHighlight, lineWidth: 0.75)
            }
            .shadow(
                color: reduceTransparency ? .clear : tint.opacity(isProminent ? 0.2 : 0.12),
                radius: isProminent ? 10 : 6,
                y: isProminent ? 3 : 2
            )
            .shadow(
                color: Color.black.opacity(reduceTransparency ? 0.04 : 0.08),
                radius: isProminent ? 5 : 3,
                y: 2
            )
            .accessibilityHidden(true)
    }

    private var fillGradient: LinearGradient {
        LinearGradient(
            colors: reduceTransparency
                ? [FolioPalette.surface, FolioPalette.surface]
                : [
                    Color.white.opacity(isProminent ? 0.46 : 0.36),
                    tint.opacity(isProminent ? 0.48 : 0.2),
                    tint.opacity(isProminent ? 0.32 : 0.12)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var edgeGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(reduceTransparency ? 0.65 : 0.92),
                tint.opacity(reduceTransparency ? 0.2 : 0.44),
                Color.white.opacity(reduceTransparency ? 0.38 : 0.68)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var innerHighlight: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(reduceTransparency ? 0.35 : 0.78),
                Color.white.opacity(0.05)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
