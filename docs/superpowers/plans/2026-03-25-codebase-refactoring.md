# Codebase Refactoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate accumulated tech debt (duplicated code, oversized files, fragmented interfaces) without changing any functional behavior.

**Architecture:** 5 sequential batches ordered by risk (low → high). Each batch is an independent commit with full test verification before proceeding.

**Tech Stack:** Swift/SwiftUI (iOS), Go (server), XcodeGen (project generation)

**Spec:** `docs/superpowers/specs/2026-03-25-codebase-refactoring-design.md`

---

## Task 1: Go Worker helpers — move to dedicated file

**Files:**
- Create: `server/internal/worker/helpers.go`
- Modify: `server/internal/worker/crawl_handler.go:365-386` (remove functions)

- [ ] **Step 1: Create `helpers.go` with the three functions**

```go
// server/internal/worker/helpers.go
package worker

// derefFloat returns the dereferenced float64 or 0 if the pointer is nil.
func derefFloat(f *float64) float64 {
	if f != nil {
		return *f
	}
	return 0
}

// derefOrEmpty returns the dereferenced string or "" if the pointer is nil.
func derefOrEmpty(s *string) string {
	if s != nil {
		return *s
	}
	return ""
}

// derefOrDefault returns the dereferenced string, or fallback if nil or empty.
func derefOrDefault(s *string, fallback string) string {
	if s != nil && *s != "" {
		return *s
	}
	return fallback
}
```

- [ ] **Step 2: Remove the three functions from `crawl_handler.go`**

Delete lines 364-386 of `crawl_handler.go` (the blank line before `derefFloat` through the end of `derefOrDefault`). Lines 387+ (blank line + Weibo section starting at line 388) remain untouched.

- [ ] **Step 3: Verify Go builds and tests pass**

Run: `cd server && go build ./... && go test ./internal/worker/... -v -count=1`
Expected: All tests pass, no compilation errors.

- [ ] **Step 4: Commit**

```
git add server/internal/worker/helpers.go server/internal/worker/crawl_handler.go
git commit -m "refactor: move worker helper functions to dedicated file"
```

---

## Task 2: SyncService duplicate comment + search key unification

**Files:**
- Modify: `ios/Folio/Data/Sync/SyncService.swift:393-394`
- Modify: `ios/Folio/Presentation/Home/HomeView.swift:280,286,301,305`

- [ ] **Step 1: Delete duplicate comment in SyncService**

In `ios/Folio/Data/Sync/SyncService.swift`, lines 393-394 are identical:
```
    /// Delete local synced articles whose serverID is not in the server's full article set.
    /// Delete local synced articles whose serverID is not in the server's full article set.
```
Delete one of the two lines so only one remains.

- [ ] **Step 2: Replace hardcoded search key in HomeView**

In `ios/Folio/Presentation/Home/HomeView.swift`:

Delete line 280:
```swift
    private static let recentSearchesKey = "recent_searches"
```

Replace all 3 references to `Self.recentSearchesKey` with `AppConstants.searchHistoryKey`:

Line 286: `UserDefaults.standard.stringArray(forKey: Self.recentSearchesKey)` → `UserDefaults.standard.stringArray(forKey: AppConstants.searchHistoryKey)`

Line 301: `UserDefaults.standard.stringArray(forKey: Self.recentSearchesKey)` → `UserDefaults.standard.stringArray(forKey: AppConstants.searchHistoryKey)`

Line 305: `UserDefaults.standard.set(recent, forKey: Self.recentSearchesKey)` → `UserDefaults.standard.set(recent, forKey: AppConstants.searchHistoryKey)`

- [ ] **Step 3: Verify iOS compiles**

Run: `xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```
git add ios/Folio/Data/Sync/SyncService.swift ios/Folio/Presentation/Home/HomeView.swift
git commit -m "refactor: fix duplicate comment, unify search history key to AppConstants"
```

---

## Task 3: Extract UpgradeComparisonView to its own file

**Files:**
- Create: `ios/Folio/Presentation/Settings/UpgradeComparisonView.swift`
- Modify: `ios/Folio/Presentation/Settings/SettingsView.swift:523-753`

- [ ] **Step 1: Create `UpgradeComparisonView.swift`**

Create `ios/Folio/Presentation/Settings/UpgradeComparisonView.swift` with the content from `SettingsView.swift` lines 524-753 (from `// MARK: - State 4: Upgrade Comparison View` through the end of the file including previews for UpgradeComparisonView).

