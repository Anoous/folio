import SwiftUI
import SwiftData

struct TimelineView: View {
    let articles: [Article]
    @State private var collapsedMonths: Set<String> = []

    var body: some View {
        let monthGroups = groupByMonth(articles)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(monthGroups, id: \.month) { group in
                    Section {
                        if !collapsedMonths.contains(group.month) {
                            ForEach(group.dayGroups, id: \.day) { dayGroup in
                                daySection(day: dayGroup.day, articles: dayGroup.articles)
                            }
                        }
                    } header: {
                        monthHeader(month: group.month, count: group.articleCount)
                    }
                }
            }
        }
        .background(Color.folio.background)
    }

    private func monthHeader(month: String, count: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if collapsedMonths.contains(month) {
                    collapsedMonths.remove(month)
                } else {
                    collapsedMonths.insert(month)
                }
            }
        } label: {
            HStack {
                Image(systemName: collapsedMonths.contains(month) ? "chevron.right" : "chevron.down")
                    .font(.caption)
                Text(month)
                    .font(Typography.listTitle)
                Spacer()
                Text("\(count)")
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textTertiary)
            }
            .foregroundStyle(Color.folio.textPrimary)
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.sm)
            .background(Color.folio.background)
        }
    }

    private func daySection(day: String, articles: [Article]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(day)
                .font(Typography.caption)
                .foregroundStyle(Color.folio.textTertiary)
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.xs)

            ForEach(articles) { article in
                NavigationLink(value: article.id) {
                    Text(article.displayTitle)
                        .font(Typography.body)
                        .foregroundStyle(Color.folio.textPrimary)
                        .lineLimit(1)
                        .padding(.horizontal, Spacing.screenPadding)
                        .padding(.vertical, Spacing.xxs)
                }
            }
        }
    }

    // MARK: - Grouping

    struct MonthGroup {
        let month: String
        let dayGroups: [DayGroup]
        var articleCount: Int { dayGroups.reduce(0) { $0 + $1.articles.count } }
    }

    struct DayGroup {
        let day: String
        let articles: [Article]
    }

    private func groupByMonth(_ articles: [Article]) -> [MonthGroup] {
        let formatter = DateFormatter()
        let dayFormatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yyyyMMMM")
        dayFormatter.setLocalizedDateFormatFromTemplate("MMMd")

        var monthDict: [String: [String: [Article]]] = [:]
        var monthOrder: [String] = []

        for article in articles.sorted(by: { $0.createdAt > $1.createdAt }) {
            let month = formatter.string(from: article.createdAt)
            let day = dayFormatter.string(from: article.createdAt)

            if monthDict[month] == nil {
                monthOrder.append(month)
                monthDict[month] = [:]
            }
            monthDict[month]?[day, default: []].append(article)
        }

        return monthOrder.map { month in
            let days = monthDict[month] ?? [:]
            let sortedDays = days.keys.sorted().reversed().map { day in
                DayGroup(day: day, articles: days[day]!)
            }
            return MonthGroup(month: month, dayGroups: sortedDays)
        }
    }
}
