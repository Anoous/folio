# 知识地图 — Design Spec

> 日期：2026-03-23
> 状态：Approved
> 范围：P1.4 — 知识地图（从 Settings 进入的统计页面）

---

## 概述

知识地图是用户的月度阅读统计页面，从 Settings "知识地图" 行进入。展示 4 个区域：月度概览数字、主题分布条形图、AI 趋势洞察、Echo 吸收统计。Pro 功能。

## 设计决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 入口 | Settings → 知识地图 | 原型 07 从通用 section 进入 |
| 数据来源 | 后端聚合 API | 需要跨表统计（articles + echo_reviews + categories） |
| 趋势洞察 | AI 生成（DeepSeek） | 基于本月 vs 上月分类变化 |
| 权限 | Pro only | Free 用户看到升级提示 |

## 后端

### GET /api/v1/stats/monthly

**请求：** `?month=2026-03`（默认当月）

**响应：**
```json
{
  "articles_count": 47,
  "insights_count": 31,
  "streak_days": 7,
  "topic_distribution": [
    { "category_slug": "tech", "category_name": "科技", "count": 14 },
    { "category_slug": "business", "category_name": "商业", "count": 9 }
  ],
  "trend_insight": "你的关注重心正在从「AI 技术」转向「AI 产品化」——本月产品类收藏增长了 80%，而纯技术类持平。"
}
```

**逻辑：**
1. articles_count: `COUNT(articles) WHERE user_id AND created_at IN month`
2. insights_count: `COUNT(articles) WHERE summary IS NOT NULL AND created_at IN month`
3. streak_days: 连续有收藏的天数（从今天倒推）
4. topic_distribution: `GROUP BY category_id JOIN categories`，按 count DESC
5. trend_insight: 用 DeepSeek 一句话分析（本月 vs 上月分类变化）。如果只有一个月数据，返回简单总结。

**权限：** auth + pro

### GET /api/v1/stats/echo

**请求：** `?month=2026-03`

**响应：**
```json
{
  "completion_rate": 85,
  "total_reviews": 23,
  "remembered_count": 20,
  "forgotten_count": 3
}
```

**逻辑：** 从 echo_reviews 聚合当月数据。

**权限：** auth + pro

### 文件结构

```
server/internal/
├── service/stats.go       # 统计聚合 + AI 趋势
├── api/handler/stats.go   # HTTP handlers
```

Repository 层不需要新文件——直接在 service 中用 raw SQL 查询（统计查询不适合 ORM 模式）。

## iOS

### KnowledgeMapView

**文件：** `ios/Folio/Presentation/Settings/KnowledgeMapView.swift`

从 Settings "知识地图" 行 NavigationLink 进入。

**布局（匹配原型 05）：**

1. **标题** "知识地图" + 月份（"2026 年 3 月"）
2. **月度概览**（三列数字）：
   - 47 篇收藏 | 31 个洞察 | 7 天连续
   - 数字：28px bold，标签：13px textTertiary
3. **主题分布**（水平条形图）：
   - "主题分布" header
   - 每行：分类名 + 数字 + 水平条（宽度按比例，accent 色）
   - 按 count DESC 排序
4. **趋势洞察**：
   - "✦ 趋势洞察" 标签（accent）
   - 一句话 AI 分析（衬线 15px, textSecondary）
5. **Echo 吸收统计**：
   - "Echo 吸收统计" header
   - 回忆率 X%（大数字 + 环形进度）
   - 本月 N 次 Echo
   - 记得 X / 忘了 Y
   - 底部："知识在积累，你正在变得更强。"

### DTO

```swift
struct MonthlyStatsResponse: Codable {
    let articlesCount: Int
    let insightsCount: Int
    let streakDays: Int
    let topicDistribution: [TopicStat]
    let trendInsight: String?
}

struct TopicStat: Codable {
    let categorySlug: String
    let categoryName: String
    let count: Int
}

struct EchoStatsResponse: Codable {
    let completionRate: Int
    let totalReviews: Int
    let rememberedCount: Int
    let forgottenCount: Int
}
```

### Free 用户处理

Free 用户点击"知识地图" → 显示升级提示（"知识地图是 Pro 功能" + 升级按钮），不调 API。

## 不做

- 月份切换（只显示当月）
- 知识图谱可视化（graph view）
- 导出统计数据