Add the necessary imports at the top:
```swift
import SwiftUI
```

The file should include:
- `UpgradeComparisonView` struct (and its `comparisonTable`, `comparisonRow`, `comparisonValueView`, `ComparisonValue` enum, `ComparisonRow` struct, `comparisonRows` array)
- The `#Preview("Upgrade Comparison")` block

- [ ] **Step 2: Remove the moved code from SettingsView.swift**

Delete lines 524-741 (the `UpgradeComparisonView` struct and all its internals) and lines 751-753 (the `#Preview("Upgrade Comparison")` block). Keep lines 743-749 (the `#Preview("Free User")` block) — it stays in SettingsView.swift.

- [ ] **Step 3: Run xcodegen**

Run: `cd ios && xcodegen generate`
Expected: "⚙️  Generating plists..." and "Created project at..."

- [ ] **Step 4: Verify iOS compiles**

Run: `xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```
git add ios/Folio/Presentation/Settings/UpgradeComparisonView.swift ios/Folio/Presentation/Settings/SettingsView.swift ios/project.yml ios/Folio.xcodeproj
git commit -m "refactor: extract UpgradeComparisonView to its own file"
```

---

## Task 4: Merge Article toggle actions into generic helper

**Files:**
- Modify: `ios/Folio/Domain/Models/Article+Actions.swift`

- [ ] **Step 1: Add the generic `toggleBoolWithSync` private method**

Add this method inside the `extension Article` block, before the existing `toggleFavoriteWithSync`:

```swift
    /// Generic optimistic toggle + server sync pattern.
    @MainActor
    private func toggleBoolWithSync(
        toggle: () -> Void,
        makeRequest: () -> UpdateArticleRequest,
        toastOn: (String, String),
        toastOff: (String, String),
        getValue: () -> Bool,
        context: ModelContext,
        apiClient: APIClient,
        isAuthenticated: Bool,
        showToast: @escaping (String, String?) -> Void
    ) {
        toggle()
        markPendingUpdateIfNeeded()
        ModelContext.safeSave(context)

        let value = getValue()
        let toast = value ? toastOn : toastOff
        showToast(toast.0, toast.1)

        guard isAuthenticated, let serverID else { return }
        Task {
            do {
                try await apiClient.updateArticle(id: serverID, request: makeRequest())
                syncState = .synced
                ModelContext.safeSave(context)
            } catch {
                syncState = .pendingUpdate
                ModelContext.safeSave(context)
                showToast(
                    String(localized: "home.article.syncFailed", defaultValue: "Sync failed, will retry"),
                    "exclamationmark.icloud"
                )
            }
        }
    }
```

- [ ] **Step 2: Rewrite `toggleFavoriteWithSync` using the generic method**

Replace the entire existing `toggleFavoriteWithSync` method (lines 22-59) with:

```swift
    /// Toggle favorite with optimistic update and server sync.
    @MainActor
    func toggleFavoriteWithSync(
        context: ModelContext,
        apiClient: APIClient,
        isAuthenticated: Bool,
        showToast: @escaping (String, String?) -> Void
    ) {
        toggleBoolWithSync(
            toggle: { isFavorite.toggle() },
            makeRequest: { UpdateArticleRequest(isFavorite: isFavorite) },
            toastOn: (
                String(localized: "home.article.favorited", defaultValue: "Added to favorites"),
                "heart.fill"
            ),
            toastOff: (
                String(localized: "home.article.unfavorited", defaultValue: "Removed from favorites"),
                "heart"
            ),
            getValue: { isFavorite },
            context: context,
            apiClient: apiClient,
            isAuthenticated: isAuthenticated,
            showToast: showToast
        )
    }
```

- [ ] **Step 3: Rewrite `toggleArchiveWithSync` using the generic method**

Replace the entire existing `toggleArchiveWithSync` method (lines 61-99) with:

```swift
    /// Toggle archive with optimistic update and server sync.
    @MainActor
    func toggleArchiveWithSync(
        context: ModelContext,
        apiClient: APIClient,
        isAuthenticated: Bool,
        showToast: @escaping (String, String?) -> Void
    ) {
        toggleBoolWithSync(
            toggle: { isArchived.toggle() },
            makeRequest: { UpdateArticleRequest(isArchived: isArchived) },
            toastOn: (
                String(localized: "home.article.archived", defaultValue: "Archived"),
                "archivebox.fill"
            ),
            toastOff: (
                String(localized: "home.article.unarchived", defaultValue: "Unarchived"),
                "archivebox"
            ),
            getValue: { isArchived },
            context: context,
            apiClient: apiClient,
            isAuthenticated: isAuthenticated,
            showToast: showToast
        )
    }
