# 冷启动策略 — Design Spec + Plan

> 日期：2026-03-23
> 状态：Approved
> 范围：P1.5 — 冷启动里程碑提示（纯 iOS 端）

---

## 概述

新用户从 0 到 11 篇文章的旅程中，在关键节点显示里程碑提示卡片，引导用户发现功能价值。纯客户端逻辑，基于 SwiftData 本地文章计数触发。

## 5 个里程碑（原型 08）

| 触发条件 | 标题 | 内容 | Aha Moment |
|---------|------|------|-----------|
| 第 1 篇 | Folio 已读过这篇 | 洞察摘要出现 + "继续收藏，它会发现文章之间的隐藏关联。" | AI 自动理解 |
| 第 3 篇 | 首次关联 | "你刚存的这篇和之前那篇都讨论了同一观点" | 文章连接 |
| 第 5 篇 | 解锁 Echo + RAG | 首次 Echo 出现 + "试试提问" 提示 | 主动回忆 + 问答 |
| 第 10 篇 | 试用总结 | 统计：10 篇 / X 洞察 / X 次 Echo + 升级引导 | 成长感 |
| 第 11 篇 | Free 限制生效 | Echo 每周 3 次 / RAG 每月 5 次 + "升级 Pro 解锁全部" | 付费触发 |

## 设计

### 实现方式

**不用后端，不用 `user_milestones` 表。** 纯客户端：

1. `@AppStorage` 存储已展示过的里程碑 Set（如 `"milestones_shown": "1,3,5"`）
2. HomeView 在文章列表顶部检测当前文章数
3. 如果命中里程碑且未展示过 → 显示提示卡片
4. 用户关闭 → 加入已展示 Set

### MilestoneCardView

**文件：** `ios/Folio/Presentation/Home/MilestoneCardView.swift`

在 Home Feed 文章列表顶部（日期行下方，文章之前）显示一张卡片：

- 背景：`Color.folio.accentSoft`（rgba accent 8%）
- 圆角：14px
- Padding：16px
- 标题：15px semibold, textPrimary
- 描述：14px, textSecondary, line-height 1.5
- 关闭按钮：右上角 "×"（textTertiary）
- 第 10 篇额外：小统计行（N 篇 / N 洞察）
- 第 10/11 篇额外："升级 Pro" 按钮（accent text，textPrimary bg）

### HomeView 集成

在 `articleList` 的 `statusBanners` 和 `dateHeader` 之间，插入：

```swift
if let milestone = activeMilestone {
    MilestoneCardView(milestone: milestone, onDismiss: { dismissMilestone(milestone) })
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
}
```

### 里程碑检测逻辑

```swift
var activeMilestone: Milestone? {
    let count = viewModel?.articles.count ?? 0
    let shown = dismissedMilestones // Set<Int> from @AppStorage

    if count >= 11 && !shown.contains(11) { return .freeLimit }
    if count >= 10 && !shown.contains(10) { return .trialSummary }
    if count >= 5 && !shown.contains(5) { return .unlockEchoRAG }
    if count >= 3 && !shown.contains(3) { return .firstAssociation }
    if count >= 1 && !shown.contains(1) { return .firstArticle }
    return nil
}
```

优先显示最高未展示的里程碑。用户关闭后永不再显示同一个。

## 不做

- 后端里程碑追踪（纯本地）
- 里程碑动画/庆祝效果
- 里程碑历史页面
- 自定义里程碑

---

## Implementation Plan

### Task 1: MilestoneCardView + HomeView Integration

**Files:**
- Create: `ios/Folio/Presentation/Home/MilestoneCardView.swift`
- Modify: `ios/Folio/Presentation/Home/HomeView.swift`

**Step 1:** Create Milestone enum + MilestoneCardView

```swift
enum Milestone: Int, CaseIterable {
    case firstArticle = 1
    case firstAssociation = 3
    case unlockEchoRAG = 5
    case trialSummary = 10
    case freeLimit = 11

    var title: String { ... }
    var description: String { ... }
    var showUpgrade: Bool { self == .trialSummary || self == .freeLimit }
}
```

**Step 2:** Add to HomeView:
- `@AppStorage("dismissed_milestones") private var dismissedMilestonesRaw = ""`
- Computed `activeMilestone` based on article count
- Insert `MilestoneCardView` above the article sections
- Dismiss handler adds milestone to the stored set

**Step 3:** xcodegen + build + commit

### Task 2: E2E Test on Simulator

Test: verify milestone card appears when article count matches.

---

3 个文件改动，1 个新文件。最简单的 P1 功能。
