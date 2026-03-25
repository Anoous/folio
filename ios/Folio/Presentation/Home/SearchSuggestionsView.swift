import SwiftUI

struct SearchSuggestionsView: View {
    @Binding var searchText: String
    let recentSearches: [String]
    var onShowNoteSheet: () -> Void

    private var suggestedQuestions: [String] {
        [
            "我存过的文章里关于用户留存有哪些方法？",
            "哪些文章提到了飞轮效应？",
            "量子计算最近有什么进展？",
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Recent searches
                if !recentSearches.isEmpty {
                    Text("最近")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.folio.textTertiary)
                        .tracking(0.5)
                        .padding(.horizontal, Spacing.screenPadding)
                        .padding(.top, 20)
                        .padding(.bottom, 12)

                    ForEach(recentSearches, id: \.self) { search in
                        Button {
                            searchText = search
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.folio.textTertiary)
                                Text(search)
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.folio.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, Spacing.screenPadding)
                            .padding(.vertical, 12)
                        }
                    }

                    Rectangle()
                        .fill(Color.folio.separator)
                        .frame(height: 0.5)
                        .padding(.horizontal, Spacing.screenPadding)
                        .padding(.vertical, 16)
                }

                // Suggested questions
                Text("试试这样问")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.folio.textTertiary)
                    .tracking(0.5)
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.top, recentSearches.isEmpty ? 20 : 0)
                    .padding(.bottom, 16)

                ForEach(suggestedQuestions, id: \.self) { question in
                    Button {
                        searchText = question
                    } label: {
                        Text("\u{201C}\(question)\u{201D}")
                            .font(Font.custom("LXGWWenKaiTC-Regular", size: 15).italic())
                            .foregroundStyle(Color.folio.textSecondary)
                            .padding(.horizontal, Spacing.screenPadding)
                            .padding(.vertical, 10)
                    }
                }

                // Quick actions
                HStack(spacing: 12) {
                    quickActionCard(icon: "link", title: "粘贴链接") {
                        if let string = UIPasteboard.general.string,
                           let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
                           url.scheme?.hasPrefix("http") == true
                        {
                            searchText = string.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    quickActionCard(icon: "square.and.pencil", title: "记一条笔记") {
                        onShowNoteSheet()
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, 24)
            }
        }
    }

    private func quickActionCard(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.folio.textTertiary)
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.folio.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Color.folio.echoBg)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
