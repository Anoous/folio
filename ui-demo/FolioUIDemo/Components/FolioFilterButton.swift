import SwiftUI

struct FolioFilterButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FolioFunnelShape()
                .stroke(FolioPalette.inkGreen, style: StrokeStyle(lineWidth: 1.35, lineJoin: .round))
                .frame(width: 22, height: 22)
                .frame(width: 48, height: 48)
                .background(FolioPalette.surface.opacity(0.85))
                .clipShape(.circle)
                .overlay {
                    Circle()
                        .stroke(FolioPalette.inkGreen, lineWidth: 1)
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("筛选")
    }
}

private struct FolioFunnelShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.minY + rect.height * 0.2))
            path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.14, y: rect.minY + rect.height * 0.2))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.58, y: rect.minY + rect.height * 0.54))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.58, y: rect.maxY - rect.height * 0.16))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.maxY - rect.height * 0.27))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.54))
            path.closeSubpath()
        }
    }
}
