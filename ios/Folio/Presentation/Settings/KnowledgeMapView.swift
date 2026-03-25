import SwiftUI

// MARK: - KnowledgeMapView (Prototype 05)

struct KnowledgeMapView: View {
    @State private var monthlyStats: MonthlyStatsResponse?
    @State private var echoStats: EchoStatsResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .padding(.top, 60)
            } else if let error = errorMessage {
                Text(error)
                    .foregroundStyle(Color.folio.textTertiary)
                    .padding(.top, 60)
            } else {
                statsContent
            }
        }
        .background(Color.folio.background)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadStats() }
    }

    // MARK: - Stats Content

    @ViewBuilder
    private var statsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            monthlyOverview
            topicDistributionSection
            trendInsightSection
            echoAbsorptionSection
            footerSection
        }
    }

    // MARK: - 1. Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("知识地图")
                .font(Typography.v3PageTitle)
                .foregroundStyle(Color.folio.textPrimary)

            Text(currentMonthLabel)
                .font(.system(size: 13))
                .foregroundStyle(Color.folio.textTertiary)
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, Spacing.screenPadding)
    }

    // MARK: - 2. Monthly Overview (3 columns)

    private var monthlyOverview: some View {
        HStack(spacing: 0) {
            statColumn(value: monthlyStats?.articlesCount ?? 0, label: "篇收藏")

            statColumn(value: monthlyStats?.insightsCount ?? 0, label: "个洞察")

            statColumn(value: monthlyStats?.streakDays ?? 0, label: "天连续")
        }
        .padding(.vertical, Spacing.screenPadding)
        .background(Color.folio.echoBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, Spacing.lg)
    }

    private func statColumn(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.folio.textPrimary)

            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color.folio.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 3. Topic Distribution (horizontal bar chart)

    @ViewBuilder
    private var topicDistributionSection: some View {
        let topics = Array((monthlyStats?.topicDistribution ?? []).prefix(6))
        if !topics.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("主题分布")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.folio.textPrimary)

                let maxCount = topics.map(\.count).max() ?? 1
                ForEach(Array(topics.enumerated()), id: \.offset) { index, topic in
                    topicBarRow(topic: topic, maxCount: maxCount, index: index)
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.xl)
        }
    }

    private func topicBarRow(topic: TopicStat, maxCount: Int, index: Int) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(topic.categoryName)
                .font(.system(size: 15))
                .foregroundStyle(Color.folio.textPrimary)
                .frame(width: 60, alignment: .trailing)

            GeometryReader { geometry in
                let fraction = maxCount > 0 ? CGFloat(topic.count) / CGFloat(maxCount) : 0
                RoundedRectangle(cornerRadius: 3)
                    .fill(barColor(for: index))
                    .frame(width: geometry.size.width * fraction, height: 6)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 20)

            Text("\(topic.count)")
                .font(.system(size: 13))
                .foregroundStyle(Color.folio.textTertiary)
                .frame(width: 28, alignment: .leading)
        }
    }

    private func barColor(for index: Int) -> Color {
        switch index {
        case 0: return Color.folio.textPrimary
        case 1: return Color.folio.textSecondary
        case 2: return Color.folio.textTertiary
        case 3: return Color.folio.textQuaternary
        default: return Color.folio.separator
        }
    }

    // MARK: - 4. Trend Insight

    @ViewBuilder
    private var trendInsightSection: some View {
        if let insight = monthlyStats?.trendInsight, !insight.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: 6) {
                    Text("✦")
                        .foregroundStyle(Color.folio.accent)
                    Text("趋势洞察")
                        .tracking(1)
                        .textCase(.uppercase)
                }
                .font(.system(size: 13))
                .foregroundStyle(Color.folio.textTertiary)

                Text(insight)
                    .font(Font.custom("LXGWWenKaiTC-Regular", size: 15))
                    .foregroundStyle(Color.folio.textSecondary)
                    .lineSpacing(6)
            }
            .padding(Spacing.screenPadding)
            .background(Color.folio.echoBg)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.lg)
        }
    }

    // MARK: - 5. Echo Absorption Stats

    @ViewBuilder
    private var echoAbsorptionSection: some View {
        if let echo = echoStats {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Echo 吸收统计")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.folio.textPrimary)

                HStack(spacing: Spacing.screenPadding) {
                    // Ring
                    echoRing(rate: echo.completionRate)

                    // Details
                    VStack(spacing: 0) {
                        echoDetailRow(label: "本月 Echo", value: "\(echo.totalReviews) 次")
                        Rectangle()
                            .fill(Color.folio.separator)
                            .frame(height: 0.5)
                        echoDetailRow(label: "记得", value: "\(echo.rememberedCount)", valueColor: Color.folio.success)
                        Rectangle()
                            .fill(Color.folio.separator)
                            .frame(height: 0.5)
                        echoDetailRow(label: "忘了", value: "\(echo.forgottenCount)")
                    }
                }
            }
            .padding(Spacing.screenPadding)
            .background(Color.folio.echoBg)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.xl)
        }
    }

    private func echoRing(rate: Int) -> some View {
        ZStack {
            Circle()
                .stroke(Color.folio.textQuaternary, lineWidth: 6)
                .frame(width: 80, height: 80)

            Circle()
                .trim(from: 0, to: Double(rate) / 100)
                .stroke(Color.folio.success, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 80, height: 80)

            Text("\(rate)%")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.folio.textPrimary)
        }
    }

    private func echoDetailRow(label: String, value: String, valueColor: Color = Color.folio.textPrimary) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Color.folio.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(valueColor)
        }
        .padding(.vertical, 6)
    }

    // MARK: - 6. Footer

    private var footerSection: some View {
        Text("知识在积累，你正在变得更强。")
            .font(.system(size: 13))
            .foregroundStyle(Color.folio.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 40)
            .padding(.bottom, Spacing.screenPadding)
    }

    // MARK: - Data Loading

    private func loadStats() async {
        do {
            async let monthly = APIClient.shared.getMonthlyStats()
            async let echo = APIClient.shared.getEchoStats()
            monthlyStats = try await monthly
            echoStats = try await echo
        } catch {
            errorMessage = "无法加载统计数据"
        }
        isLoading = false
    }

    // MARK: - Helpers

    private static let monthLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy 年 M 月"
        return f
    }()

    private var currentMonthLabel: String {
        Self.monthLabelFormatter.string(from: Date())
    }
}

// MARK: - Previews

#Preview("Knowledge Map") {
    NavigationStack {
        KnowledgeMapView()
    }
}
