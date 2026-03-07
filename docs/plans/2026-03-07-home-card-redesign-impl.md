# Home Card Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rewrite the home feed article cards to follow the Jobs-inspired "breathing list" design — title-dominant, minimal, with quiet status indicators and proper unread dots.

**Architecture:** Rewrite `ArticleCardView` with new layout (title top, summary 2 lines, source line bottom with favicon + category + status). Remove `DailyDigestCard` and `InsightCard` from feed. Simplify `StatusBadge` to inline trailing icons. Update `HomeView` to use the new cards.

**Tech Stack:** SwiftUI, SwiftData, Nuke (LazyImage for favicon), SF Symbols

---

### Task 1: Rewrite ArticleCardView

**Files:**
- Modify: `ios/Folio/Presentation/Home/ArticleCardView.swift` (full rewrite)

**Step 1: Write the new ArticleCardView**

Replace the entire file content with the new card layout. The new structure is:

```swift
import SwiftUI
import NukeUI

struct ArticleCardView: View {
    let article: Article
    var onRetry: (() -> Void)?

    private var isUnread: Bool {
        article.readProgress == 0 && article.status == .ready
    }

    private var isFailed: Bool {
        article.status == .failed
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            // Unread dot
            if isUnread {
                Circle()
                    .fill(Color.folio.unread)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6) // align with first line of title
                    .accessibilityLabel(Text(String(localized: "status.unread", defaultValue: "Unread")))
            }

            VStack(alignment: .leading, spacing: 0) {
                // Title
                Text(article.displayTitle)
                    .font(Typography.listTitle)
                    .foregroundStyle(isFailed ? Color.folio.textSecondary : Color.folio.textPrimary)
                    .lineLimit(2)

                // Summary
                if let summary = article.displaySummary {
                    Text(summary)
                        .font(Typography.body)
                        .foregroundStyle(Color.folio.textSecondary)
                        .lineLimit(2)
                        .padding(.top, Spacing.xxs)
                }

                // Source line
                sourceLine
                    .padding(.top, Spacing.xs)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Source Line

    private var sourceLine: some View {
        HStack(spacing: Spacing.xxs) {
            // Favicon
            faviconView

            // Source name
            if let siteName = article.siteName, !siteName.isEmpty {
                Text(siteName)
                    .font(Typography.tag)
                    .foregroundStyle(Color.folio.textTertiary)

                Text("\u{00B7}")
                    .foregroundStyle(Color.folio.textTertiary)
            }

            // Category
            if let category = article.category {
                Text(category.displayName)
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textTertiary)

                Text("\u{00B7}")
                    .foregroundStyle(Color.folio.textTertiary)
            }

            // Time
            Text(article.createdAt.relativeFormatted())
                .font(Typography.caption)
                .foregroundStyle(Color.folio.textTertiary)

            Spacer(minLength: 0)

            // Status icon (trailing)
            statusIcon

            // Favorite heart (trailing)
            if article.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.pink)
                    .accessibilityLabel(Text(String(localized: "status.favorited", defaultValue: "Favorited")))
            }
        }
    }

    // MARK: - Favicon

    @ViewBuilder
    private var faviconView: some View {
        if let faviconURL = article.faviconURL, let url = URL(string: faviconURL) {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    // Loading or failure: show SF Symbol fallback
                    sourceTypeIcon
                }
            }
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
        } else {
            sourceTypeIcon
        }
    }

    private var sourceTypeIcon: some View {
        Image(systemName: article.sourceType.iconName)
            .font(.system(size: 13))
            .foregroundStyle(Color.folio.textTertiary)
            .frame(width: 20, height: 20)
            .accessibilityLabel(article.sourceType.displayName)
    }

    // MARK: - Status Icon

    @ViewBuilder
    private var statusIcon: some View {
        switch article.status {
        case .processing:
            Image(systemName: "circle.dashed")
                .font(.system(size: 12))
                .foregroundStyle(Color.folio.warning)
                .symbolEffect(.variableColor.iterative)
                .accessibilityLabel(Text(String(localized: "status.processing", defaultValue: "Processing")))
        case .clientReady:
            Image(systemName: "doc.richtext")
                .font(.system(size: 12))
                .foregroundStyle(Color.folio.success)
                .accessibilityLabel(Text(String(localized: "status.clientReady", defaultValue: "Content ready")))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.folio.error)
                .accessibilityLabel(Text(String(localized: "status.failed", defaultValue: "Failed")))
        case .pending where article.syncState == .pendingUpload:
            Image(systemName: "arrow.up.icloud")
                .font(.system(size: 12))
                .foregroundStyle(Color.folio.textTertiary)
                .accessibilityLabel(Text(String(localized: "status.pendingSync", defaultValue: "Pending sync")))
        default:
            EmptyView()
        }
    }
}

#Preview("Standard") {
    List {
        ArticleCardView(article: {
            let a = Article(url: "https://example.com", title: "SwiftUI Best Practices for 2025", sourceType: .web)
            a.siteName = "Swift Blog"
            a.summary = "A comprehensive guide to modern SwiftUI patterns and architecture decisions that will change how you build apps."
            return a
        }())
        ArticleCardView(article: {
            let a = Article(url: "https://mp.weixin.qq.com/s/abc", title: "Deep Dive into Swift Concurrency", sourceType: .wechat)
            a.siteName = "SwiftGG"
            a.summary = "Understanding actors, async/await, and structured concurrency in Swift 5.9."
            a.statusRaw = ArticleStatus.processing.rawValue
            return a
        }())
        ArticleCardView(article: {
            let a = Article(url: "https://x.com/user/status/123", title: "Claude Code is amazing", sourceType: .twitter)
            a.siteName = "Yanhua on X"
            a.statusRaw = ArticleStatus.ready.rawValue
            a.isFavorite = true
            return a
        }())
        ArticleCardView(article: {
            let a = Article(url: "https://example.com/fail", title: "Failed Article", sourceType: .web)
            a.statusRaw = ArticleStatus.failed.rawValue
            a.fetchError = "Network timeout"
            return a
        }())
    }
    .listStyle(.plain)
}
```

