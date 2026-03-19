import SwiftUI

/// A thin progress line shown below the navigation bar in the reader.
struct ReadingProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.folio.accent.opacity(progress >= 1.0 ? 0.5 : 0.3))
                .frame(width: geometry.size.width * min(max(progress, 0), 1.0))
                .animation(Motion.quick, value: progress)
        }
        .frame(height: 1.5)
    }
}
