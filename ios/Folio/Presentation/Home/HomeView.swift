import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthViewModel.self) private var authViewModel: AuthViewModel?
    @Environment(OfflineQueueManager.self) private var offlineQueueManager: OfflineQueueManager?
    @Query(sort: \Article.createdAt, order: .reverse) private var articles: [Article]
    @State private var viewModel: HomeViewModel?
    @State private var showAddURL = false
    @State private var urlInput = ""
    @State private var articleToDelete: Article?
    @State private var showDeleteConfirmation = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any]? = nil

    var body: some View {
        Group {
            if articles.isEmpty {
                EmptyStateView(onPasteURL: { url in
                    saveURL(url.absoluteString)
                })
            } else {
                articleList
            }
        }
        .navigationTitle("Folio")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    urlInput = ""
                    // Pre-fill from clipboard if available
                    if let url = UIPasteboard.general.url {
                        urlInput = url.absoluteString
                    } else if let string = UIPasteboard.general.string,
                              let url = URL(string: string), url.scheme?.hasPrefix("http") == true {
                        urlInput = string
                    }
                    showAddURL = true
                } label: {
                    Label(String(localized: "home.add", defaultValue: "Add"), systemImage: "plus")
                }
            }
        }
        .alert(String(localized: "home.addURL.title", defaultValue: "Add Link"), isPresented: $showAddURL) {
            TextField(String(localized: "home.addURL.placeholder", defaultValue: "https://"), text: $urlInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(String(localized: "button.cancel", defaultValue: "Cancel"), role: .cancel) {}
            Button(String(localized: "home.addURL.save", defaultValue: "Save")) {
                let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                saveURL(trimmed)
            }
        } message: {
            Text(String(localized: "home.addURL.message", defaultValue: "Enter or paste a link to save"))
        }
        .navigationDestination(for: UUID.self) { articleID in
            if let article = articles.first(where: { $0.id == articleID }) {
                ReaderView(article: article)
            }
        }
        .toast(isPresented: Binding(
            get: { viewModel?.showToast ?? false },
            set: { viewModel?.showToast = $0 }
        ), message: viewModel?.toastMessage ?? "", icon: viewModel?.toastIcon)
        .confirmationDialog(
            String(localized: "reader.deleteConfirm", defaultValue: "Delete this article?"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "reader.delete", defaultValue: "Delete"), role: .destructive) {
                if let article = articleToDelete {
                    viewModel?.deleteArticle(article)
                    articleToDelete = nil
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = HomeViewModel(
                    context: modelContext,
                    isAuthenticated: authViewModel?.isAuthenticated ?? false
                )
                viewModel?.fetchArticles()
            }
        }
        .onChange(of: authViewModel?.isAuthenticated) { _, newValue in
            viewModel?.isAuthenticated = newValue ?? false
        }
    }

    private var articleList: some View {
        List {
            if let vm = viewModel {
                ForEach(vm.groupedArticles.isEmpty ? vm.groupByDate(articles) : vm.groupedArticles, id: \.0) { group in
                    Section {
                        ForEach(group.1) { article in
                            NavigationLink(value: article.id) {
                                ArticleCardView(article: article)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    articleToDelete = article
                                    showDeleteConfirmation = true
                                } label: {
                                    Label(String(localized: "reader.delete", defaultValue: "Delete"), systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    vm.toggleFavorite(article)
                                } label: {
                                    Label(
                                        article.isFavorite
                                            ? String(localized: "reader.unfavorite", defaultValue: "Remove Favorite")
                                            : String(localized: "reader.favorite", defaultValue: "Favorite"),
                                        systemImage: article.isFavorite ? "heart.slash" : "heart"
                                    )
                                }
                                .tint(article.isFavorite ? .gray : .pink)
                            }
                            .contextMenu {
                                Button {
                                    vm.toggleFavorite(article)
                                } label: {
                                    Label(
                                        article.isFavorite
                                            ? String(localized: "reader.unfavorite", defaultValue: "Remove Favorite")
                                            : String(localized: "reader.favorite", defaultValue: "Favorite"),
                                        systemImage: article.isFavorite ? "heart.fill" : "heart"
                                    )
                                }

                                Button {
                                    vm.archiveArticle(article)
                                } label: {
                                    Label(
                                        article.isArchived
                                            ? String(localized: "reader.unarchive", defaultValue: "Unarchive")
                                            : String(localized: "reader.archive", defaultValue: "Archive"),
                                        systemImage: article.isArchived ? "archivebox.fill" : "archivebox"
                                    )
                                }

                                Button {
                                    if let url = URL(string: article.url) {
                                        shareItems = [url]
                                        showShareSheet = true
                                    }
                                } label: {
                                    Label(String(localized: "reader.share", defaultValue: "Share"), systemImage: "square.and.arrow.up")
                                }

                                Button {
                                    UIPasteboard.general.string = article.url
                                    vm.showToast = false
                                    DispatchQueue.main.async {
                                        vm.toastMessage = String(localized: "home.article.linkCopied", defaultValue: "Link copied")
                                        vm.toastIcon = "doc.on.doc"
                                        vm.showToast = true
                                    }
                                } label: {
                                    Label(String(localized: "home.article.copyLink", defaultValue: "Copy Link"), systemImage: "link")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    articleToDelete = article
                                    showDeleteConfirmation = true
                                } label: {
                                    Label(String(localized: "reader.delete", defaultValue: "Delete"), systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text(group.0)
                            .font(Typography.caption)
                            .foregroundStyle(Color.folio.textTertiary)
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: Spacing.screenPadding, bottom: 0, trailing: Spacing.screenPadding))
                .listRowSeparatorTint(Color.folio.separator)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel?.refreshFromServer()
        }
        .background(Color.folio.background)
        .sheet(isPresented: $showShareSheet) {
            if let items = shareItems {
                ShareSheet(activityItems: items)
            }
        }
    }

    private func saveURL(_ urlString: String) {
        let manager = SharedDataManager(context: modelContext)
        do {
            _ = try manager.saveArticleFromText(urlString)
            SharedDataManager.incrementQuota()
            viewModel?.fetchArticles()
            showToast(String(localized: "home.addURL.saved", defaultValue: "Link saved"), icon: "checkmark.circle.fill")

            // Trigger backend processing
            Task {
                await offlineQueueManager?.processPendingArticles()
            }
        } catch SharedDataError.duplicateURL {
            showToast(String(localized: "home.addURL.duplicate", defaultValue: "Link already exists"), icon: "exclamationmark.triangle.fill")
        } catch {
            showToast(String(localized: "home.addURL.error", defaultValue: "Failed to save"), icon: "xmark.circle.fill")
        }
    }

    private func showToast(_ message: String, icon: String?) {
        viewModel?.toastMessage = message
        viewModel?.toastIcon = icon
        withAnimation { viewModel?.showToast = true }
    }

}
