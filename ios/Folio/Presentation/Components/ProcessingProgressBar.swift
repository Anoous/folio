import SwiftUI

/// A thin animated progress line shown at the bottom of processing article cards.
struct ProcessingProgressBar: View {
    var color: Color = Color.folio.accent.opacity(0.4)
    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 0.75)
                .fill(color)
                .frame(width: geometry.size.width * progress, height: 1.5)
        }
        .frame(height: 1.5)
        .onAppear {
            if reduceMotion {
                progress = 1.0
            } else {
                withAnimation(Motion.slow.repeatForever(autoreverses: true)) {
                    progress = 1.0
                }
            }
        }
    }
}
