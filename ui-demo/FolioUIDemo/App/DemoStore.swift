import Foundation
import Observation

@Observable
final class DemoStore {
    var isSignedIn = false
    var isSessionValid = true
    var accountEmail = "user@example.com"
    var selectedTab = DemoTab.library
    var path: [DemoRoute] = []
    var libraryFilter = DemoLibraryFilter.all
    var isOnline = true
    var isCapacityFull = false
    var shouldTimeoutNextCapture = false
    var shouldFailNextProcessing = false
    var authMessage: String?
    var activeNotice: DemoNotice?
    private(set) var articles: [DemoArticle]
    private(set) var pendingDeletion: DemoPendingDeletion?
    private(set) var deviceSessions: [DemoDeviceSession]
    private(set) var visibleArticleLimit = 8
    @ObservationIgnored private var processingTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var deletionDismissTask: Task<Void, Never>?

    var libraryArticles: [DemoArticle] {
        articles
    }

    var filteredArticles: [DemoArticle] {
        articles.filter { libraryFilter.includes($0.status) }
    }

    var visibleArticles: [DemoArticle] {
        Array(filteredArticles.prefix(visibleArticleLimit))
    }

    var canLoadMoreArticles: Bool {
        visibleArticles.count < filteredArticles.count
    }

    var storageDescription: String {
        isCapacityFull ? "1 GB / 1 GB" : "620 MB / 1 GB"
    }

    init(initialScreen: DemoScreen? = nil) {
        let shouldSeedLibrary = initialScreen != nil && initialScreen != .welcome
        articles = shouldSeedLibrary ? DemoContent.articles : []
        deviceSessions = [
            DemoDeviceSession(
                id: "current-iphone",
                name: "这台 iPhone",
                detail: "新加坡 · 当前设备",
                symbol: "iphone",
                isCurrent: true
            ),
            DemoDeviceSession(
                id: "macbook",
                name: "MacBook Air",
                detail: "广州 · 2 小时前",
                symbol: "laptopcomputer",
                isCurrent: false
            )
        ]

        guard let initialScreen else { return }

        switch initialScreen {
        case .welcome:
            break
        case .library:
            isSignedIn = true
        case .reader:
            isSignedIn = true
            path = [.reader]
        case .insight:
            isSignedIn = true
            path = [.insight]
        case .evidence:
            isSignedIn = true
            path = [.evidence]
        case .askHome:
            isSignedIn = true
            selectedTab = .ask
        case .askAnswer:
            isSignedIn = true
            selectedTab = .ask
            path = [.askAnswer]
        case .askInsufficient:
            isSignedIn = true
            selectedTab = .ask
            path = [.askInsufficient]
        case .shareSuccess:
            isSignedIn = true
            path = [.shareSuccess]
        case .settings:
            isSignedIn = true
            path = [.settings]
        }
    }

    func signIn(email: String? = nil) {
        if let email, !email.isEmpty {
            accountEmail = email
        }
        isSessionValid = true
        isSignedIn = true
        authMessage = nil
    }

    func signOut(message: String? = "已安全退出。重新登录后，云端资料仍会恢复。") {
        path.removeAll()
        selectedTab = .library
        isSignedIn = false
        authMessage = message
    }

    func expireSession() {
        isSessionValid = false
        signOut(message: "登录状态已失效。请重新登录后继续收藏。")
    }

    func selectTab(_ tab: DemoTab) {
        selectedTab = tab
        path.removeAll()
    }

    func open(_ route: DemoRoute) {
        path.append(route)
    }

    func openArticle(_ article: DemoArticle) {
        guard isOnline else {
            activeNotice = DemoNotice(
                title: "需要联网阅读",
                message: "Folio 的正文来自云端。恢复网络后即可继续阅读，现有内容不会丢失。"
            )
            return
        }
        open(.article(article))
    }

