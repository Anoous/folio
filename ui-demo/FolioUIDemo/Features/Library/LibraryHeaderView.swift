import SwiftUI

struct LibraryHeaderView: View {
    let selectedFilter: DemoLibraryFilter
    let isSearching: Bool
    let onSelectFilter: (DemoLibraryFilter) -> Void
    let onToggleSearch: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("资料库")
                .font(FolioTypography.editorialBold(34, relativeTo: .largeTitle))
                .foregroundStyle(FolioPalette.inkGreenDeep)
                .lineLimit(1)

            Spacer()

            Button(action: onToggleSearch) {
                Label(
                    isSearching
                        ? String(localized: .libraryCloseSearch)
                        : String(localized: .librarySearch),
                    systemImage: isSearching
                        ? "magnifyingglass.circle.fill"
                        : "magnifyingglass"
                )
                .labelStyle(.iconOnly)
                .font(.body.weight(.medium))
                .foregroundStyle(FolioPalette.inkGreenDeep)
                .frame(
                    width: FolioMetrics.minimumTapTarget,
                    height: FolioMetrics.minimumTapTarget
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("library-search")

            Menu {
                ForEach(DemoLibraryFilter.allCases) { filter in
                    Button(action: { onSelectFilter(filter) }) {
                        if filter == selectedFilter {
                            Label(filter.title, systemImage: "checkmark")
                        } else {
                            Text(filter.title)
                        }
                    }
                }
            } label: {
                Image(systemName: selectedFilter == .all
                    ? "line.3.horizontal.decrease"
                    : "line.3.horizontal.decrease.circle.fill"
                )
                    .font(.body.weight(.medium))
                    .foregroundStyle(FolioPalette.inkGreenDeep)
                    .frame(
                        width: FolioMetrics.minimumTapTarget,
                        height: FolioMetrics.minimumTapTarget
                    )
            }
            .accessibilityLabel("筛选")
            .accessibilityValue(selectedFilter.title)
            .accessibilityIdentifier("library-filter")

            Button(action: onOpenSettings) {
                FolioAvatar(size: FolioMetrics.minimumTapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开设置")
        }
        .padding(.top, 18)
        .padding(.bottom, 17)
    }
}
