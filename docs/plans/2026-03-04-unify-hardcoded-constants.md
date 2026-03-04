# Unify Hardcoded Constants Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 消除 iOS 代码库中所有跨模块硬编码字符串，统一为共享常量，防止隐蔽的 key 不一致 bug。

**Architecture:** 创建集中的常量定义文件，放在 `ios/Shared/Constants/` 目录（App 和 Share Extension 均可访问），然后逐模块替换硬编码引用。每个 Task 独立可编译、可提交。

**Tech Stack:** Swift / SwiftUI / SwiftData / XcodeGen

---

## 背景

代码审查发现多处"同一字符串在多个文件中手打"的模式，这是 `"folio.isPro"` vs `"is_pro_user"` bug 的同类问题。以下是完整清单：

| 字符串 | 硬编码次数 | 风险级别 |
|--------|-----------|---------|
| `"group.com.folio.app"` | 7 处 / 6 文件 | Critical |
| `"hasCompletedOnboarding"` | 3 处 / 3 文件 | Critical |
| `reader_fontSize` 等 4 个阅读偏好 key | 22 处 / 3 文件 | Important |
| `statusRaw == "ready"` 等枚举比较 | 2 处 / 2 文件 | Important |
| `"folio_search_history"` 测试中硬编码 | 3 处 / 1 文件 | Important |

---

## Task 1: 创建共享常量文件 + 统一 App Group identifier

**Files:**
- Create: `ios/Shared/Constants/AppConstants.swift`
- Modify: `ios/Folio/App/FolioApp.swift`
- Modify: `ios/Folio/Data/SwiftData/DataManager.swift`
- Modify: `ios/Folio/Data/SwiftData/SharedDataManager.swift`
- Modify: `ios/ShareExtension/ShareViewController.swift`
- Modify: `ios/FolioTests/Data/DataManagerTests.swift`
- Modify: `ios/project.yml`（确认 Shared/ 在两个 target 中都包含）

**Step 1: 创建 `ios/Shared/Constants/AppConstants.swift`**

```swift
import Foundation

enum AppConstants {
    /// App Group identifier，App 和 Share Extension 共享数据的唯一通道。
    /// 修改此值必须同步更新 Folio.entitlements 和 ShareExtension.entitlements。
    static let appGroupIdentifier = "group.com.folio.app"

    /// Keychain service name
    static let keychainServiceName = "com.folio.app"
}
```

**Step 2: 全局替换 `"group.com.folio.app"` 为 `AppConstants.appGroupIdentifier`**

涉及 6 个文件共 7 处：

`FolioApp.swift`:
```swift
// 第 18 行和第 22 行
containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier)
groupContainer: .identifier(AppConstants.appGroupIdentifier)
```

`DataManager.swift`:
```swift
// 约第 24 行
groupContainer: .identifier(AppConstants.appGroupIdentifier)
```

`SharedDataManager.swift`:
```swift
// 约第 141 行
UserDefaults(suiteName: AppConstants.appGroupIdentifier) ?? .standard
```

`ShareViewController.swift`:
```swift
// 约第 59 行和第 61 行
containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier)
groupContainer: .identifier(AppConstants.appGroupIdentifier)
```

`DataManagerTests.swift`:
```swift
// 约第 61 行
containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier)
```

**Step 3: 确认 project.yml 中 Shared/ 目录被 App 和 ShareExtension 两个 target 引用**

读取 `ios/project.yml`，确认 `Shared/` 路径出现在两个 target 的 sources 中。如果 `Constants/` 是新子目录，XcodeGen 应自动发现（因为 Shared/ 已经在 sources 中）。

**Step 4: XcodeGen 重新生成项目**

```bash
cd ios && xcodegen generate
```

**Step 5: 编译验证**

```bash
xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet
```

**Step 6: 添加契约测试**

在 `ios/FolioTests/Data/DataManagerTests.swift` 中添加：

```swift
func testAppGroupIdentifier_matchesEntitlement() {
    // 验证常量与实际 App Group 一致（可访问）
    let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
    XCTAssertNotNil(defaults, "App Group identifier must be valid")
}
```

**Step 7: Commit**

