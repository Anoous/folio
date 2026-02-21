import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthViewModel.self) private var authViewModel: AuthViewModel?
    @Query(sort: \Article.createdAt, order: .reverse) private var articles: [Article]
    @State private var viewModel: HomeViewModel?

    var body: some View {
        Group {
            if articles.isEmpty {
                EmptyStateView(onPasteURL: nil)
            } else {
                articleList
            }
        }
        .navigationTitle("Folio")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // Paste action placeholder
                } label: {
                    Label(String(localized: "empty.paste", defaultValue: "Paste"), systemImage: "doc.on.clipboard")
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
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                if let vm = viewModel {
                    ForEach(vm.groupedArticles.isEmpty ? groupByDate(articles) : vm.groupedArticles, id: \.0) { group in
                        Section {
                            ForEach(group.1) { article in
                                NavigationLink(value: article.id) {
                                    ArticleCardView(article: article)
                                }
                                .buttonStyle(.plain)
                                Divider()
                                    .padding(.leading, Spacing.screenPadding)
                            }
                        } header: {
                            Text(group.0)
                                .font(Typography.caption)
                                .foregroundStyle(Color.folio.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Spacing.screenPadding)
                                .padding(.vertical, Spacing.xs)
                                .background(Color.folio.background)
                        }
                    }
                }
            }
        }
        .refreshable {
            await viewModel?.refreshFromServer()
        }
        .background(Color.folio.background)
    }

    private func groupByDate(_ articles: [Article]) -> [(String, [Article])] {
        let calendar = Calendar.current
        var groups: [String: [Article]] = [:]
        var order: [String] = []
        for article in articles {
            let key: String
            if calendar.isDateInToday(article.createdAt) {
                key = "Today"
            } else if calendar.isDateInYesterday(article.createdAt) {
                key = "Yesterday"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                key = formatter.string(from: article.createdAt)
            }
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(article)
        }
        return order.compactMap { key in
            guard let items = groups[key] else { return nil }
            return (key, items)
        }
    }
}
