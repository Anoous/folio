import SwiftUI

struct HeroArticleCardView: View {
    @Environment(\.heroNamespace) private var heroNamespace

    let article: Article

    @State private var screenshotImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 0. Screenshot thumbnail (if applicable)
            if article.sourceType == .screenshot, let _ = article.localImagePath {
                if let image = screenshotImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel(String(localized: "home.screenshotPreview", defaultValue: "Screenshot preview"))
                        .padding(.bottom, 12)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.folio.separator.opacity(0.3))
                        .frame(height: 140)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 24))
                                .foregroundStyle(Color.folio.textQuaternary)
                        }
                        .padding(.bottom, 12)
                }
            }

            // 1. Title
            HStack(spacing: 6) {
                if article.sourceType == .voice {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.folio.textTertiary)
                }
                Text(article.displayTitle)
                    .font(Typography.v3HeroTitle)
                    .foregroundStyle(Color.folio.textPrimary)
                    .lineSpacing(24 * 0.4)
                    .tracking(-0.2)
                    .modifier(HeroGeometryModifier(id: "title-\(article.id)", namespace: heroNamespace))
            }
            .padding(.bottom, 14)

            // 2. Insight pull quote (if summary exists)
            if let summary = article.displaySummary, !summary.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.folio.accent)
                        .frame(width: 2)
                    Text(summary)
                        .font(Typography.v3HeroInsight)
                        .foregroundStyle(Color.folio.textSecondary)
                        .lineSpacing(16 * 0.65)
                        .padding(.leading, 14)
                }
                .padding(.bottom, 14)
            }

            // 3. Metadata row
            HStack(spacing: 6) {
                if let sourceName = article.effectiveSourceName {
                    Text(sourceName)
                    dotSeparator
                }
                Text(article.createdAt.relativeFormatted())
                if !article.tags.isEmpty {
                    dotSeparator
                    Text(article.tags.prefix(2).map(\.name).joined(separator: " · "))
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Color.folio.textTertiary)
        }
        .padding(.bottom, 24)
        .task {
            guard article.sourceType == .screenshot,
                  let localPath = article.localImagePath,
                  let containerURL = FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier
                  ) else { return }
            let fileURL = containerURL.appendingPathComponent(localPath)
            screenshotImage = await Task.detached {
                UIImage(contentsOfFile: fileURL.path)
            }.value
        }
    }

    private var dotSeparator: some View {
        Circle()
            .fill(Color.folio.textQuaternary)
            .frame(width: 2, height: 2)
    }
}
