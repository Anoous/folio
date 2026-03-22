# Echo Active Recall — Design Spec

> 日期：2026-03-22
> 状态：Approved
> 范围：P1.1 — Echo 主动回忆系统（核心洞察类型）

---

## 概述

Echo 是 Folio 的间隔重复系统。AI 分析文章后自动生成问答卡片，在用户快忘记时提问，用户主动回忆后标记"记得/忘了"，SM-2 算法调整下次复习时间。

**核心流程：** 文章 AI 分析完成 → Worker 生成 Echo 卡片 → 穿插在 Home Feed → 用户交互 → 间隔重复

## 设计决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 生成位置 | 后端 Worker | 跨设备同步、算法集中管理 |
| 间隔算法 | SM-2 简化版 | DB 字段已匹配、简单可靠、后续可升级 FSRS |
| 穿插规则 | 每 3-4 篇文章后插一张 | 与原型一致，不突兀 |
| 生成时机 | AI 分析完成后自动入队 | 零用户操作、AI 生成问答质量高 |

## 卡片类型路线图

| 类型 | 实现时机 | 依赖 |
|------|---------|------|
| `insight`（核心洞察） | **本次 P1.1** | key_points（已有） |
| `highlight`（高亮回顾） | P1.2 高亮完成后补 | highlights 表数据 |
| `related`（关联发现） | P1.3 RAG 完成后补 | 向量嵌入/相似度 |

三种类型复用同一套 Echo 卡片 UI + SM-2 算法，仅 `card_type` 和内容不同。

## 后端设计

### 1. echo:generate Worker 任务

**触发：** `article:ai` Worker 完成后自动入队
**队列：** Default，2 次重试，30 秒超时
**输入：** article_id, user_id
**逻辑：**

1. 读取文章的 key_points 和 summary
2. 调用 DeepSeek API，prompt 要求从 key_points 生成 1-2 个问答对：
   - question：一个自然的回忆提问（如"这篇文章最反直觉的结论是什么？"）
   - answer：简洁的答案（直接引用或精炼 key_point）
   - source_context：来源描述（如"来自《文章标题》· 来源 · 收藏时间"）
3. 写入 `echo_cards` 表：
   - `card_type = 'insight'`
   - `next_review_at = NOW() + INTERVAL '1 day'`
   - `interval_days = 1`, `ease_factor = 2.50`

**AI prompt（追加在现有分析之后，或独立调用）：**
```
基于以下文章要点，生成 1-2 个回忆测试问答对。

要求：
1. question：用"还记得……吗？"的口吻，引导用户主动回忆，不超过 30 字
2. answer：简洁的答案，可以是原文引用或精炼表述，不超过 50 字
3. source_context：一句来源描述

输出 JSON 数组：[{"question":"...", "answer":"...", "source_context":"..."}]

文章标题：{title}
来源：{source}
要点：
{key_points}
```

### 2. SM-2 间隔重复算法

```
func updateSM2(card, result):
    card.review_count += 1

    if result == "remembered":
        card.correct_count += 1
        if card.review_count == 1:
            card.interval_days = 1
        elif card.review_count == 2:
            card.interval_days = 3
        else:
            card.interval_days = round(card.interval_days * card.ease_factor)
        card.ease_factor = min(3.0, card.ease_factor + 0.1)

    elif result == "forgot":
        card.interval_days = 1
        card.ease_factor = max(1.3, card.ease_factor - 0.2)

    card.next_review_at = now + card.interval_days * 24h
```

### 3. API 端点

#### GET /api/v1/echo/today

获取今日待复习卡片。

**请求：** `?limit=5`（默认 5）
**响应：**
```json
{
  "data": [
    {
      "id": "uuid",
      "article_id": "uuid",
      "article_title": "为什么 90% 的 AI 项目失败",
      "card_type": "insight",
      "question": "还记得 AI 项目失败最反直觉的结论吗？",
      "answer": "失败的根因不是技术，而是问题定义错误。",
      "source_context": "来自《为什么 90% 的 AI 项目失败》· 少数派 · 3 周前收藏",
      "next_review_at": "2026-03-22T08:00:00Z",
      "interval_days": 14,
      "review_count": 3
    }
  ],
  "remaining_today": 2,
  "weekly_count": 1,
  "weekly_limit": 3
}
```

**逻辑：**
- 查询 `echo_cards WHERE user_id = ? AND next_review_at <= NOW()` ORDER BY next_review_at ASC
- JOIN articles 获取 article_title
- Free 用户：检查 `users.echo_count_this_week`，超过 3 则返回空 data + remaining_today=0
- weekly_limit: Free=3, Pro=null

**权限：** auth

#### POST /api/v1/echo/{id}/review

提交回忆反馈。

**请求：**
```json
{
  "result": "remembered",
  "response_time_ms": 3200
}
```

**响应：**
```json
{
  "next_review_at": "2026-04-05T08:00:00Z",
  "interval_days": 14,
  "review_count": 4,
  "correct_count": 3,
  "streak": {
    "weekly_rate": 85,
    "consecutive_days": 7,
    "display": "本周回忆率 85% · 已连续 7 天"
  }
}
```

**逻辑：**
1. 运行 SM-2 更新 echo_card
2. 写入 echo_reviews 记录
3. 递增 users.echo_count_this_week（Free 用户配额）
4. 聚合 streak 数据：
   - weekly_rate = 本周 remembered / 本周 total × 100
   - consecutive_days = 连续有 echo_review 记录的天数

**权限：** auth

### 4. 文件结构（后端新增）