```

- [ ] **Step 4: Verify iOS compiles and tests pass**

Run: `xcodebuild test -project ios/Folio.xcodeproj -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```
git add ios/Folio/Domain/Models/Article+Actions.swift
git commit -m "refactor: merge toggleFavorite/ArchiveWithSync into generic helper"
```

---

## Task 5: ReaderView menu dismiss helper

**Files:**
- Modify: `ios/Folio/Presentation/Reader/ReaderView.swift`

- [ ] **Step 1: Add `dismissMenuThen` helper**

Add this private method inside `ReaderView`, before the `readerMenuSheet` computed property (before line 510):

```swift
    private func dismissMenuThen(_ action: @escaping () -> Void) {
        showMoreMenu = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: action)
    }
```

- [ ] **Step 2: Replace all 6 occurrences in `readerMenuSheet`**

Replace each `showMoreMenu = false` / `DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { ... }` block with `dismissMenuThen { ... }`.

The 6 replacements in `readerMenuSheet` (lines 518-575):

1. Favorite toggle (line 519-522): `dismissMenuThen { viewModel?.toggleFavorite() }`
2. Copy Markdown (line 528-531): `dismissMenuThen { viewModel?.copyMarkdown() }`
3. Reading Preferences (line 537-540): `dismissMenuThen { showsReadingPreferences = true }`
4. Archive toggle (line 551-554): `dismissMenuThen { viewModel?.archiveArticle() }`
5. Open Original (line 561-564): `dismissMenuThen { openOriginal() }`
6. Delete (line 571-574): `dismissMenuThen { showsDeleteConfirmation = true }`

- [ ] **Step 3: Verify iOS compiles**

Run: `xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```
git add ios/Folio/Presentation/Reader/ReaderView.swift
git commit -m "refactor: extract dismissMenuThen helper in ReaderView"
```

---

## Task 6: DateFormatter static caching

**Files:**
- Modify: `ios/Folio/Presentation/Home/HomeView.swift:544-549`
- Modify: `ios/Folio/Presentation/Settings/KnowledgeMapView.swift:266-271`
- Modify: `ios/Folio/Presentation/Search/RAGAnswerView.swift:325-330`
- Modify: `ios/Folio/Utils/Extensions/Date+RelativeFormat.swift:34-43`

- [ ] **Step 1: Cache DateFormatter in HomeView**

In `HomeView.swift`, add a static formatter and rewrite `formattedDate()`:

Replace lines 544-549:
```swift
    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日，EEEE"
        return formatter.string(from: .now)
    }
```
With:
```swift
    private static let dateWeekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日，EEEE"
        return f
    }()

    private func formattedDate() -> String {
        Self.dateWeekdayFormatter.string(from: .now)
    }
```

- [ ] **Step 2: Cache DateFormatter in KnowledgeMapView**

In `KnowledgeMapView.swift`, replace lines 266-271:
```swift
    private var currentMonthLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月"
        return formatter.string(from: Date())
    }
```
With:
```swift
    private static let monthLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy 年 M 月"
        return f
    }()

    private var currentMonthLabel: String {
        Self.monthLabelFormatter.string(from: Date())
    }
```

- [ ] **Step 3: Cache DateFormatter in RAGAnswerView**

In `RAGAnswerView.swift`, replace lines 325-330:
```swift
    private func formatSourceDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "M\u{6708}d\u{65E5}\u{6536}\u{85CF}"
        return fmt.string(from: date)
    }
```
With:
```swift
    private static let sourceDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M\u{6708}d\u{65E5}\u{6536}\u{85CF}"
        return f
    }()

    private func formatSourceDate(_ date: Date) -> String {
        Self.sourceDateFormatter.string(from: date)
    }
```

- [ ] **Step 4: Cache DateFormatters in Date+RelativeFormat**

In `Date+RelativeFormat.swift`, replace lines 34-43:
```swift
        // Older — show absolute date
        let formatter = DateFormatter()
        let isChinese = locale.language.languageCode?.identifier == "zh"
        if calendar.component(.year, from: self) == calendar.component(.year, from: now) {
            formatter.dateFormat = isChinese ? "M月d日" : "MMM d"
        } else {
            formatter.dateFormat = isChinese ? "yyyy年M月d日" : "MMM d, yyyy"
        }
        formatter.locale = locale
        return formatter.string(from: self)
