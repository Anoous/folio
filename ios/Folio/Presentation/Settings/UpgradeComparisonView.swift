import SwiftUI

// MARK: - State 4: Upgrade Comparison View

struct UpgradeComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionManager.self) private var subscriptionManager: SubscriptionManager?

    private var yearlyPriceText: String {
        if let product = subscriptionManager?.yearlyProduct {
            return "\(product.displayPrice)/年"
        }
        return "¥98/年"
    }

    private var monthlyPriceText: String {
        if let product = subscriptionManager?.monthlyProduct {
            return "\(product.displayPrice)/月"
        }
        return "¥12/月"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Header
                    VStack(spacing: Spacing.xs) {
                        Text("Folio Pro")
                            .font(Typography.v3ComparisonTitle)
                            .foregroundStyle(Color.folio.textPrimary)

                        Text("解锁 Folio 的全部能力")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.folio.textSecondary)
                    }
                    .padding(.top, Spacing.lg)

                    // Comparison Table
                    comparisonTable

                    // CTA
                    VStack(spacing: Spacing.xs) {
                        Button {
                            Task {
                                if let product = subscriptionManager?.yearlyProduct {
                                    await subscriptionManager?.purchase(product)
                                }
                            }
                        } label: {
                            if subscriptionManager?.isLoading == true {
                                ProgressView()
                                    .tint(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Color.folio.textPrimary)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            } else {
                                Text("升级 Pro — \(yearlyPriceText)")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Color.folio.textPrimary)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                        .disabled(subscriptionManager?.isLoading == true)

                        if let errorMessage = subscriptionManager?.errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.folio.error)
                        }

                        Text("或 \(monthlyPriceText) · 随时取消")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.folio.textTertiary)

                        Text("7 天免费试用 · 试用期内取消不收费")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.folio.textQuaternary)

                        Button {
                            Task { await subscriptionManager?.restorePurchases() }
                        } label: {
                            Text("恢复购买")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.folio.textSecondary)
                        }
                        .padding(.top, Spacing.xxs)
                    }
                    .padding(.top, Spacing.sm)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xl)
            }
            .background(Color.folio.background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.folio.textQuaternary)
                    }
                }
            }
        }
    }

    // MARK: - Comparison Table

    private var comparisonTable: some View {
        VStack(spacing: 0) {
            // Table header
            HStack {
                Spacer()
                Text("Free")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.folio.textTertiary)
                    .frame(width: 56, alignment: .center)
                Text("Pro")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.folio.accent)
                    .frame(width: 56, alignment: .center)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Rectangle()
                .fill(Color.folio.separator)
                .frame(height: 0.5)

            // Rows
            ForEach(Array(comparisonRows.enumerated()), id: \.offset) { index, row in
                comparisonRow(
                    feature: row.feature,
                    freeValue: row.freeValue,
                    proValue: row.proValue
                )

                if index < comparisonRows.count - 1 {
                    Rectangle()
                        .fill(Color.folio.separator)
                        .frame(height: 0.5)
                        .padding(.leading, 16)
                }
            }
        }
        .background(Color.folio.echoBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func comparisonRow(feature: String, freeValue: ComparisonValue, proValue: ComparisonValue) -> some View {
        HStack {
            Text(feature)
                .font(.system(size: 15))
                .foregroundStyle(Color.folio.textPrimary)

            Spacer()

            comparisonValueView(freeValue)
                .frame(width: 56, alignment: .center)
            comparisonValueView(proValue)
                .frame(width: 56, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func comparisonValueView(_ value: ComparisonValue) -> some View {
        switch value {
        case .check:
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.folio.success)
        case .dash:
            Text("—")
                .font(.system(size: 14))
                .foregroundStyle(Color.folio.textQuaternary)
        case .text(let string):
            Text(string)
                .font(.system(size: 13))
                .foregroundStyle(Color.folio.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: - Comparison Data

    private enum ComparisonValue {
        case check
        case dash
        case text(String)
    }

    private struct ComparisonRow {
        let feature: String
        let freeValue: ComparisonValue
        let proValue: ComparisonValue
    }

    private var comparisonRows: [ComparisonRow] {
        [
            ComparisonRow(feature: "收藏 & AI 摘要", freeValue: .check, proValue: .check),
            ComparisonRow(feature: "关键词搜索", freeValue: .check, proValue: .check),
            ComparisonRow(feature: "语义搜索", freeValue: .dash, proValue: .check),
            ComparisonRow(feature: "Echo 回忆", freeValue: .text("3次/周"), proValue: .text("每日")),
            ComparisonRow(feature: "RAG 问答", freeValue: .text("5次/月"), proValue: .text("无限")),
            ComparisonRow(feature: "知识简报", freeValue: .dash, proValue: .check),
            ComparisonRow(feature: "知识地图", freeValue: .dash, proValue: .check),
            // iCloud 同步已移除
            ComparisonRow(feature: "存储空间", freeValue: .text("1 GB"), proValue: .text("无限")),
        ]
    }
}

#Preview("Upgrade Comparison") {
    UpgradeComparisonView()
}
