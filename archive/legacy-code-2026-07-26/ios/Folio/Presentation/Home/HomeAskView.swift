import SwiftUI

struct HomeAskView: View {
    var viewModel: HomeViewModel
    @Binding var query: String
    let recentSearches: [String]
    let isAuthenticated: Bool
    let focusRequest: HomeTabFocusRequest?
    let onSaveRecentSearch: (String) -> Void
    let onOpenAccount: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.selectArticle) private var selectArticle
    @FocusState private var isInputFocused: Bool

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasAnswerState: Bool {
        viewModel.ragIsStreaming
            || viewModel.ragSources != nil
            || !viewModel.ragPartialAnswer.isEmpty
            || viewModel.ragError != nil
            || !viewModel.ragThread.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            askBar

            if !isAuthenticated {
                signedOutState
            } else if hasAnswerState {
                answerContent
            } else if viewModel.activeKnowledgePanel == .spark {
                sparkContent
            } else if viewModel.activeKnowledgePanel == .learn {
                learnContent
            } else {
                SearchSuggestionsView(
                    searchText: $query,
                    recentSearches: recentSearches,
                    showsCaptureActions: false,
                    onShowNoteSheet: {},
                    onShowSpark: { Task { await viewModel.loadSpark() } },
                    onShowLearn: { Task { await viewModel.loadLearn() } },
                    onSelectSearch: { selected in
                        submit(selected)
                    }
                )
                .contentMargins(.bottom, 154, for: .scrollContent)
            }
        }
        .background(FolioPaperPalette.background)
        .onAppear {
            applyFocusRequest(focusRequest)
        }
        .onChange(of: focusRequest?.id) { _, _ in
            applyFocusRequest(focusRequest)
        }
        .onChange(of: query) { _, newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                viewModel.clearRAG()
                viewModel.clearKnowledge()
            }
        }
    }

    private var askBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 15))
                .foregroundStyle(Color.folio.accent)

            TextField("向 Folio 提问", text: $query, axis: .vertical)
                .font(.system(size: 16))
                .focused($isInputFocused)
                .lineLimit(1...3)
                .submitLabel(.send)
                .disabled(!isAuthenticated)
                .onSubmit {
                    submit(query)
                }

            Button {
                submit(query)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(canSubmit ? Color.folio.accent : Color.folio.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .accessibilityLabel("发送问题")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.folio.echoBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.bottom, 12)
    }

    private var canSubmit: Bool {
        isAuthenticated && !trimmedQuery.isEmpty && !viewModel.ragIsStreaming
    }

    private var signedOutState: some View {
        VStack(spacing: Spacing.md) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(Color.folio.textTertiary)

            Text("登录后向 Folio 提问")
                .font(Typography.listTitle)
                .foregroundStyle(Color.folio.textPrimary)

            Text("Folio 会综合你的收藏回答，并溯源到原文。")
                .font(Typography.caption)
                .foregroundStyle(Color.folio.textSecondary)
                .multilineTextAlignment(.center)

            Button("登录 / 注册", action: onOpenAccount)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.folio.textPrimary)
                .clipShape(Capsule())

            Spacer()
            Color.clear.frame(height: 124)
        }
        .padding(.horizontal, Spacing.screenPadding)
    }

    private var answerContent: some View {
        ScrollView {
            if viewModel.ragIsStreaming && viewModel.ragSources == nil && viewModel.ragPartialAnswer.isEmpty {
                RAGLoadingView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
            } else if let error = viewModel.ragError {
                RAGErrorView(errorType: error, onRetry: { submit(query) })
                    .padding(.top, 80)
            } else {
                RAGAnswerView(
                    thread: viewModel.ragThread,
                    partialAnswer: viewModel.ragPartialAnswer,
                    sources: viewModel.ragSources?.sources ?? [],
                    sourceCount: viewModel.ragSources?.sourceCount ?? 0,
                    citedIndices: viewModel.ragCitedIndices,
                    followupSuggestions: viewModel.ragFollowupSuggestions,
                    isStreaming: viewModel.ragIsStreaming,
                    onSourceTap: openSourceArticle,
                    onFollowup: { question in
                        query = question
                        onSaveRecentSearch(question)
                        viewModel.submitFollowup(question)
                    },
                    onStop: {
                        viewModel.ragStreamTask?.cancel()
                    }
                )
            }
        }
        .contentMargins(.bottom, 154, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var sparkContent: some View {
        if viewModel.isKnowledgeLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.knowledgeError {
            knowledgeError(error)
        } else {
            KnowledgeSparkView(insights: viewModel.sparkInsights) { question in
                submit(question)
            }
            .contentMargins(.bottom, 154, for: .scrollContent)
        }
    }

    @ViewBuilder
    private var learnContent: some View {
        if viewModel.isKnowledgeLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.knowledgeError {
            knowledgeError(error)
        } else if let summary = viewModel.learnSummary {
            KnowledgeLearnView(summary: summary, items: viewModel.learnItems)
                .contentMargins(.bottom, 154, for: .scrollContent)
        } else {
            Spacer()
        }
    }

    private func knowledgeError(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 14))
            .foregroundStyle(Color.folio.textSecondary)
            .padding(Spacing.screenPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func submit(_ rawQuestion: String) {
        let question = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAuthenticated, !question.isEmpty, !viewModel.ragIsStreaming else { return }

        query = question
        onSaveRecentSearch(question)
        viewModel.submitRAGQuery(question)
        isInputFocused = false
    }

    private func openSourceArticle(_ articleId: String) {
        let repo = ArticleRepository(context: modelContext)
        if let article = try? repo.fetchByServerID(articleId) {
            selectArticle(article)
        }
    }

    private func applyFocusRequest(_ request: HomeTabFocusRequest?) {
        guard request?.target == .askInput else { return }
        isInputFocused = true
    }
}
