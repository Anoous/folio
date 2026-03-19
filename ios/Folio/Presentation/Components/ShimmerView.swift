import SwiftUI

/// Skeleton placeholder for article cards while content is loading.
/// Displays static gray blocks with a slow breathing opacity animation.
struct ShimmerView: View {
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            VStack(alignment: .leading, spacing: Spacing.xs) {
                // Title placeholder — 70% of card width
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.folio.separator)
                    .frame(width: w * 0.7, height: 14)

                // Summary placeholder — 90% of card width
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.folio.separator)
                    .frame(width: w * 0.9, height: 12)

                // Meta placeholder — 40% of card width
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.folio.separator)
                    .frame(width: w * 0.4, height: 10)
            }
        }
        .frame(height: 50)
        .opacity(isAnimating ? 0.7 : 0.4)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
            value: isAnimating
        )
        .onAppear { isAnimating = true }
        .padding(.vertical, Spacing.sm)
    }
}
