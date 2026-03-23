import SwiftUI
import SwiftData

// MARK: - Export Data Models

private struct ExportArticle: Encodable {
    let title: String
    let url: String
    let summary: String
    let keyPoints: [String]
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case title, url, summary
        case keyPoints = "key_points"
        case createdAt = "created_at"
    }

    init(from article: Article) {
        self.title = article.displayTitle
        self.url = article.url ?? ""
        self.summary = article.summary ?? ""
        self.keyPoints = article.keyPoints
        self.createdAt = article.createdAt
    }
}

private struct ExportPayload: Encodable {
    let exportedAt: Date
    let articleCount: Int
    let articles: [ExportArticle]

    enum CodingKeys: String, CodingKey {
        case exportedAt = "exported_at"
        case articleCount = "article_count"
        case articles
    }
}

// MARK: - SettingsView (4-State)

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var authViewModel: AuthViewModel?
    @Environment(SubscriptionManager.self) private var subscriptionManager: SubscriptionManager?
    @Environment(\.modelContext) private var modelContext
    @State private var logoutTrigger = false
    @State private var showUpgradeComparison = false
    @State private var showReadingPreferences = false
    @State private var showExportShareSheet = false
    @State private var exportShareItems: [Any] = []

    /// Derived user state for cleaner branching.
    private enum UserState {
        case guest
        case free(UserDTO)
        case pro(UserDTO)
    }

    private var userState: UserState {
        guard let user = authViewModel?.currentUser,
              authViewModel?.isAuthenticated == true else {
            return .guest
        }
        return user.isPro ? .pro(user) : .free(user)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                switch userState {
                case .guest:
                    guestLoginPrompt
                    settingsSections(isPro: false, isGuest: true)
                case .free(let user):
                    profileCard(user: user, isPro: false)
                    proUpgradeCard
                    settingsSections(isPro: false, isGuest: false)
                    signOutButton
                case .pro(let user):
                    profileCard(user: user, isPro: true)
                    proInfoCard(user: user)
                    settingsSections(isPro: true, isGuest: false)
                    signOutButton
                }

                versionFooter

                #if DEBUG
                devToolsSection
                #endif
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.md)
        }
        .background(Color.folio.background)
        .sensoryFeedback(.impact(weight: .medium), trigger: logoutTrigger)
        .sheet(isPresented: $showUpgradeComparison) {
            UpgradeComparisonView()
        }
        .sheet(isPresented: $showReadingPreferences) {
            ReadingPreferenceView()
        }
        .sheet(isPresented: $showExportShareSheet) {
            ShareSheet(activityItems: exportShareItems)
        }
    }

    // MARK: - State 3: Guest Login Prompt

    private var guestLoginPrompt: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 56))
                .foregroundStyle(Color.folio.textQuaternary.opacity(0.5))
                .padding(.top, Spacing.lg)

            Text("登录以同步知识")
                .font(Typography.v3LoginPromptTitle)
                .foregroundStyle(Color.folio.textPrimary)

            Text("登录后可使用 AI 摘要、云端同步等全部功能")
                .font(.system(size: 13))
                .foregroundStyle(Color.folio.textSecondary)
                .multilineTextAlignment(.center)

            NavigationLink {
                SignInView()
            } label: {
                Text("登录 / 注册")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.folio.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.top, Spacing.xs)
        }
        .padding(Spacing.screenPadding)
        .background(Color.folio.echoBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Profile Card

    private func profileCard(user: UserDTO, isPro: Bool) -> some View {
        HStack(spacing: Spacing.sm) {
            // Avatar
            ZStack {
                Circle()
                    .fill(isPro ? Color.folio.accent : Color.folio.echoBg)
                    .frame(width: 52, height: 52)
                Text("F")
                    .font(.system(size: 20))
                    .foregroundStyle(isPro ? .white : Color.folio.textPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text(user.nickname ?? user.email ?? "User")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.folio.textPrimary)

                    // Badge
                    Text(isPro ? "PRO" : "FREE")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isPro ? .white : Color.folio.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isPro ? Color.folio.accent : Color.folio.echoBg)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                if let email = user.email {
                    Text(email)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.folio.textTertiary)
                }
            }

            Spacer()
        }
        .padding(Spacing.md)
        .background(Color.folio.echoBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - State 1: Pro Upgrade Card (Free User)

    private var proUpgradeCard: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("升级 Pro，解锁全部能力")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.folio.textPrimary)

            Text("每日 Echo · 无限问答 · 语义搜索 · 知识地图")
                .font(.system(size: 13))
                .foregroundStyle(Color.folio.textSecondary)

            Button {
                showUpgradeComparison = true
            } label: {
                Text("查看 Pro")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.folio.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.top, Spacing.xxs)
        }
        .padding(Spacing.screenPadding)
        .background(Color.folio.echoBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - State 2: Pro Info Card (Pro User)

    private func proInfoCard(user: UserDTO) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pro 订阅")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.folio.accent)

                if let expiresAt = user.subscriptionExpiresAt {
                    Text("有效期至 \(expiresAt.formatted(.dateTime.year().month().day())) · 自动续费")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.folio.textSecondary)
                } else {
                    Text("自动续费")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.folio.textSecondary)
                }
            }
            Spacer()
        }
        .padding(Spacing.md)
        .background(Color.folio.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Settings Sections

    @ViewBuilder
    private func settingsSections(isPro: Bool, isGuest: Bool) -> some View {
        if isGuest {
            // Guest: minimal — only reading preferences
            settingsSection(header: nil) {
                settingsRow(icon: "textformat.size", label: "阅读偏好") {
                    showReadingPreferences = true
                }
            }
        } else {
            // 通用
            settingsSection(header: "通用") {
                NavigationLink {
                    KnowledgeMapView()
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "map")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.folio.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(Color.folio.background)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        Text("知识地图")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.folio.textPrimary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.folio.textQuaternary)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
                sectionSeparator
                settingsRow(icon: "textformat.size", label: "阅读偏好") {
                    showReadingPreferences = true
                }
                sectionSeparator
                settingsRow(icon: "bell", label: "通知", value: "开启")
                // iCloud 同步已移除（使用后端同步）
            }

            if isPro {
                // 订阅
                settingsSection(header: "订阅") {
                    settingsRow(icon: "creditcard", label: "管理订阅")
                    sectionSeparator
                    settingsRow(icon: "arrow.clockwise", label: "恢复购买") {
                        Task { await subscriptionManager?.restorePurchases() }
                    }
                }
            }

            // 数据
            settingsSection(header: "数据") {
                settingsRow(
                    icon: "internaldrive",
                    label: "本地存储",
                    sublabel: isPro ? nil : "已使用 \(localStorageMB) MB / 1 GB"
                )
                sectionSeparator
                settingsRow(icon: "square.and.arrow.up", label: "导出数据") {
                    exportData()
                }
            }

            // 关于
            settingsSection(header: "关于") {
                settingsRow(icon: "hand.raised", label: "隐私政策")
                sectionSeparator
                settingsRow(icon: "doc.text", label: "服务条款")
            }
        }
    }

    // MARK: - Section Container

    private func settingsSection(header: String?, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header {
                Text(header)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.folio.textQuaternary)
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .padding(.bottom, Spacing.xs)
            }

            VStack(spacing: 0) {
                content()
            }
            .background(Color.folio.echoBg)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Settings Row

    private func settingsRow(
        icon: String,
        label: String,
        sublabel: String? = nil,
        value: String? = nil,
        valueColor: Color = Color.folio.textTertiary,
        isPlaceholder: Bool = false,
        action: (() -> Void)? = nil
    ) -> some View {
        Button {
            action?()
        } label: {
            HStack(spacing: Spacing.sm) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.folio.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Color.folio.background)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.folio.textPrimary)

                    if let sublabel {
                        Text(sublabel)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.folio.textTertiary)
                    }
                }

                Spacer()

                if let value {
                    Text(value)
                        .font(.system(size: 14))
                        .foregroundStyle(valueColor)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.folio.textQuaternary)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .opacity(isPlaceholder ? 0.5 : 1.0)
        .disabled(isPlaceholder)
    }

    private var sectionSeparator: some View {
        Rectangle()
            .fill(Color.folio.separator)
            .frame(height: 0.5)
            .padding(.leading, 56) // icon (28) + spacing (12) + padding (16)
    }

    // MARK: - Sign Out

    private var signOutButton: some View {
        Button {
            logoutTrigger.toggle()
            authViewModel?.signOut()
        } label: {
            Text("退出登录")
                .font(.system(size: 16))
                .foregroundStyle(Color.folio.error)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 14)
        }
    }

    // MARK: - Version Footer

    private var versionFooter: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return Text("Folio v\(version) (Build \(build))")
            .font(.system(size: 12))
            .foregroundStyle(Color.folio.textQuaternary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Export Data

    private func exportData() {
        let descriptor = FetchDescriptor<Article>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let articles = (try? modelContext.fetch(descriptor)) ?? []

        let payload = ExportPayload(
            exportedAt: Date(),
            articleCount: articles.count,
            articles: articles.map { ExportArticle(from: $0) }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("folio-export.json")
        try? data.write(to: tempURL)

        exportShareItems = [tempURL]
        showExportShareSheet = true
    }

    // MARK: - Local Storage

    private var localStorageMB: String {
        // Approximate SwiftData store size
        let fileManager = FileManager.default
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier
        ) else { return "0" }

        let storeURL = containerURL.appendingPathComponent("default.store")
        let size = (try? fileManager.attributesOfItem(atPath: storeURL.path)[.size] as? Int) ?? 0
        let mb = Double(size) / 1_048_576
        return String(format: "%.1f", mb)
    }

    // MARK: - Dev Tools

    #if DEBUG
    private var devToolsSection: some View {
        settingsSection(header: "DEV TOOLS") {
            Button {
                try? KeyChainManager.shared.clearTokens()
                authViewModel?.signOut()
            } label: {
                HStack {
                    Image(systemName: "key.slash")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.folio.error)
                        .frame(width: 28, height: 28)
                    Text("Clear Keychain")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.folio.error)
                    Spacer()
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)

            sectionSeparator

            Button {
                UserDefaults.standard.set(false, forKey: AppConstants.onboardingCompletedKey)
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.folio.warning)
                        .frame(width: 28, height: 28)
                    Text("Reset Onboarding")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.folio.warning)
                    Spacer()
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
        }
    }
    #endif
}

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

// MARK: - Previews

#Preview("Free User") {
    NavigationStack {
        SettingsView()
    }
}

#Preview("Upgrade Comparison") {
    UpgradeComparisonView()
}
