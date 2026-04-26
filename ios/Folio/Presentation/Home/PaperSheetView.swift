import SwiftUI

struct PaperSheetView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            paperBody
            content
        }
        .overlay(alignment: .leading) {
            BinderHoleColumn()
        }
        .overlay(alignment: .bottomTrailing) {
            PaperFoldView()
                .frame(width: 48, height: 48)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.045), radius: 2, x: 0, y: 1)
        .shadow(color: Color.black.opacity(0.105), radius: 18, x: 0, y: 14)
    }

    private var paperBody: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(FolioPaperPalette.paper)
            .overlay {
                PaperTextureView()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.72), lineWidth: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.045), lineWidth: 1)
            }
    }
}

private struct BinderHoleColumn: View {
    private let count = 8

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let spacing = max(1, (height - 40) / CGFloat(count - 1))

            ZStack(alignment: .topLeading) {
                ForEach(0..<count, id: \.self) { index in
                    Circle()
                        .fill(FolioPaperPalette.background)
                        .frame(width: 22, height: 22)
                        .overlay {
                            Circle()
                                .stroke(Color.black.opacity(0.035), lineWidth: 1)
                        }
                        .shadow(color: Color.black.opacity(0.045), radius: 1.5, x: 0.8, y: 0.8)
                        .position(x: 14, y: 20 + CGFloat(index) * spacing)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct PaperTextureView: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<210 {
                let x = pseudoRandom(index, salt: 17) * size.width
                let y = pseudoRandom(index, salt: 43) * size.height
                let radius = 0.35 + pseudoRandom(index, salt: 89) * 0.9
                let opacity = 0.010 + pseudoRandom(index, salt: 131) * 0.020
                let rect = CGRect(x: x, y: y, width: radius, height: radius)
                context.fill(Path(ellipseIn: rect), with: .color(Color.black.opacity(opacity)))
            }

            for index in 0..<70 {
                let y = pseudoRandom(index, salt: 211) * size.height
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y + pseudoRandom(index, salt: 233) * 1.6 - 0.8))
                context.stroke(path, with: .color(Color.white.opacity(0.035)), lineWidth: 0.5)
            }
        }
        .blendMode(.multiply)
        .opacity(0.9)
        .allowsHitTesting(false)
    }

    private func pseudoRandom(_ value: Int, salt: Int) -> CGFloat {
        let n = UInt64(value &* 1_103_515_245 &+ salt &* 12_345)
        let mixed = (n ^ (n >> 13) ^ (n << 7)) & 0xFFFF
        return CGFloat(mixed) / CGFloat(0xFFFF)
    }
}

private struct PaperFoldView: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            PaperFoldShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.92),
                            FolioPaperPalette.paper.opacity(0.55),
                            Color.black.opacity(0.06),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.black.opacity(0.08), radius: 5, x: -3, y: -3)

            PaperFoldShape()
                .stroke(Color.white.opacity(0.76), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

private struct PaperFoldShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY + 4))
        path.addCurve(
            to: CGPoint(x: rect.minX + 4, y: rect.maxY),
            control1: CGPoint(x: rect.maxX - 4, y: rect.midY + 4),
            control2: CGPoint(x: rect.midX + 3, y: rect.maxY - 2)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
