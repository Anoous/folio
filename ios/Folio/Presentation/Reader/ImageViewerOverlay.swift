import SwiftUI
import NukeUI

/// Full-screen image viewer with pinch-to-zoom, double-tap zoom, and
/// drag-to-dismiss support.
struct ImageViewerOverlay: View {
    let url: URL
    let altText: String

    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0
    private let doubleTapScale: CGFloat = 2.5
    private let dismissThreshold: CGFloat = 150

    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()
                .opacity(backgroundOpacity)

            // Image
            LazyImage(url: url) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if state.error != nil {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("Failed to load image")
                            .font(Typography.body)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .scaleEffect(scale)
            .offset(x: offset.width + dragOffset.width,
                    y: offset.height + dragOffset.height)
            .gesture(combinedGesture)
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    if scale > minScale {
                        scale = minScale
                        offset = .zero
                        lastScale = minScale
                        lastOffset = .zero
                    } else {
                        scale = doubleTapScale
                        lastScale = doubleTapScale
                    }
                }
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(Spacing.md)
                    }
                }
                Spacer()

                // Alt text at bottom
                if !altText.isEmpty {
                    Text(altText)
                        .font(Typography.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.xs)
                        .background(.black.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                        .padding(.bottom, Spacing.lg)
                }
            }
        }
        .statusBarHidden()
    }

    // MARK: - Gestures

    private var combinedGesture: some Gesture {
        SimultaneousGesture(pinchGesture, panGesture)
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = lastScale * value.magnification
                scale = min(max(newScale, minScale), maxScale)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= minScale {
                    withAnimation(.easeOut(duration: 0.2)) {
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if scale <= minScale {
                    // Drag to dismiss when not zoomed
                    dragOffset = value.translation
                } else {
                    // Pan when zoomed
                    offset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                }
            }
            .onEnded { value in
                if scale <= minScale {
                    if abs(dragOffset.height) > dismissThreshold {
                        dismiss()
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) {
                            dragOffset = .zero
                        }
                    }
                } else {
                    lastOffset = offset
                }
            }
    }

    // MARK: - Computed

    private var backgroundOpacity: Double {
        if scale <= minScale {
            let progress = abs(dragOffset.height) / dismissThreshold
            return max(1.0 - Double(progress) * 0.5, 0.3)
        }
        return 1.0
    }
}

#Preview {
    ImageViewerOverlay(
        url: URL(string: "https://picsum.photos/1200/800")!,
        altText: "Sample preview image"
    )
}