```
With:
```swift
        // Older — show absolute date
        let isChinese = locale.language.languageCode?.identifier == "zh"
        let sameYear = calendar.component(.year, from: self) == calendar.component(.year, from: now)
        let formatter: DateFormatter
        switch (isChinese, sameYear) {
        case (true, true):   formatter = Self.zhShortDate
        case (true, false):  formatter = Self.zhFullDate
        case (false, true):  formatter = Self.enShortDate
        case (false, false): formatter = Self.enFullDate
        }
        return formatter.string(from: self)
```

And add these static formatters inside the `extension Date` block (before the `relativeFormatted` function).
Note: The app only supports `en` and `zh-Hans` locales, so hardcoding `zh_CN`/`en_US` is acceptable. The original code dynamically set `formatter.locale = locale`, but since the format strings are locale-specific already (`"M月d日"` vs `"MMM d"`), the locale only affects minor details like month abbreviation style which is identical across `en_*` and `zh_*` variants for these formats.

```swift
    // Cached formatters for relative date display (app supports en + zh-Hans only)
    private static let zhShortDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f
    }()

    private static let zhFullDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f
    }()

    private static let enShortDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d"
        return f
    }()

    private static let enFullDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
```

- [ ] **Step 5: Verify iOS compiles and tests pass**

Run: `xcodebuild test -project ios/Folio.xcodeproj -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```
git add ios/Folio/Presentation/Home/HomeView.swift ios/Folio/Presentation/Settings/KnowledgeMapView.swift ios/Folio/Presentation/Search/RAGAnswerView.swift ios/Folio/Utils/Extensions/Date+RelativeFormat.swift
git commit -m "refactor: cache DateFormatter instances as static lets"
```

---

## Task 7: Extract ContentSaveService

**Files:**
- Create: `ios/Folio/Data/ContentSaveService.swift`
- Modify: `ios/Folio/Presentation/Home/HomeView.swift`

- [ ] **Step 1: Create ContentSaveService**

Create `ios/Folio/Data/ContentSaveService.swift`. Move the save logic from HomeView into this service. The service handles:
- Quota check (`SharedDataManager.canSave`)
- The actual SwiftData write
- `SharedDataManager.incrementQuota()`
- Fire-and-forget `syncService?.incrementalSync()`
- Returns a `SaveResult` for the caller to handle UI