**Step 2: Build and verify in Xcode preview**

Run: `cd /Users/mac/github/folio/ios && xcodegen generate && xcodebuild build -project Folio.xcodeproj -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add ios/Folio/Presentation/Home/ArticleCardView.swift
git commit -m "feat: rewrite ArticleCardView — title-dominant layout with unread dots, favicon, trailing status icons"
```

---

### Task 2: Update HomeView — Remove DailyDigest/Insight, Add Retry to Context Menu

**Files:**
- Modify: `ios/Folio/Presentation/Home/HomeView.swift:364-400` (articleList) and `ios/Folio/Presentation/Home/HomeView.swift:527-579` (articleContextMenu)
- Delete: `ios/Folio/Presentation/Home/DailyDigestCard.swift`
- Delete: `ios/Folio/Presentation/Home/InsightCard.swift`

**Step 1: Edit HomeView — remove DailyDigest and Insight from articleList**

In `HomeView.swift`, replace the `articleList` computed property (lines 365-401). Remove `DailyDigestCard()` and the `InsightCard` block. The list should only contain `statusBanners` and `articleSections`:

```swift
private var articleList: some View {
    List {
        statusBanners

        if let vm = viewModel {
            articleSections(vm: vm)
        }
    }
    .listStyle(.plain)
    .refreshable {
        if let syncService {
            await syncService.incrementalSync()
        }
        viewModel?.fetchArticles()
    }
    .task(id: articles.contains { $0.status == .processing || $0.status == .clientReady }) {
        guard articles.contains(where: { $0.status == .processing || $0.status == .clientReady }) else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { break }
            await syncService?.fetchProcessingArticles()
            viewModel?.fetchArticles()
        }
    }
    .background(Color.folio.background)
    .sheet(isPresented: $showShareSheet) {
        if let items = shareItems {
            ShareSheet(activityItems: items)
        }
    }
}
```

Also remove the `@State private var showInsight = true` property (line 20).

**Step 2: Edit articleContextMenu — add Retry as first item for failed articles**

Replace the `articleContextMenu` method. Add Retry button at the top, only shown for failed articles:

```swift
@ViewBuilder
private func articleContextMenu(article: Article, vm: HomeViewModel) -> some View {
    // Retry (only for failed articles)
    if article.status == .failed {
        Button {
            vm.retryArticle(article)
        } label: {
            Label(String(localized: "article.retry", defaultValue: "Retry"), systemImage: "arrow.clockwise")
        }

        Divider()
    }

    Button {
        vm.toggleFavorite(article)
    } label: {
        Label(
            article.isFavorite
                ? String(localized: "reader.unfavorite", defaultValue: "Remove Favorite")
                : String(localized: "reader.favorite", defaultValue: "Favorite"),
            systemImage: article.isFavorite ? "heart.fill" : "heart"
        )
    }

    Button {
        vm.archiveArticle(article)
    } label: {
        Label(
            article.isArchived
                ? String(localized: "reader.unarchive", defaultValue: "Unarchive")
                : String(localized: "reader.archive", defaultValue: "Archive"),
            systemImage: article.isArchived ? "archivebox.fill" : "archivebox"
        )
    }

    Button {
        if let url = URL(string: article.url) {
            shareItems = [url]
            showShareSheet = true
        }
    } label: {
        Label(String(localized: "reader.share", defaultValue: "Share"), systemImage: "square.and.arrow.up")
    }

    Button {
        UIPasteboard.general.string = article.url
        vm.showToast = false
        DispatchQueue.main.async {
            vm.toastMessage = String(localized: "home.article.linkCopied", defaultValue: "Link copied")
            vm.toastIcon = "doc.on.doc"
            vm.showToast = true
        }
    } label: {
        Label(String(localized: "home.article.copyLink", defaultValue: "Copy Link"), systemImage: "link")
    }

    Divider()

    Button(role: .destructive) {
        articleToDelete = article
        showDeleteConfirmation = true
    } label: {
        Label(String(localized: "reader.delete", defaultValue: "Delete"), systemImage: "trash")
    }
}
```

