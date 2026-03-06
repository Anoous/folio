import SwiftUI

struct TopicsView: View {
    @State private var topics: [MockTopic] = MockTopic.samples

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.sm),
        GridItem(.flexible(), spacing: Spacing.sm),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                headerSection

                LazyVGrid(columns: columns, spacing: Spacing.sm) {
                    ForEach(topics) { topic in
                        topicCard(topic)
                    }
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.folio.background)
        .navigationTitle(String(localized: "topics.title", defaultValue: "Topics"))
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(String(localized: "topics.subtitle", defaultValue: "Auto-generated from your collection"))
                .font(Typography.body)
                .foregroundStyle(Color.folio.textSecondary)
        }
    }

    // MARK: - Topic Card

    private func topicCard(_ topic: MockTopic) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Image(systemName: topic.icon)
                    .font(.title2)
                    .foregroundStyle(Color.folio.accent)
                Spacer()
                Text("\(topic.articleCount)")
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textTertiary)
                Image(systemName: "doc.text")
                    .font(.caption)
                    .foregroundStyle(Color.folio.textTertiary)
            }

            Text(topic.name)
                .font(Typography.listTitle)
                .foregroundStyle(Color.folio.textPrimary)
                .lineLimit(2)

            Text(topic.overview)
                .font(Typography.caption)
                .foregroundStyle(Color.folio.textSecondary)
                .lineLimit(3)

            // Mini tag chips
            HStack(spacing: Spacing.xxs) {
                ForEach(topic.tags.prefix(3), id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.folio.tagText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.folio.tagBackground)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(Spacing.sm)
        .background(Color.folio.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }
}

// MARK: - Mock Data

private struct MockTopic: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let articleCount: Int
    let overview: String
    let tags: [String]

    static let samples: [MockTopic] = [
        MockTopic(
            name: "AI Agent",
            icon: "cpu",
            articleCount: 12,
            overview: "From ReAct patterns to multi-agent orchestration, covering the latest in autonomous AI systems.",
            tags: ["LangChain", "AutoGPT", "Tool Use"]
        ),
        MockTopic(
            name: "SwiftUI",
            icon: "swift",
            articleCount: 8,
            overview: "Modern iOS development with declarative UI, covering state management, navigation, and performance.",
            tags: ["iOS", "Observable", "Navigation"]
        ),
        MockTopic(
            name: String(localized: "topics.mock.startup", defaultValue: "Startup Playbook"),
            icon: "lightbulb",
            articleCount: 6,
            overview: String(localized: "topics.mock.startup.desc", defaultValue: "Pricing strategies, growth hacking, and product-market fit from founders who've been there."),
            tags: ["PMF", "Growth", "Pricing"]
        ),
        MockTopic(
            name: "RAG & Vector DB",
            icon: "cylinder.split.1x2",
            articleCount: 9,
            overview: "Retrieval-augmented generation pipelines, embedding models, and vector database comparisons.",
            tags: ["Pinecone", "Embeddings", "Chunking"]
        ),
        MockTopic(
            name: String(localized: "topics.mock.design", defaultValue: "Product Design"),
            icon: "paintbrush.pointed",
            articleCount: 5,
            overview: String(localized: "topics.mock.design.desc", defaultValue: "Design systems, information architecture, and user research methodologies."),
            tags: ["Design System", "UX", "Figma"]
        ),
        MockTopic(
            name: "Rust",
            icon: "gearshape.2",
            articleCount: 7,
            overview: "Systems programming with Rust: async runtime, ownership model, and web backends.",
            tags: ["Tokio", "Async", "WASM"]
        ),
    ]
}

#Preview {
    NavigationStack {
        TopicsView()
    }
}
