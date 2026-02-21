import SwiftUI

struct SearchHistoryView: View {
    let history: [String]
    let popularTags: [Tag]
    let onSelectQuery: (String) -> Void
    let onDeleteItem: (String) -> Void
    let onClearAll: () -> Void
    let onSelectTag: (Tag) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // MARK: - Recent Searches
                if !history.isEmpty {
                    recentSearchesSection
                }

                // MARK: - Popular Tags
                if !popularTags.isEmpty {
                    popularTagsSection
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.md)
        }
    }

    // MARK: - Recent Searches Section

    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(String(localized: "search.recent", defaultValue: "Recent Searches"))
                    .font(Typography.listTitle)
                    .foregroundStyle(Color.folio.textPrimary)

                Spacer()

                Button {
                    onClearAll()
                } label: {
                    Text(String(localized: "search.clearAll", defaultValue: "Clear"))
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.accent)
                }
            }

            ForEach(history, id: \.self) { query in
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.folio.textTertiary)

                    Text(query)
                        .font(Typography.body)
                        .foregroundStyle(Color.folio.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        onDeleteItem(query)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.folio.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelectQuery(query)
                }
                .padding(.vertical, Spacing.xxs)
            }
        }
    }

    // MARK: - Popular Tags Section

    private var popularTagsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(String(localized: "search.popularTags", defaultValue: "Popular Tags"))
                .font(Typography.listTitle)
                .foregroundStyle(Color.folio.textPrimary)

            FlowLayout(spacing: Spacing.xs) {
                ForEach(popularTags) { tag in
                    TagChip(text: tag.name)
                        .onTapGesture {
                            onSelectTag(tag)
                        }
                }
            }
        }
    }
}

