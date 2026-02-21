import SwiftUI
import SwiftData

struct CategoryFilterBar: View {
    @Binding var selectedCategory: Folio.Category?
    let categories: [Folio.Category]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                // "All" button
                filterChip(
                    title: String(localized: "filter.all", defaultValue: "All"),
                    isSelected: selectedCategory == nil
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedCategory = nil
                    }
                }

                ForEach(categories.filter { $0.articleCount > 0 }) { category in
                    filterChip(
                        title: category.localizedName,
                        icon: category.icon,
                        isSelected: selectedCategory?.id == category.id
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCategory = category
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
        }
        .padding(.vertical, Spacing.xs)
    }

    private func filterChip(title: String, icon: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.xxs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(Typography.tag)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .foregroundStyle(isSelected ? Color.folio.cardBackground : Color.folio.textPrimary)
            .background(isSelected ? Color.folio.accent : Color.folio.tagBackground)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        }
    }
}
