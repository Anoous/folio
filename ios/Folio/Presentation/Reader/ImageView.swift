import SwiftUI
import Nuke
import NukeUI

/// Async image view using Nuke/NukeUI for loading remote images.
/// Supports optional alt text and tap to open full-screen viewer.
struct ImageView: View {
    let urlString: String
    let altText: String

    @State private var showsFullScreen = false

    var body: some View {
        VStack(spacing: Spacing.xxs) {
            if let url = URL(string: urlString) {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, minHeight: 1)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel(altText.isEmpty
                                ? String(localized: "image.viewFull", defaultValue: "View full size")
                                : altText)
                            .onTapGesture {
                                showsFullScreen = true
                            }
                    } else if state.error != nil {
                        imagePlaceholder(icon: "exclamationmark.triangle", text: String(localized: "image.loadFailed", defaultValue: "Image failed to load"))
                    } else {
                        imagePlaceholder(icon: "photo", text: String(localized: "image.loading", defaultValue: "Loading..."))
                            .overlay {
                                ProgressView()
                            }
                    }
                }
                .fullScreenCover(isPresented: $showsFullScreen) {
                    ImageViewerOverlay(url: url, altText: altText)
                }
            } else {
                imagePlaceholder(icon: "photo.badge.exclamationmark", text: String(localized: "image.invalidURL", defaultValue: "Invalid image URL"))
            }

            // Alt text caption
            if !altText.isEmpty {
                Text(altText)
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private func imagePlaceholder(icon: String, text: String) -> some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(Color.folio.textTertiary)
            Text(text)
                .font(Typography.caption)
                .foregroundStyle(Color.folio.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(Color.folio.background)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }
}

#Preview {
    ScrollView {
        VStack(spacing: Spacing.md) {
            ImageView(urlString: "https://picsum.photos/800/400", altText: "Sample landscape image")
            ImageView(urlString: "", altText: "Broken URL")
        }
        .padding()
    }
}