**Step 3: Delete DailyDigestCard.swift and InsightCard.swift**

```bash
rm ios/Folio/Presentation/Home/DailyDigestCard.swift
rm ios/Folio/Presentation/Home/InsightCard.swift
```

**Step 4: Regenerate Xcode project and build**

Run: `cd /Users/mac/github/folio/ios && xcodegen generate && xcodebuild build -project Folio.xcodeproj -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add -A ios/Folio/Presentation/Home/
git commit -m "feat: remove DailyDigest/Insight cards from feed, add Retry to context menu for failed articles"
```

---

### Task 3: Clean Up StatusBadge

The old `StatusBadge` was used as a leading badge in the old card. The new card uses inline status icons directly. Check if `StatusBadge` is used anywhere else. If not, delete it. If it is, leave it.

**Files:**
- Possibly delete: `ios/Folio/Presentation/Components/StatusBadge.swift`

**Step 1: Search for StatusBadge usage**

Run: `grep -r "StatusBadge" ios/Folio/ --include="*.swift" -l`

If only `ArticleCardView.swift` used it (and we already rewrote that), delete the file.

**Step 2: Delete if unused**

```bash
rm ios/Folio/Presentation/Components/StatusBadge.swift
```

**Step 3: Regenerate and build**

Run: `cd /Users/mac/github/folio/ios && xcodegen generate && xcodebuild build -project Folio.xcodeproj -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add -A ios/Folio/Presentation/Components/StatusBadge.swift
git commit -m "chore: remove unused StatusBadge component"
```

---

### Task 4: Visual Verification with Appium

**Files:** None (testing only)

**Step 1: Build and install on simulator**

Run: `xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/folio-build 2>&1 | tail -5`

Then install and launch:
```bash
xcrun simctl install booted /tmp/folio-build/Build/Products/Debug-iphonesimulator/Folio.app
xcrun simctl launch booted com.7WSH9CR7KS.folio.app
```

**Step 2: Take screenshot via Appium and verify**

```python
from appium import webdriver
from appium.options.ios import XCUITestOptions
import base64

options = XCUITestOptions()
options.platform_name = 'iOS'
options.device_name = 'iPhone 17 Pro'
options.udid = '7910EBEA-1F8E-47B3-9AF4-7A30F48407C9'
options.automation_name = 'XCUITest'
options.no_reset = True

driver = webdriver.Remote('http://127.0.0.1:4723', options=options)
screenshot = driver.get_screenshot_as_base64()
with open('/tmp/redesign_screenshot.png', 'wb') as f:
    f.write(base64.b64decode(screenshot))

source = driver.page_source
driver.quit()
print(source[:3000])
```

**Step 3: Verify the following in the screenshot/page source:**
- No DailyDigestCard or InsightCard visible
- Article titles are prominent (2 lines max)
- Summary text visible (2 lines max)
- Source line at bottom with favicon/icon, source name, time
- Unread dots visible on unread articles
- Status icons visible on processing/failed articles
- Favorite hearts visible on favorited articles
- Adequate spacing between cards

**Step 4: Commit with verification note**

```bash
git add -A
git commit -m "chore: visual verification complete — home card redesign"
```

---

### Task 5: Run Existing Tests

**Files:** None (test verification only)

**Step 1: Run all iOS tests to ensure nothing is broken**

Run: `xcodebuild test -project ios/Folio.xcodeproj -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E '(Test Suite|Tests|Executed|FAIL)'`

Expected: All tests pass. The HomeViewModel tests should still work since we didn't change the ViewModel.

**Step 2: If any tests reference DailyDigestCard or InsightCard, update them**

Search: `grep -r "DailyDigest\|InsightCard" ios/FolioTests/ --include="*.swift"`

If found, remove those test references.

**Step 3: If test fixes were needed, commit**

```bash
git add ios/FolioTests/
git commit -m "test: update tests for home card redesign"
```

---

## Summary of Changes

| Action | File |
|--------|------|
| Rewrite | `ios/Folio/Presentation/Home/ArticleCardView.swift` |
| Modify | `ios/Folio/Presentation/Home/HomeView.swift` |
| Delete | `ios/Folio/Presentation/Home/DailyDigestCard.swift` |
| Delete | `ios/Folio/Presentation/Home/InsightCard.swift` |
| Delete | `ios/Folio/Presentation/Components/StatusBadge.swift` (if unused) |
| Run | `cd ios && xcodegen generate` (after file changes) |

## What Is NOT Changed

- `HomeViewModel.swift` — no changes needed
- `EmptyStateView.swift` — unchanged
- `Article.swift` model — unchanged
- Design tokens (`Spacing`, `Typography`, `CornerRadius`, `Color+Folio`) — unchanged
- Swipe actions, navigation, pagination — unchanged
- Search functionality — unchanged
