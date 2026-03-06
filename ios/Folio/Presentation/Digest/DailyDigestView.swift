import SwiftUI

struct DailyDigestView: View {
    @State private var isPlaying = false
    @State private var playbackProgress: Double = 0.35
    @State private var playbackSpeed: Double = 1.0

    private let mockDuration = "5:42"
    private let mockElapsed = "2:00"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                audioPlayerCard
                digestSections
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.folio.background)
        .navigationTitle(String(localized: "digest.title", defaultValue: "Daily Digest"))
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Audio Player

    private var audioPlayerCard: some View {
        VStack(spacing: Spacing.md) {
            // Date
            HStack {
                Image(systemName: "headphones")
                    .foregroundStyle(Color.folio.accent)
                Text(formattedDate)
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textSecondary)
                Spacer()
                speedButton
            }

            // Waveform placeholder
            HStack(spacing: 2) {
                ForEach(0..<40, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Double(i) / 40.0 < playbackProgress ? Color.folio.accent : Color.folio.separator)
                        .frame(width: 4, height: CGFloat.random(in: 8...28))
                }
            }
            .frame(height: 28)

            // Progress
            HStack {
                Text(mockElapsed)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.folio.textTertiary)
                Spacer()
                Text(mockDuration)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.folio.textTertiary)
            }

            // Controls
            HStack(spacing: Spacing.lg) {
                Button { } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title3)
                        .foregroundStyle(Color.folio.textSecondary)
                }

                Button {
                    withAnimation { isPlaying.toggle() }
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Color.folio.accent)
                }

                Button { } label: {
                    Image(systemName: "goforward.30")
                        .font(.title3)
                        .foregroundStyle(Color.folio.textSecondary)
                }
            }
        }
        .padding(Spacing.md)
        .background(Color.folio.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    private var speedButton: some View {
        Button {
            let speeds: [Double] = [0.75, 1.0, 1.25, 1.5, 2.0]
            if let idx = speeds.firstIndex(of: playbackSpeed) {
                playbackSpeed = speeds[(idx + 1) % speeds.count]
            } else {
                playbackSpeed = 1.0
            }
        } label: {
            Text(String(format: "%.2gx", playbackSpeed))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.folio.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.folio.tagBackground)
                .clipShape(Capsule())
        }
    }

    // MARK: - Text Digest

    private var digestSections: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text(String(localized: "digest.textVersion", defaultValue: "Text Summary"))
                .font(Typography.listTitle)
                .foregroundStyle(Color.folio.textPrimary)

            ForEach(MockDigestSection.samples) { section in
                digestSectionCard(section)
            }
        }
    }

    private func digestSectionCard(_ section: MockDigestSection) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(section.color)
                    .frame(width: 8, height: 8)
                Text(section.category)
                    .font(Typography.tag)
                    .foregroundStyle(Color.folio.textSecondary)
            }

            Text(section.summary)
                .font(Typography.body)
                .foregroundStyle(Color.folio.textPrimary)
                .lineSpacing(4)

            // Referenced articles
            ForEach(section.articles, id: \.self) { article in
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "link")
                        .font(.caption2)
                        .foregroundStyle(Color.folio.accent)
                    Text(article)
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.link)
                        .lineLimit(1)
                }
            }
        }
        .padding(Spacing.sm)
        .background(Color.folio.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: Date())
    }
}

// MARK: - Mock Data

private struct MockDigestSection: Identifiable {
    let id = UUID()
    let category: String
    let summary: String
    let articles: [String]
    let color: Color

    static let samples: [MockDigestSection] = [
        MockDigestSection(
            category: "AI & LLM",
            summary: "Claude introduced a new tool-use paradigm with structured outputs. Meanwhile, a deep dive into prompt caching shows 60-90% cost reduction for repetitive prefixes.",
            articles: ["Claude Tool Use Guide", "Prompt Caching Deep Dive"],
            color: .purple
        ),
        MockDigestSection(
            category: "iOS",
            summary: "Apple's latest Xcode 16.2 brings improved SwiftUI previews and @Observable macro optimizations. A community post benchmarks SwiftData vs Core Data performance.",
            articles: ["What's New in Xcode 16.2", "SwiftData Performance Benchmarks"],
            color: .blue
        ),
        MockDigestSection(
            category: String(localized: "digest.mock.business", defaultValue: "Business"),
            summary: String(localized: "digest.mock.business.text", defaultValue: "An insightful analysis of indie app pricing strategies suggests annual plans convert 3x better than monthly. Key insight: anchor to the annual price, show monthly as comparison."),
            articles: [String(localized: "digest.mock.business.article", defaultValue: "Indie App Pricing in 2026")],
            color: .orange
        ),
    ]
}

#Preview {
    NavigationStack {
        DailyDigestView()
    }
}