```bash
git add ios/Shared/Constants/AppConstants.swift \
        ios/Folio/App/FolioApp.swift \
        ios/Folio/Data/SwiftData/DataManager.swift \
        ios/Folio/Data/SwiftData/SharedDataManager.swift \
        ios/ShareExtension/ShareViewController.swift \
        ios/FolioTests/Data/DataManagerTests.swift \
        ios/project.yml ios/Folio.xcodeproj
git commit -m "refactor: extract App Group identifier to shared constant

Replaces 7 hardcoded occurrences of 'group.com.folio.app' across 6 files
with AppConstants.appGroupIdentifier. This is the communication bridge
between the main app and Share Extension — any mismatch would silently
break article saving and quota sync."
```

---

## Task 2: 统一 `hasCompletedOnboarding` key

**Files:**
- Modify: `ios/Shared/Constants/AppConstants.swift`
- Modify: `ios/Folio/App/FolioApp.swift`
- Modify: `ios/Folio/Presentation/Onboarding/OnboardingView.swift`
- Modify: `ios/Folio/Presentation/Settings/SettingsView.swift`

**Step 1: 在 AppConstants 中添加 key**

```swift
enum AppConstants {
    // ... existing ...

    /// Onboarding 完成状态 key（UserDefaults.standard）
    static let onboardingCompletedKey = "hasCompletedOnboarding"
}
```

**Step 2: 替换 3 处硬编码**

`FolioApp.swift`:
```swift
@AppStorage(AppConstants.onboardingCompletedKey) private var hasCompletedOnboarding = false
```

`OnboardingView.swift`:
```swift
@AppStorage(AppConstants.onboardingCompletedKey) private var hasCompletedOnboarding = false
```

`SettingsView.swift`:
```swift
UserDefaults.standard.set(false, forKey: AppConstants.onboardingCompletedKey)
```

**Step 3: 编译验证 + Commit**

```bash
xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet
git add ios/Shared/Constants/AppConstants.swift \
        ios/Folio/App/FolioApp.swift \
        ios/Folio/Presentation/Onboarding/OnboardingView.swift \
        ios/Folio/Presentation/Settings/SettingsView.swift
git commit -m "refactor: unify onboarding key to shared constant

Replaces 3 hardcoded 'hasCompletedOnboarding' across FolioApp,
OnboardingView, and SettingsView with AppConstants.onboardingCompletedKey."
```

---

## Task 3: 统一阅读偏好 key（4 个 key，22 处）

**Files:**
- Create: `ios/Shared/Constants/ReadingPreferenceKeys.swift`
- Modify: `ios/Folio/Presentation/Reader/ReaderView.swift`
- Modify: `ios/Folio/Presentation/Reader/ReadingPreferenceView.swift`
- Modify: `ios/FolioTests/Reader/ReadingPreferenceTests.swift`（如存在）

**Step 1: 创建常量文件**

```swift
import Foundation

enum ReadingPreferenceKeys {
    static let fontSize = "reader_fontSize"
    static let lineSpacing = "reader_lineSpacing"
    static let theme = "reader_theme"
    static let fontFamily = "reader_fontFamily"
}
```

**Step 2: 替换 ReaderView.swift 和 ReadingPreferenceView.swift 中的 @AppStorage**

```swift
// 将
@AppStorage("reader_fontSize") var fontSize: Double = 17
// 改为
@AppStorage(ReadingPreferenceKeys.fontSize) var fontSize: Double = 17
```

4 个 key × 2 个文件 = 8 处。

**Step 3: 替换测试中的硬编码**

读取测试文件，将所有 `forKey: "reader_fontSize"` 等替换为 `forKey: ReadingPreferenceKeys.fontSize`。

**Step 4: XcodeGen + 编译 + Commit**

```bash
cd ios && xcodegen generate
xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet
git add ios/Shared/Constants/ReadingPreferenceKeys.swift \
        ios/Folio/Presentation/Reader/ \
        ios/FolioTests/Reader/ \
        ios/project.yml ios/Folio.xcodeproj
git commit -m "refactor: extract reading preference keys to shared constants

Replaces 22 hardcoded occurrences of reader_fontSize, reader_lineSpacing,
reader_theme, reader_fontFamily across ReaderView, ReadingPreferenceView,
and tests with ReadingPreferenceKeys constants."
```