```
server/internal/
├── worker/
│   └── echo.go              # echo:generate 任务处理器
├── service/
│   └── echo.go              # Echo 业务逻辑（SM-2 + streak 计算）
├── repository/
│   └── echo.go              # echo_cards + echo_reviews 数据库操作
├── api/handler/
│   └── echo.go              # HTTP handler
└── domain/
    └── echo.go              # EchoCard + EchoReview 领域模型
```

## iOS 设计

### 1. SwiftData 模型

**EchoCard（新增）：**
```
@Model class EchoCard:
    id: UUID
    serverID: String?
    articleID: UUID
    articleTitle: String
    cardType: String          // "insight" | "highlight" | "related"
    question: String
    answer: String
    sourceContext: String?
    nextReviewAt: Date
    intervalDays: Int
    reviewCount: Int
    correctCount: Int
    createdAt: Date
```

注册到 `DataManager.schema`。

### 2. EchoCardView（新增）

**文件：** `ios/Folio/Presentation/Home/EchoCardView.swift`

匹配原型 02 的 4 步交互状态机：

**Step 0 — 问题呈现：**
- echoBg 背景，14pt 圆角
- "✦ ECHO" 标签（11px, uppercase, tracking 2.5, textTertiary）
- 问题文字（v3EchoQuestion 17px 衬线体，居中）
- 来源信息（12px, textQuaternary）
- "揭晓答案" 按钮（14px, 边框圆角 24px）

**Step 1 — 揭晓答案（settle 0.4s 展开）：**
- 问题缩小变灰（15px, textTertiary, 左对齐）
- 答案出现（17px 衬线体, 左侧 2px accent 竖线, padding-left 14px）
- 来源标注（12px, textQuaternary, padding-left 14px）
- "记得" / "忘了" 按钮（flex 两列，success/error 边框色）

**Step 2 — 反馈后收缩（exit 0.2s）：**
- 收缩为确认行（14px, textSecondary, 居中）
- 记得："✓ 记得 · 下次 2 周后回顾"
- 忘了："已标记 · 3 天后再来"
- streak 行："本周回忆率 85% · 已连续 7 天"（12px, textTertiary）

### 3. HomeView 穿插逻辑

**HomeViewModel 新增：**
- `echoCards: [EchoCard]` — 启动时从 `GET /echo/today` 拉取
- `func submitEchoReview(cardID: UUID, result: String)` — 乐观更新 + 异步提交

**穿插算法：**
```
let combined: [(type: FeedItem, data: Any)]
var echoIndex = 0
for (i, article) in articles.enumerated() {
    combined.append(.article(article))
    if (i + 1) % 4 == 0, echoIndex < echoCards.count {
        combined.append(.echo(echoCards[echoIndex]))
        echoIndex += 1
    }
}
```

### 4. DTO（Network.swift 新增）

```swift
struct EchoCardDTO: Codable {
    let id: String
    let articleId: String
    let articleTitle: String
    let cardType: String
    let question: String
    let answer: String
    let sourceContext: String?
    let nextReviewAt: Date
    let intervalDays: Int
    let reviewCount: Int
}

struct EchoTodayResponse: Codable {
    let data: [EchoCardDTO]
    let remainingToday: Int
    let weeklyCount: Int
    let weeklyLimit: Int?
}

struct EchoReviewRequest: Codable {
    let result: String  // "remembered" | "forgot"
    let responseTimeMs: Int?
}

struct EchoReviewResponse: Codable {
    let nextReviewAt: Date
    let intervalDays: Int
    let reviewCount: Int
    let correctCount: Int
    let streak: EchoStreak
}

struct EchoStreak: Codable {
    let weeklyRate: Int
    let consecutiveDays: Int
    let display: String
}
```

### 5. SyncService 扩展

- `fetchEchoCards()` — 调用 `GET /echo/today`，更新本地 SwiftData
- App 启动时和下拉刷新时调用

### 6. 文件结构（iOS 新增）

```
ios/Folio/
├── Domain/Models/
│   └── EchoCard.swift                # SwiftData 模型
├── Presentation/Home/
│   └── EchoCardView.swift            # Echo 卡片 4 步交互 UI
└── Data/Network/Network.swift        # 新增 DTO + APIClient 方法
```

## Free/Pro 配额

| | Free | Pro |
|---|------|-----|
| Echo 次数 | 3 次/周 | 无限 |
| 配额追踪 | `users.echo_count_this_week` | 不追踪 |
| 重置 | 每周一 00:00（`echo_week_reset_at`） | — |
| 超限行为 | `GET /echo/today` 返回空 + `remaining_today=0` | — |

## 不做

- 高亮回顾卡片（P1.2 后补）
- 关联发现卡片（P1.3 后补）
- 推送通知（Echo 体验稳定后再加）
- Echo 历史页面（P1.4 知识地图消费 echo_reviews 数据）
- 自定义复习频率设置

## 对应原型元素

| 原型 02 元素 | 本设计对应 |
|-------------|-----------|
| ✦ ECHO 标签 | EchoCardView Step 0 |
| 问题文字（衬线居中） | EchoCardView Step 0, v3EchoQuestion |
| 来源信息 | echo_cards.source_context |
| "揭晓答案" 按钮 | EchoCardView Step 0 → Step 1 transition |
| 答案（衬线粗体 + accent 竖线） | EchoCardView Step 1 |
| 来源标注 | article_title via echo_cards.article_id |
| 记得/忘了按钮 | EchoCardView Step 1, POST /echo/{id}/review |
| 确认行 + 下次时间 | EchoCardView Step 2, review response |
| streak 统计行 | EchoCardView Step 2, streak 字段 |
| 核心洞察类型 | card_type = 'insight' |
| 高亮回顾类型 | card_type = 'highlight'（P1.2 后补） |
| 关联发现类型 | card_type = 'related'（P1.3 后补） |
| Home Feed 穿插 | HomeViewModel 每 4 篇插一张 |
