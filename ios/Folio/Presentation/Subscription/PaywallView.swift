import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTier: SubscriptionTier = .pro
    @State private var showThankYou = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                headerSection
                tierCards
                featureComparison
                subscribeButton
                restoreButton
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.folio.background)
        .navigationTitle(String(localized: "paywall.title", defaultValue: "Upgrade"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(String(localized: "paywall.thankYou", defaultValue: "Thank you!"), isPresented: $showThankYou) {
            Button("OK") { dismiss() }
        } message: {
            Text(String(localized: "paywall.mockPurchase", defaultValue: "This is a demo. StoreKit integration coming soon."))
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(Color.folio.accent)
                .padding(.top, Spacing.lg)

            Text(String(localized: "paywall.headline", defaultValue: "Unlock the full power of Folio"))
                .font(Typography.pageTitle)
                .foregroundStyle(Color.folio.textPrimary)
                .multilineTextAlignment(.center)

            Text(String(localized: "paywall.subtitle", defaultValue: "AI-powered organization, unlimited saves, and more"))
                .font(Typography.body)
                .foregroundStyle(Color.folio.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Tier Cards

    private var tierCards: some View {
        VStack(spacing: Spacing.sm) {
            ForEach(SubscriptionTier.allCases) { tier in
                tierCard(tier)
            }
        }
    }

    private func tierCard(_ tier: SubscriptionTier) -> some View {
        let isSelected = selectedTier == tier
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedTier = tier }
        } label: {
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xs) {
                        Text(tier.displayName)
                            .font(Typography.listTitle)
                            .foregroundStyle(Color.folio.textPrimary)
                        if tier == .proPlus {
                            Text(String(localized: "paywall.bestValue", defaultValue: "Best Value"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.folio.accent)
                                .clipShape(Capsule())
                        }
                    }
                    Text(tier.priceDescription)
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.textSecondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.folio.accent : Color.folio.textTertiary)
            }
            .padding(Spacing.md)
            .background(Color.folio.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.medium)
                    .stroke(isSelected ? Color.folio.accent : Color.folio.separator, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Feature Comparison

    private var featureComparison: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(String(localized: "paywall.features", defaultValue: "What you get"))
                .font(Typography.listTitle)
                .foregroundStyle(Color.folio.textPrimary)

            ForEach(PaywallFeature.allFeatures) { feature in
                featureRow(feature)
            }
        }
        .padding(Spacing.md)
        .background(Color.folio.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    private func featureRow(_ feature: PaywallFeature) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: feature.icon)
                .font(.body)
                .foregroundStyle(Color.folio.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(Typography.body)
                    .foregroundStyle(Color.folio.textPrimary)
                Text(feature.subtitle)
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textTertiary)
            }

            Spacer()

            HStack(spacing: Spacing.md) {
                tierBadge(feature.freeTier)
                tierBadge(feature.proTier)
                tierBadge(feature.proPlusTier)
            }
        }
    }

    private func tierBadge(_ available: Bool) -> some View {
        Image(systemName: available ? "checkmark" : "minus")
            .font(.caption2.weight(.bold))
            .foregroundStyle(available ? Color.folio.success : Color.folio.textTertiary)
            .frame(width: 20)
    }

    // MARK: - Actions

    private var subscribeButton: some View {
        FolioButton(
            title: String(
                format: NSLocalizedString("paywall.subscribe", value: "Subscribe to %@", comment: ""),
                selectedTier.displayName
            ),
            style: .primary
        ) {
            showThankYou = true
        }
    }

    private var restoreButton: some View {
        Button {
            showThankYou = true
        } label: {
            Text(String(localized: "paywall.restore", defaultValue: "Restore Purchases"))
                .font(Typography.caption)
                .foregroundStyle(Color.folio.textSecondary)
        }
    }
}

// MARK: - Models

private enum SubscriptionTier: String, CaseIterable, Identifiable {
    case free, pro, proPlus

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .free: "Free"
        case .pro: "Pro"
        case .proPlus: "Pro+"
        }
    }

    var priceDescription: String {
        switch self {
        case .free: String(localized: "paywall.free.price", defaultValue: "30 articles / month")
        case .pro: String(localized: "paywall.pro.price", defaultValue: "$9.99 / year ($0.83/mo)")
        case .proPlus: String(localized: "paywall.proPlus.price", defaultValue: "$19.99 / year ($1.67/mo)")
        }
    }
}

private struct PaywallFeature: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let freeTier: Bool
    let proTier: Bool
    let proPlusTier: Bool

    static let allFeatures: [PaywallFeature] = [
        PaywallFeature(
            icon: "infinity",
            title: String(localized: "paywall.feat.unlimited", defaultValue: "Unlimited saves"),
            subtitle: String(localized: "paywall.feat.unlimited.sub", defaultValue: "No monthly limit"),
            freeTier: false, proTier: true, proPlusTier: true
        ),
        PaywallFeature(
            icon: "sparkles",
            title: String(localized: "paywall.feat.ai", defaultValue: "AI tags & summary"),
            subtitle: String(localized: "paywall.feat.ai.sub", defaultValue: "Auto-organize everything"),
            freeTier: false, proTier: true, proPlusTier: true
        ),
        PaywallFeature(
            icon: "brain.head.profile",
            title: String(localized: "paywall.feat.qa", defaultValue: "AI knowledge Q&A"),
            subtitle: String(localized: "paywall.feat.qa.sub", defaultValue: "Ask across all your articles"),
            freeTier: false, proTier: false, proPlusTier: true
        ),
        PaywallFeature(
            icon: "rectangle.stack",
            title: String(localized: "paywall.feat.topics", defaultValue: "Smart topics"),
            subtitle: String(localized: "paywall.feat.topics.sub", defaultValue: "Auto-generated collections"),
            freeTier: false, proTier: false, proPlusTier: true
        ),
        PaywallFeature(
            icon: "headphones",
            title: String(localized: "paywall.feat.podcast", defaultValue: "Daily podcast"),
            subtitle: String(localized: "paywall.feat.podcast.sub", defaultValue: "Audio digest of your saves"),
            freeTier: false, proTier: false, proPlusTier: true
        ),
        PaywallFeature(
            icon: "icloud",
            title: String(localized: "paywall.feat.icloud", defaultValue: "iCloud sync"),
            subtitle: String(localized: "paywall.feat.icloud.sub", defaultValue: "Seamless cross-device"),
            freeTier: false, proTier: false, proPlusTier: true
        ),
    ]
}

#Preview {
    NavigationStack {
        PaywallView()
    }
}
