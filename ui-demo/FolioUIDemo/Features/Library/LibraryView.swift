import SwiftUI

struct LibraryView: View {
    @Bindable var store: DemoStore
    let onOpenSettings: () -> Void
    let onBeginSaving: () -> Void
    let onShowShareDemo: () -> Void
    let transitionNamespace: Namespace.ID

    var body: some View {
        VStack(spacing: 0) {
            LibraryHeaderView(
                selectedFilter: store.libraryFilter,
                onSelectFilter: store.selectFilter,
                onOpenSettings: onOpenSettings
            )
            .padding(.horizontal, FolioMetrics.libraryInset)

            if !store.isOnline {
                LibraryConnectivityBanner(onOpenSettings: onOpenSettings)
                    .padding(.horizontal, FolioMetrics.libraryInset)
                    .padding(.bottom, 8)
            }

            if store.articles.isEmpty {
                ScrollView {
                    LibraryEmptyStateView(
                        onBeginSaving: onBeginSaving,
                        onShowShareDemo: onShowShareDemo
                    )
                    .padding(.bottom, FolioMetrics.tabBarHeight + 28)
                }
                .scrollIndicators(.hidden)
            } else if store.filteredArticles.isEmpty {
                ScrollView {
                    LibraryFilterEmptyView(
                        filter: store.libraryFilter,
                        onClear: { store.selectFilter(.all) }
                    )
                }
                .scrollIndicators(.hidden)
            } else {
                List {
                    ForEach(store.visibleArticles) { article in
                        LibraryArticleRow(
                            article: article,
                            transitionNamespace: transitionNamespace,
                            onOpen: { store.openArticle(article) }
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("删除", systemImage: "trash", role: .destructive) {
                                store.deleteArticle(article)
                            }
                            .accessibilityIdentifier("library-delete-\(article.id)")
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            if article.status.needsAttention {
                                Button("重试", systemImage: "arrow.clockwise") {
                                    store.retryArticle(article)
                                }
                                .tint(FolioPalette.inkGreen)
                                .accessibilityIdentifier("library-retry-\(article.id)")
                            }
                        }
                    }

                    if store.canLoadMoreArticles {
                        LibraryLoadMoreRow(
                            remainingCount: store.filteredArticles.count - store.visibleArticles.count,
                            action: store.loadMoreArticles
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
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable(action: store.refreshLibrary)
                .accessibilityIdentifier("library-list")
            }
        }
        .background(FolioPalette.canvas)
        .overlay(alignment: .bottom) {
            if let pendingDeletion = store.pendingDeletion {
                LibraryUndoBanner(
                    articleTitle: pendingDeletion.article.title,
                    onUndo: store.undoDeletion
                )
                .padding(.horizontal, FolioMetrics.compactInset)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: store.pendingDeletion?.article.id)
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview("Seeded library") {
    @Previewable @Namespace var transitionNamespace
    @Previewable @State var store = DemoStore(initialScreen: .library)

    LibraryView(
        store: store,
        onOpenSettings: {},
        onBeginSaving: {},
        onShowShareDemo: {},
        transitionNamespace: transitionNamespace
    )
}

#Preview("First save") {
    @Previewable @Namespace var transitionNamespace
    @Previewable @State var store = DemoStore()

    LibraryView(
        store: store,
        onOpenSettings: {},
        onBeginSaving: {},
        onShowShareDemo: {},
        transitionNamespace: transitionNamespace
    )
}
