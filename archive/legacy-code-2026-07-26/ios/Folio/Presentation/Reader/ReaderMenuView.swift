import SwiftUI

struct ReaderMenuView: View {
    let article: Article
    let onDismiss: () -> Void
    let onToggleFavorite: () -> Void
    let onCopyMarkdown: () -> Void
    let onReadingPreferences: () -> Void
    let onToggleArchive: () -> Void
    let onOpenOriginal: () -> Void
    let onDelete: () -> Void

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    menuRow(
                        icon: article.isFavorite ? "bookmark.fill" : "bookmark",
                        label: article.isFavorite
                            ? String(localized: "reader.unfavorite", defaultValue: "取消收藏")
                            : String(localized: "reader.favorite", defaultValue: "收藏")
                    ) {
                        dismissThen { onToggleFavorite() }
                    }

                    menuSeparator

                    menuRow(icon: "doc.on.doc", label: String(localized: "reader.copyMarkdown", defaultValue: "复制 Markdown")) {
                        dismissThen { onCopyMarkdown() }
                    }

                    menuSeparator

                    menuRow(icon: "textformat.size", label: String(localized: "reader.readingPrefs", defaultValue: "阅读偏好")) {
                        dismissThen { onReadingPreferences() }
                    }

                    menuSeparator

                    menuRow(
                        icon: article.isArchived ? "archivebox.fill" : "archivebox",
                        label: article.isArchived
                            ? String(localized: "reader.unarchive", defaultValue: "取消归档")
                            : String(localized: "reader.archive", defaultValue: "归档")
                    ) {
                        dismissThen { onToggleArchive() }
                    }

                    if article.url != nil {
                        menuSeparator

                        menuRow(icon: "globe", label: String(localized: "reader.openInBrowser", defaultValue: "查看原文")) {
                            dismissThen { onOpenOriginal() }
                        }
                    }

                    menuSeparator

                    menuRow(icon: "trash", label: String(localized: "reader.delete", defaultValue: "删除"), isDestructive: true) {
                        dismissThen { onDelete() }
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)

                Spacer().frame(height: Spacing.lg)

                Button {
                    onDismiss()
                } label: {
                    Text(String(localized: "button.cancel", defaultValue: "取消"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.folio.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.folio.accentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, Spacing.screenPadding)
            }
            .padding(.top, Spacing.md)
            .padding(.bottom, max(proxy.safeAreaInsets.bottom, 16))
            .background(Color.folio.background)
        }
    }

    private func dismissThen(_ action: @escaping () -> Void) {
        onDismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: action)
    }

    private func menuRow(icon: String, label: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .imageScale(.medium)
                    .symbolRenderingMode(.monochrome)
                    .fontWeight(.regular)
                    .foregroundStyle(isDestructive ? Color.folio.error : Color.folio.textPrimary)
                    .frame(width: 24, alignment: .center)

                Text(label)
                    .font(.system(size: 16))
                    .foregroundStyle(isDestructive ? Color.folio.error : Color.folio.textPrimary)

                Spacer()
            }
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private var menuSeparator: some View {
        Rectangle()
            .fill(Color.folio.separator)
            .frame(height: 0.5)
    }
}
