import SwiftUI

struct LibrarySearchResultsView: View {
    let results: [DemoSearchResult]
    let transitionNamespace: Namespace.ID
    let onOpen: (DemoSearchResult) -> Void

    var body: some View {
        if results.isEmpty {
            ScrollView {
                ContentUnavailableView.search
                    .padding(.top, 48)
            }
            .scrollIndicators(.hidden)
        } else {
            List(results) { result in
                LibrarySearchResultRow(
                    result: result,
                    transitionNamespace: transitionNamespace,
                    onOpen: { onOpen(result) }
                )
                .listRowInsets(
                    EdgeInsets(
                        top: 0,
                        leading: FolioMetrics.libraryInset,
                        bottom: 0,
                        trailing: FolioMetrics.libraryInset
                    )
                )
                .listRowSeparator(.hidden)
                .listRowBackground(FolioPalette.canvas)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("library-search-results")
        }
    }
}