    func captureURL(_ url: URL) -> DemoCaptureResult {
        guard isSignedIn, isSessionValid else {
            return .failure(.sessionExpired)
        }
        guard isOnline else {
            return .failure(.offline)
        }
        guard !isCapacityFull else {
            return .failure(.capacityFull)
        }
        if shouldTimeoutNextCapture {
            shouldTimeoutNextCapture = false
            return .failure(.timeout)
        }

        if articles.contains(where: { normalizedKey(for: $0.url) == normalizedKey(for: url) }) {
            return .success(.duplicate(host: url.host() ?? "这个链接"))
        }

        let article = DemoArticle.capturedURL(url)
        let shouldFail = shouldFailNextProcessing
        shouldFailNextProcessing = false
        articles.insert(article, at: 0)
        libraryFilter = .all
        visibleArticleLimit = max(visibleArticleLimit, 8)
        scheduleProcessing(for: article.id, shouldFail: shouldFail)
        return .success(.accepted(host: url.host() ?? "链接"))
    }

    func selectFilter(_ filter: DemoLibraryFilter) {
        libraryFilter = filter
        visibleArticleLimit = 8
    }

    func loadMoreArticles() {
        visibleArticleLimit += 8
    }

    func refreshLibrary() async {
        try? await Task.sleep(for: .milliseconds(420))
        for article in articles where article.status == .accepted || article.status == .queued {
            transitionArticle(article.id, to: .processing)
        }
    }

    func retryArticle(_ article: DemoArticle) {
        transitionArticle(article.id, to: .queued)
        scheduleProcessing(for: article.id, shouldFail: false)
    }

    func deleteArticle(_ article: DemoArticle) {
        guard let index = articles.firstIndex(where: { $0.id == article.id }) else { return }
        processingTasks[article.id]?.cancel()
        processingTasks[article.id] = nil
        let removedArticle = articles.remove(at: index)
        pendingDeletion = DemoPendingDeletion(article: removedArticle, originalIndex: index)

        deletionDismissTask?.cancel()
        deletionDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.pendingDeletion = nil
        }
    }

    func undoDeletion() {
        guard let pendingDeletion else { return }
        deletionDismissTask?.cancel()
        let index = min(pendingDeletion.originalIndex, articles.endIndex)
        articles.insert(pendingDeletion.article, at: index)
        self.pendingDeletion = nil
    }

    func clearLibrary() {
        processingTasks.values.forEach { $0.cancel() }
        processingTasks.removeAll()
        articles.removeAll()
        pendingDeletion = nil
        libraryFilter = .all
        visibleArticleLimit = 8
    }

    func requestAccountDeletion() {
        clearLibrary()
        deviceSessions.removeAll { !$0.isCurrent }
        isSessionValid = false
        signOut(message: "账号已进入 7 天删除撤销期。此 UI Demo 没有删除真实云端数据。")
    }

    func revokeDevice(_ session: DemoDeviceSession) {
        guard !session.isCurrent else { return }
        deviceSessions.removeAll { $0.id == session.id }
        activeNotice = DemoNotice(
            title: "设备已退出",
            message: "\(session.name) 的会话已撤销，下次请求会要求重新登录。"
        )
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func reset() {
        path.removeAll()
        selectedTab = .library
    }

    private func scheduleProcessing(for articleID: UUID, shouldFail: Bool) {
        processingTasks[articleID]?.cancel()
        processingTasks[articleID] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            self?.transitionArticle(articleID, to: .queued)

            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.transitionArticle(articleID, to: .processing)

            try? await Task.sleep(for: .milliseconds(1_250))
            guard !Task.isCancelled else { return }
            self?.transitionArticle(articleID, to: shouldFail ? .failed : .ready)
            self?.processingTasks[articleID] = nil
        }
    }

    private func transitionArticle(_ articleID: UUID, to status: DemoArticleStatus) {
        guard let index = articles.firstIndex(where: { $0.id == articleID }) else { return }
        articles[index].status = status
        articles[index].age = "刚刚"
        articles[index].summary = summary(for: status)
    }

    private func summary(for status: DemoArticleStatus) -> String {
        switch status {
        case .accepted:
            "已接收 · 等待云端处理"
        case .queued:
            "等待处理 · 可以先离开"
        case .processing:
            "处理中 · 正在获取并整理正文"
        case .ready:
            "正文已保存 · 可以阅读"
        case .partial:
            "正文可读 · 洞察暂不可用"
        case .failed:
            "处理失败 · 原始链接仍然安全"
        }
    }

    private func normalizedKey(for url: URL?) -> String? {
        guard let url else { return nil }
        let host = url.host()?.lowercased() ?? ""
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(host)/\(path)"
    }
}
