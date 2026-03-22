import SwiftUI

/// A thin indeterminate progress bar (Safari-style) shown during background sync.
/// 2pt height, accent color, slides left-to-right continuously.
struct SyncProgressBar: View {
    @State private var offset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let barWidth = geometry.size.width * 0.3
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.folio.accent.opacity(0.6))
                .frame(width: barWidth, height: 2)
                .offset(x: offset * (geometry.size.width + barWidth) - barWidth)
        }
        .frame(height: 2)
        .clipped()
        .onAppear {
            if reduceMotion {
                offset = 0.5
            } else {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    offset = 1
                }
            }
        }
        .transition(.opacity)
    }
}
