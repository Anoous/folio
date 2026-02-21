import SwiftUI

struct TagFilterView: View {
    @Binding var selectedTags: [Tag]
    let tags: [Tag]
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "tag")
                        .font(.caption)
                    Text(String(localized: "filter.tags", defaultValue: "Tag filter"))
                        .font(Typography.caption)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(Color.folio.textTertiary)
                .padding(.horizontal, Spacing.screenPadding)
            }

            if isExpanded {
                FlowLayout(spacing: Spacing.xs) {
                    ForEach(tags) { tag in
                        Button {
                            toggleTag(tag)
                        } label: {
                            Text(tag.name)
                                .font(Typography.tag)
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, Spacing.xxs)
                                .foregroundStyle(isSelected(tag) ? Color.folio.cardBackground : Color.folio.tagText)
                                .background(isSelected(tag) ? Color.folio.accent : Color.folio.tagBackground)
                                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                        }
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func isSelected(_ tag: Tag) -> Bool {
        selectedTags.contains(where: { $0.id == tag.id })
    }

    private func toggleTag(_ tag: Tag) {
        if let index = selectedTags.firstIndex(where: { $0.id == tag.id }) {
            selectedTags.remove(at: index)
        } else {
            selectedTags.append(tag)
        }
    }
}
