import SwiftUI
import UIKit

struct ReaderMediaContentView: View {
    let article: Article
    let onImageTap: (URL) -> Void

    @State private var screenshotImage: UIImage?

    private var hasText: Bool {
        article.markdownContent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if article.sourceType == .screenshot, let localPath = article.localImagePath {
                screenshotImageView(localPath: localPath)
            }

            if hasText, let markdownContent = article.markdownContent {
                Text(markdownContent)
                    .font(Typography.body)
                    .foregroundStyle(Color.folio.textPrimary)
                    .lineSpacing(17 * 0.65)
                    .padding(.horizontal, Spacing.screenPadding)
                    .textSelection(.enabled)
            } else if article.sourceType == .screenshot {
                emptyOCRState
            }
        }
        .task(id: article.localImagePath) {
            guard article.sourceType == .screenshot,
                  let localPath = article.localImagePath else { return }
            screenshotImage = await loadLocalImage(relativePath: localPath)
        }
    }

    @ViewBuilder
    private func screenshotImageView(localPath: String) -> some View {
        if let image = screenshotImage {
            let imageURL = screenshotImageURL(localPath)
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: hasText ? 300 : 400)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture {
                    if let imageURL {
                        onImageTap(imageURL)
                    }
                }
                .accessibilityLabel(hasText
                    ? String((article.markdownContent ?? "").prefix(200))
                    : String(localized: "reader.screenshot", defaultValue: "Screenshot"))
                .padding(.horizontal, Spacing.screenPadding)
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.folio.separator.opacity(0.3))
                .frame(height: 200)
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.folio.textQuaternary)
                }
                .padding(.horizontal, Spacing.screenPadding)
        }
    }

    private var emptyOCRState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(Color.folio.textQuaternary)
            Text(String(localized: "reader.noOCRText", defaultValue: "No text detected"))
                .font(Typography.caption)
                .foregroundStyle(Color.folio.textTertiary)
            Text(String(localized: "reader.tapToViewImage", defaultValue: "Tap image to view full size"))
                .font(Typography.caption)
                .foregroundStyle(Color.folio.textQuaternary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
        .accessibilityLabel(String(localized: "reader.noOCRText", defaultValue: "No text detected"))
    }

    private func screenshotImageURL(_ localPath: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier)?
            .appendingPathComponent(localPath)
    }

    private func loadLocalImage(relativePath: String) async -> UIImage? {
        await Task.detached {
            guard let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier
            ) else { return nil }
            let fileURL = containerURL.appendingPathComponent(relativePath)
            return UIImage(contentsOfFile: fileURL.path)
        }.value
    }
}