The file should contain:
```swift
import Foundation
import SwiftData
import SwiftUI

@MainActor
final class ContentSaveService {
    private let context: ModelContext
    private let syncService: SyncService?

    init(context: ModelContext, syncService: SyncService?) {
        self.context = context
        self.syncService = syncService
    }

    enum SaveResult {
        case success(message: String, icon: String)
        case duplicate
        case quotaExceeded
        case error(message: String)
    }

    // MARK: - Save URL

    func saveURL(_ urlString: String) -> SaveResult {
        guard checkQuota() else { return .quotaExceeded }

        let manager = SharedDataManager(context: context)
        do {
            _ = try manager.saveArticleFromText(urlString)
            SharedDataManager.incrementQuota()
            triggerSync()
            return .success(
                message: String(localized: "home.addURL.saved", defaultValue: "Link saved"),
                icon: "checkmark.circle.fill"
            )
        } catch SharedDataError.duplicateURL {
            return .duplicate
        } catch {
            return .error(message: String(localized: "home.addURL.error", defaultValue: "Failed to save"))
        }
    }

    // MARK: - Save Manual Content

    func saveManualContent(_ content: String) -> SaveResult {
        guard checkQuota() else { return .quotaExceeded }

        let manager = SharedDataManager(context: context)
        do {
            _ = try manager.saveManualContent(content: content)
            SharedDataManager.incrementQuota()
            triggerSync()
            return .success(
                message: String(localized: "home.manualSaved", defaultValue: "Saved"),
                icon: "checkmark.circle.fill"
            )
        } catch {
            return .error(message: String(localized: "home.manualSaveError", defaultValue: "Failed to save"))
        }
    }

    // MARK: - Save Voice Note

    func saveVoiceNote(_ transcribedText: String) -> SaveResult {
        let trimmed = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .error(message: "Empty text") }
        guard checkQuota() else { return .quotaExceeded }

        let article = Article(url: nil, sourceType: .voice)
        article.markdownContent = trimmed
        let firstSentence = trimmed.components(separatedBy: CharacterSet(charactersIn: ".!?\u{3002}\u{FF01}\u{FF1F}")).first ?? trimmed
        let titleCandidate = String(firstSentence.prefix(40))
        article.title = titleCandidate.count < firstSentence.count ? titleCandidate + "..." : titleCandidate
        article.status = .clientReady
        article.wordCount = Article.countWords(trimmed)
        context.insert(article)
        do {
            try context.save()
            SharedDataManager.incrementQuota()
            triggerSync()
            return .success(
                message: String(localized: "home.voiceSaved", defaultValue: "Voice note saved"),
                icon: "checkmark.circle.fill"
            )
        } catch {
            return .error(message: String(localized: "home.voiceSaveError", defaultValue: "Failed to save"))
        }
    }

    // MARK: - Save Screenshot

    /// Saves the screenshot article synchronously. OCR runs in the background;
    /// `onOCRComplete` is called on MainActor when OCR finishes.
    func saveScreenshot(_ image: UIImage, onOCRComplete: @escaping () -> Void) -> SaveResult {
        guard checkQuota() else { return .quotaExceeded }

        let storageImage = Self.resizedImage(image, maxDimension: 1920)
        guard let storageData = storageImage.jpegData(compressionQuality: 0.8) else {
            return .error(message: String(localized: "home.screenshotError", defaultValue: "Failed to process image"))
        }

        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier
        ) else {
            return .error(message: String(localized: "home.screenshotError", defaultValue: "Failed to process image"))
        }

        let imagesDir = containerURL.appendingPathComponent("Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        let filename = UUID().uuidString + ".jpg"
        let fileURL = imagesDir.appendingPathComponent(filename)
        do {
            try storageData.write(to: fileURL)
        } catch {
            return .error(message: String(localized: "home.screenshotError", defaultValue: "Failed to process image"))
        }

        let relativePath = "Images/\(filename)"
        let article = Article(url: nil, sourceType: .screenshot)
        article.localImagePath = relativePath
        article.status = .clientReady
        context.insert(article)
        do {
            try context.save()
        } catch {
            return .error(message: String(localized: "home.screenshotError", defaultValue: "Failed to process image"))
        }

        SharedDataManager.incrementQuota()

        // Run OCR in background
        let ocrImage = Self.resizedImage(image, maxDimension: 1280)
        let articleID = article.id
        let context = self.context
        let syncService = self.syncService
        Task {
            let extractor = ImageOCRExtractor()
            if let text = try? await extractor.extract(from: ocrImage), !text.isEmpty {
                let descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.id == articleID })
                guard let article = try? context.fetch(descriptor).first else { return }
                article.markdownContent = text
                article.title = String(text.prefix(40)).components(separatedBy: .newlines).first ?? String(text.prefix(40))
                article.wordCount = Article.countWords(text)
                article.updatedAt = .now
                try? context.save()
                onOCRComplete()
            }
            await syncService?.incrementalSync()
        }

        return .success(
            message: String(localized: "home.screenshotSaved", defaultValue: "Screenshot saved"),
            icon: "checkmark.circle.fill"
        )
    }

    // MARK: - Private

    private func checkQuota() -> Bool {
        let isPro = UserDefaults.appGroup.bool(forKey: SharedDataManager.isProUserKey)
        return SharedDataManager.canSave(isPro: isPro)
    }

    private func triggerSync() {
        Task { await syncService?.incrementalSync() }
    }

    static func resizedImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard max(size.width, size.height) > maxDimension else { return image }
        let scale = maxDimension / max(size.width, size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
```

- [ ] **Step 2: Rewrite HomeView save methods to use ContentSaveService**

In `HomeView.swift`:

Add a `@State private var saveService: ContentSaveService?` property alongside the existing state vars.

Initialize it in `initializeViewModels()`:
```swift
if saveService == nil {
    saveService = ContentSaveService(context: modelContext, syncService: syncService)
}
```

Add a shared result handler:
```swift
private func handleSaveResult(_ result: ContentSaveService.SaveResult) {
    switch result {
    case .success(let message, let icon):
        showToast(message, icon: icon)
        saveSucceeded.toggle()
    case .duplicate:
        showToast(String(localized: "home.addURL.duplicate", defaultValue: "Link already exists"), icon: "exclamationmark.triangle.fill")
        saveFailed.toggle()
    case .quotaExceeded:
        showToast(String(localized: "home.quotaExceeded", defaultValue: "Monthly quota exceeded"), icon: "exclamationmark.triangle.fill")
        saveFailed.toggle()
    case .error(let message):
        showToast(message, icon: "xmark.circle.fill")
        saveFailed.toggle()
    }
}
```

