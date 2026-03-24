import SwiftUI

struct AudioWaveformView: View {
    let levels: [CGFloat] // 0.0 to 1.0 normalized RMS values

    private let barCount = 40
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2
    private let maxBarHeight: CGFloat = 40
    private let minBarHeight: CGFloat = 2

    var body: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(displayLevels.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(Color.folio.accent)
                    .frame(width: barWidth, height: barHeight(for: displayLevels[index]))
                    .animation(Motion.quick, value: displayLevels[index])
            }
        }
        .frame(height: maxBarHeight)
    }

    private var displayLevels: [CGFloat] {
        let padded = Array(repeating: CGFloat(0), count: max(0, barCount - levels.count)) + levels.suffix(barCount)
        return Array(padded.suffix(barCount))
    }

    private func barHeight(for level: CGFloat) -> CGFloat {
        let clamped = min(max(level, 0), 1)
        return minBarHeight + clamped * (maxBarHeight - minBarHeight)
    }
}