---

## Task 4: 修复 statusRaw 硬编码比较

**Files:**
- Modify: `ios/Folio/Presentation/Search/SearchViewModel.swift`
- Modify: `ios/Folio/Presentation/Home/HomeViewModel.swift`

**Step 1: 修复 SearchViewModel.swift 中的 `refreshSyncedCount`**

读取文件找到硬编码的 `"ready"` 和 `"clientReady"`，改为通过枚举 rawValue：

```swift
func refreshSyncedCount(context: ModelContext) {
    let readyRaw = ArticleStatus.ready.rawValue
    let clientReadyRaw = ArticleStatus.clientReady.rawValue
    let descriptor = FetchDescriptor<Article>(
        predicate: #Predicate<Article> { article in
            article.statusRaw == readyRaw || article.statusRaw == clientReadyRaw
        }
    )
    syncedArticleCount = (try? context.fetchCount(descriptor)) ?? 0
}
```

这与 OfflineQueueManager 中的已有正确模式一致。

**Step 2: 修复 HomeViewModel.swift 中的 DTO status 比较**

读取文件找到 `dto.status == "ready"` 等，改为：

```swift
if dto.status == ArticleStatus.ready.rawValue && article.markdownContent == nil {
```

**Step 3: 编译 + Commit**

```bash
xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet
git add ios/Folio/Presentation/Search/SearchViewModel.swift \
        ios/Folio/Presentation/Home/HomeViewModel.swift
git commit -m "fix: replace hardcoded statusRaw strings with enum rawValue

Uses ArticleStatus.ready.rawValue instead of \"ready\" in #Predicate
and DTO comparisons, matching the pattern already used in
OfflineQueueManager and ArticleRepository."
```

---

## Task 5: 修复测试中的硬编码 key + 补充契约测试

**Files:**
- Modify: `ios/FolioTests/ViewModels/SearchViewModelTests.swift`
- Modify: `ios/FolioTests/Data/SharedDataManagerTests.swift`（如需要）

**Step 1: 修复 SearchViewModelTests 中硬编码的 history key**

读取文件，将 `"folio_search_history"` 替换为从源码引用的常量。
由于 `SearchViewModel.historyKey` 是 `private static`，需要先检查是否可以通过 `@testable import` 访问。如果不行，有两个方案：
- 方案 A：将 `historyKey` 的访问级别改为 `internal static`（去掉 `private`）
- 方案 B：在测试中使用与源码相同的字符串并加注释说明来源

优先选方案 A（更安全）。

**Step 2: 运行全量测试**

```bash
xcodebuild test -project ios/Folio.xcodeproj -scheme Folio \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "(passed|failed)" | tail -5
```

**Step 3: Commit**

```bash
git add ios/FolioTests/ ios/Folio/Presentation/Search/SearchViewModel.swift
git commit -m "test: replace hardcoded keys in tests with source constants

Tests now reference the same constants as production code, ensuring
key renames are caught immediately by compilation errors rather than
silent test failures."
```

---

## 验收标准

| Task | 验收条件 |
|------|----------|
| T1 | `grep -r '"group.com.folio.app"' ios/` 只在 `AppConstants.swift` 和 entitlements 文件中出现 |
| T2 | `grep -r '"hasCompletedOnboarding"' ios/` 只在 `AppConstants.swift` 中出现 |
| T3 | `grep -r '"reader_' ios/` 只在 `ReadingPreferenceKeys.swift` 中出现 |
| T4 | `grep -rn 'statusRaw ==' ios/Folio/` 所有匹配行都使用 `.rawValue` 变量，无硬编码字符串 |
| T5 | `grep -r '"folio_search_history"' ios/` 只在 `SearchViewModel.swift` 常量定义处出现 |
| 全局 | `xcodebuild build` 两个 target 均通过，`xcodebuild test` 全部绿色 |

---

## 不做的事

- **不抽取 API 路径常量**：已集中在 APIClient 内部，无跨文件硬编码风险
- **不抽取 Keychain key**：已正确使用 `private enum Keys`，无需改动
- **不创建 Strings catalog**：这些是代码内部标识符，不是用户可见文本
- **不修改 Go 后端**：后端的常量管理不在本次范围内