Replace the 4 save methods (`saveURL`, `saveManualContent`, `saveScreenshot`, `saveVoiceNote`) with:

```swift
private func saveURL(_ urlString: String) {
    guard let result = saveService?.saveURL(urlString) else { return }
    handleSaveResult(result)
    if case .success = result { viewModel?.fetchArticles() }
}

private func saveManualContent(_ content: String) {
    guard let result = saveService?.saveManualContent(content) else { return }
    handleSaveResult(result)
    if case .success = result { viewModel?.fetchArticles() }
}

private func saveScreenshot(_ image: UIImage) {
    guard let result = saveService?.saveScreenshot(image, onOCRComplete: {
        viewModel?.fetchArticles()
    }) else { return }
    handleSaveResult(result)
    if case .success = result { viewModel?.fetchArticles() }
}

private func saveVoiceNote(_ transcribedText: String) {
    guard let result = saveService?.saveVoiceNote(transcribedText) else { return }
    handleSaveResult(result)
    if case .success = result { viewModel?.fetchArticles() }
}
```

Also delete the `resizedImage` static method from HomeView (it's now in ContentSaveService).

- [ ] **Step 3: Run xcodegen, verify compiles and tests**

Run: `cd ios && xcodegen generate && cd .. && xcodebuild test -project ios/Folio.xcodeproj -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -20`

- [ ] **Step 4: Commit**

```
git add ios/Folio/Data/ContentSaveService.swift ios/Folio/Presentation/Home/HomeView.swift ios/project.yml ios/Folio.xcodeproj
git commit -m "refactor: extract ContentSaveService from HomeView save methods"
```

---

## Task 8: Extract HomeSearchView and SearchSuggestionsView

**Files:**
- Create: `ios/Folio/Presentation/Home/HomeSearchView.swift`
- Create: `ios/Folio/Presentation/Home/SearchSuggestionsView.swift`
- Modify: `ios/Folio/Presentation/Home/HomeView.swift`

- [ ] **Step 1: Create HomeSearchView**

Create `ios/Folio/Presentation/Home/HomeSearchView.swift` by extracting the `searchContent` computed property (HomeView lines 178-276) into its own View. Include the search bar UI and the RAG/FTS branching logic. The view takes bindings and callbacks from HomeView.

```swift
import SwiftUI
import SwiftData

struct HomeSearchView: View {
    @Binding var searchText: String
    let viewModel: HomeViewModel
    let searchViewModel: SearchViewModel?
    let onDismiss: () -> Void
    let onSaveURL: (String) -> Void
    let onSaveNote: (String) -> Void
    let findExistingArticle: (String) -> Article?
    @Environment(\.selectArticle) private var selectArticle

    var body: some View {
        // Paste the full body of HomeView's searchContent here,
        // replacing viewModel? with viewModel (it's non-optional here),
        // and replacing isSearchActive = false with onDismiss()
    }
}
```

Move the `handleSearchTextChange` logic into HomeSearchView as a private method (or keep it in HomeView and pass it as a callback — implementer's choice based on cleanliness).

- [ ] **Step 2: Create SearchSuggestionsView**

Create `ios/Folio/Presentation/Home/SearchSuggestionsView.swift` by extracting `searchSuggestionsContent` (HomeView lines 309-406) and `quickActionCard` into its own View.

```swift
import SwiftUI

struct SearchSuggestionsView: View {
    @Binding var searchText: String
    let recentSearches: [String]
    let onShowNoteSheet: () -> Void

    // Move suggestedQuestions here
    private var suggestedQuestions: [String] { ... }

    var body: some View {
        // Paste the full body of HomeView's searchSuggestionsContent
    }

    // Move quickActionCard here
    private func quickActionCard(...) -> some View { ... }
}
```

- [ ] **Step 3: Update HomeView to use the new views**

In HomeView, replace the `searchContent` computed property body with:
```swift
HomeSearchView(
    searchText: $searchText,
    viewModel: viewModel!,  // safe: only called when viewModel != nil
    searchViewModel: searchViewModel,
    onDismiss: {
        searchText = ""
        viewModel?.clearRAG()
        isSearchActive = false
    },
    onSaveURL: { url in saveURL(url) },
    onSaveNote: { content in
        noteSheetText = content
        showNoteSheet = true
    },
    findExistingArticle: findExistingArticle
)
```

Remove the extracted computed properties and helper methods from HomeView: `searchContent`, `searchSuggestionsContent`, `quickActionCard`, `suggestedQuestions`. Keep `recentSearches`, `saveRecentSearch`, and `handleSearchTextChange` in HomeView if HomeSearchView needs them via callback, or move them if self-contained.

- [ ] **Step 4: Run xcodegen, verify compiles and tests**

Run: `cd ios && xcodegen generate && cd .. && xcodebuild test -project ios/Folio.xcodeproj -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -20`

- [ ] **Step 5: Commit**

```
git add ios/Folio/Presentation/Home/HomeSearchView.swift ios/Folio/Presentation/Home/SearchSuggestionsView.swift ios/Folio/Presentation/Home/HomeView.swift ios/project.yml ios/Folio.xcodeproj
git commit -m "refactor: extract HomeSearchView and SearchSuggestionsView from HomeView"
```

---

## Task 9: Go Worker shared interfaces

**Files:**
- Create: `server/internal/worker/interfaces.go`
- Modify: `server/internal/worker/crawl_handler.go` (remove private interfaces)
- Modify: `server/internal/worker/ai_handler.go` (remove private interfaces, change categoryRepo type)
- Modify: `server/internal/worker/echo_handler.go` (change articleRepo type)
- Modify: `server/internal/worker/relate_handler.go` (change articleRepo type)
- Modify: `server/internal/worker/image_handler.go` (change from concrete to interface)

- [ ] **Step 1: Create `interfaces.go` with building-block interfaces**

Create `server/internal/worker/interfaces.go` with all the shared interfaces from the spec (see spec section 4.3). Include proper imports for `context`, `domain`, `repository`, `asynq`.

- [ ] **Step 2: Update CrawlHandler**

In `crawl_handler.go`:
- Remove the 7 private interface definitions at the top (lines 19-60): `scraper` stays (it's CrawlHandler-specific), but remove `crawlArticleRepo`, `crawlTaskRepo`, `crawlEnqueuer`, `crawlContentCacheRepo`, `crawlTagRepo`, `crawlCategoryRepo`.
- Update `CrawlHandler` struct field types to use the shared interfaces:
  - `articleRepo` → `interface { ArticleGetter; ArticleCrawlUpdater; ArticleAIUpdater; ArticleStatusUpdater }`
  - `taskRepo` → `interface { TaskCrawlTracker; TaskAIFinisher; TaskFailer }` (note: CrawlHandler calls `SetAIFinished` but NOT `SetAIStarted`)
  - `asynqClient` → `Enqueuer`
  - `cacheRepo` → `ContentCacheReader`
  - `tagRepo` → `TagCreator`
  - `categoryRepo` → `CategoryFinder`

- [ ] **Step 3: Update AIHandler**

In `ai_handler.go`:
- Remove the 5 private interface definitions: `analyzer` stays, remove `aiArticleRepo`, `aiTaskRepo`, `aiTagRepo`, `aiContentCacheRepo`, `aiEnqueuer`.
- Update `AIHandler` struct field types:
  - `articleRepo` → `interface { ArticleGetter; ArticleAIUpdater; ArticleTitleUpdater; ArticleStatusUpdater }`
  - `taskRepo` → `interface { TaskAIStarter; TaskAIFinisher; TaskFailer }`
  - `categoryRepo` → `CategoryFinder` (was concrete `*repository.CategoryRepo`)
  - `tagRepo` → `TagCreator`
  - `cacheRepo` → `ContentCacheWriter`
  - `asynqClient` → `Enqueuer`

- [ ] **Step 4: Update EchoHandler**

In `echo_handler.go`:
- Remove `echoArticleRepo` interface definition (line 17-19).
- Change `articleRepo` field type from `echoArticleRepo` to `ArticleGetter`.
- Keep `echoCardRepo`, `echoCardGenerator`, `echoHighlightRepo` as-is (they are EchoHandler-specific).

- [ ] **Step 5: Update RelateHandler**

In `relate_handler.go`:
- Remove `relateArticleRepo` interface definition (line 17-19).
- Change `articleRepo` field type from `relateArticleRepo` to `ArticleGetter`.
- Keep `relateRAGRepo`, `relateSelector`, `relateRelationRepo` as-is.

- [ ] **Step 6: Update ImageHandler**

In `image_handler.go`:
- Add a private interface for the two methods ImageHandler needs:
```go
type imageArticleRepo interface {
    ArticleGetter
    UpdateMarkdownContent(ctx context.Context, id string, markdown string) error
}
```
- Change `articleRepo` field type from `*repository.ArticleRepo` to `imageArticleRepo`.

Note: `PushHandler` is omitted from this task — its `pushDeviceRepo` interface has no overlapping methods with other handlers, so there's nothing to consolidate.

- [ ] **Step 7: Update test mocks if needed**

Check `crawl_handler_test.go` and `ai_handler_test.go`: the mock structs should already implement all the methods in the new composed interfaces (same method set, just different interface names). If any compilation error arises because a mock implements the old named interface, update the mock type assertions.

- [ ] **Step 8: Verify Go builds and all tests pass**

Run: `cd server && go build ./... && go test ./internal/worker/... -v -count=1`
Expected: All tests pass.

- [ ] **Step 9: Commit**

```
git add server/internal/worker/
git commit -m "refactor: unify Go worker interfaces with ISP-compliant building blocks"
```

---

## Task 10: iOS SourceType.detect — add newsletter sources

**Files:**
- Modify: `ios/Folio/Domain/Models/Article.swift:40-59`

- [ ] **Step 1: Add substack/mailchimp detection**

In `Article.swift`, inside `SourceType.detect(from:)`, add a new branch before the final `else`:

Replace:
```swift
        } else if host.contains("youtube.com") || host.contains("youtu.be") {
            return .youtube
        } else {
            return .web
        }
```
With:
```swift
        } else if host.contains("youtube.com") || host.contains("youtu.be") {
            return .youtube
        } else if host.contains("substack.com") || host.contains("mailchi.mp") {
            return .newsletter
        } else {
            return .web
        }
```

- [ ] **Step 2: Verify iOS compiles**

Run: `xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet`

- [ ] **Step 3: Commit**

```
git add ios/Folio/Domain/Models/Article.swift
git commit -m "refactor: add substack/mailchimp to iOS SourceType detection (match Go server)"
```

---

## Task 11: Clean up TODOs — milestone upgrade + RAG source navigation

**Files:**
- Modify: `ios/Folio/Presentation/Home/MilestoneCardView.swift`
- Modify: `ios/Folio/Presentation/Home/HomeView.swift` (or `HomeSearchView.swift` if extracted)

- [ ] **Step 1: Implement milestone upgrade navigation**

In `MilestoneCardView.swift`, add state and sheet:

Add property: `@State private var showUpgrade = false`

Replace lines 67-68:
```swift
                Button {
                    // TODO: Navigate to upgrade
                } label: {
```
With:
```swift
                Button {
                    showUpgrade = true
                } label: {
```

Add `.sheet` modifier to the outer VStack (after `.padding(.vertical, 8)` on line 84):
```swift
        .sheet(isPresented: $showUpgrade) {
            UpgradeComparisonView()
        }
```

- [ ] **Step 2: Implement RAG source article navigation**

In the file containing the RAG `onSourceTap` callback (HomeView or HomeSearchView after Task 8), replace:
```swift
onSourceTap: { articleId in
    // TODO: Navigate to reader for this article
},
```
With:
```swift
onSourceTap: { articleId in
    let repo = ArticleRepository(context: modelContext)
    if let article = try? repo.fetchByServerID(articleId) {
        selectArticle(article)
    }
},
```

- [ ] **Step 3: Verify iOS compiles**

Run: `xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet`

- [ ] **Step 4: Commit**

```
git add ios/Folio/Presentation/Home/MilestoneCardView.swift ios/Folio/Presentation/Home/HomeView.swift
git commit -m "refactor: implement milestone upgrade navigation and RAG source article tap"
```

---

## Task 12: Final verification

- [ ] **Step 1: Run full iOS test suite**

Run: `xcodebuild test -project ios/Folio.xcodeproj -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -30`
Expected: All tests pass.

- [ ] **Step 2: Run full Go test suite**

Run: `cd server && go test ./... -count=1 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 3: Run E2E tests**

Run: `cd server && ./scripts/run_e2e.sh`
Expected: All E2E tests pass.

- [ ] **Step 4: Verify line count improvements**

Run:
```bash
wc -l ios/Folio/Presentation/Home/HomeView.swift
wc -l ios/Folio/Presentation/Settings/SettingsView.swift
wc -l ios/Folio/Domain/Models/Article+Actions.swift
wc -l server/internal/worker/crawl_handler.go
```
Expected: HomeView ~350 lines (was 865), SettingsView ~520 (was 753), Article+Actions smaller, crawl_handler ~440 (was 484).
