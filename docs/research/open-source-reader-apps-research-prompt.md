# 开源 iOS 稍后阅读/网页收藏应用 — 深度调研

## 项目背景

Folio（页集）是一个**本地优先的个人知识收藏 iOS App**。用户从任意 App（微信、Twitter、浏览器）通过系统分享面板将链接保存到 Folio，App 自动提取正文内容、AI 分类打标签、生成摘要，所有数据优先存储在本地设备。

**核心流程**：收藏 → 自动整理 → 全文检索

### 当前技术栈

| 层级 | 技术方案 |
|------|---------|
| iOS 客户端 | Swift 5.9+ / SwiftUI / SwiftData / SQLite FTS5，部署目标 iOS 17 |
| Share Extension | 用户分享入口，120MB 内存限制，通过 App Group 与主 App 共享数据 |
| 内容提取 | 服务端 Node.js，使用自研 reader 库将网页转为 Markdown |
| AI 分析 | 服务端 Python FastAPI + DeepSeek，一次 API 调用返回分类/标签/摘要 |
| 后端 API | Go + chi 路由 + asynq 任务队列 + PostgreSQL + Redis |
| 阅读器 | SwiftUI 原生渲染，使用 apple/swift-markdown 解析 Markdown |

### 架构特点

- **离线优先**：Share Extension 立即将 URL 写入本地 SwiftData，后端处理异步进行
- **单次 AI 调用**：分类 + 标签 + 摘要合并为一次 DeepSeek 请求
- **混合架构**：内容提取和 AI 在服务端完成，阅读和搜索完全本地化
- **9 个内容分类**：tech, business, science, culture, lifestyle, news, education, design, other

### 调研动机

通过研究同类开源项目，了解业界在以下模块的最佳实践，找到 Folio 可以借鉴改进的方向：

1. **客户端内容提取** — Folio 目前完全依赖服务端提取，是否可以在客户端做部分提取以减少延迟？
2. **Share Extension 体验优化** — 在 120MB 限制下的最佳实践
3. **阅读器渲染质量** — 目前用 SwiftUI 原生渲染 Markdown，效果和体验是否有更好的方案？
4. **本地存储与搜索** — SwiftData + FTS5 的方案是否足够，还是有更优解？
5. **整体架构** — MVVM + Clean Architecture 在同类 App 中的实践参考

---

## 调研目标

为 Folio 找到可借鉴的开源 iOS 实现，重点关注：**内容提取、Share Extension、离线阅读、本地存储** 四个核心模块的技术方案。

---

## 第一阶段：项目发现与筛选

### 1.1 搜索关键词矩阵

| 维度 | 关键词 |
|------|--------|
| 功能描述 | `read it later`, `bookmark manager`, `web clipper`, `article saver`, `content extractor` |
| 技术栈 | `iOS open source`, `SwiftUI`, `Swift`, `Share Extension` |
| 竞品名 | `Omnivore`, `Wallabag`, `Shiori`, `Linkding`, `Readeck`, `Hoarder`, `Karakeep` |
| 搜索平台 | GitHub, GitLab, awesome-ios 列表, awesome-selfhosted 列表 |

### 1.2 筛选标准（必须满足 ≥3 项）

- [ ] 有 iOS 原生客户端（Swift/SwiftUI，非 React Native/Flutter）
- [ ] Star 数 ≥ 500 或有实质性代码量
- [ ] 有网页内容提取功能（非纯书签）
- [ ] 最近 2 年内有提交活动（归档项目如 Omnivore 例外，因代码完整度高）
- [ ] 开源许可证允许参考（MIT/Apache/AGPL 均可）

### 1.3 输出物

项目清单表格，每个项目包含：名称、GitHub URL、Star 数、许可证、最后活跃时间、技术栈、一句话描述。

---

## 第二阶段：架构深度分析（Top 5 项目）

对筛选出的 Top 5 项目，逐一分析以下 6 个维度：

### 2.1 内容提取方案

- 用什么库/算法提取正文？（Readability.js、Mercury、自研、服务端提取）
- 提取发生在客户端还是服务端？
- 如何处理反爬/JS 渲染页面（微信公众号、SPA）？
- 提取结果格式：HTML / Markdown / 自定义 AST？
- 图片如何处理？（直接引用 / 下载缓存 / rehost）

### 2.2 Share Extension 实现

- Extension 的内存管理策略（120MB 限制下怎么做）
- 与主 App 的数据共享方式（App Group / UserDefaults / 文件系统 / Core Data）
- 离线保存逻辑：Extension 里做到哪一步？只存 URL 还是也做初步提取？
- UI 复杂度：简单确认弹窗 vs 可编辑表单

### 2.3 本地存储与数据模型

- 持久化方案：Core Data / SwiftData / SQLite / Realm / 文件系统
- 全文搜索实现：FTS5 / Core Spotlight / 自建倒排索引
- 数据模型设计：Article / Tag / Category / ReadingProgress 的关系
- 离线优先策略：冲突解决、同步队列

### 2.4 阅读器实现

- 渲染方案：WKWebView / 原生 SwiftUI Text / AttributedString / 自研
- Markdown 渲染库选择
- 排版自定义：字体、字号、行距、主题
- 代码块高亮方案
- 图片懒加载策略

### 2.5 同步与网络层

- 同步协议：REST / GraphQL / WebSocket / CloudKit
- 离线队列设计：重试策略、冲突解决
- 认证方案：JWT / OAuth / Apple Sign In

### 2.6 项目工程实践

- 架构模式：MVVM / TCA / VIPER / Clean Architecture
- 模块化方式：SPM Package / Framework / 单 Target
- 测试覆盖率与测试策略
- CI/CD 方案

### 输出物

每个项目一份结构化分析报告，按上述 6 个维度组织。

---

## 第三阶段：对标 Folio 的差距分析

### 3.1 特性对比矩阵

| 特性 | Folio 现状 | 项目 A | 项目 B | ... | 最佳实践 |
|------|-----------|--------|--------|-----|---------|
| 内容提取 | 服务端 Node.js | | | | |
| Share Extension | 存 URL + 离线队列 | | | | |
| 本地搜索 | SQLite FTS5 | | | | |
| 阅读器渲染 | SwiftUI + swift-markdown | | | | |
| 离线支持 | SwiftData + OfflineQueue | | | | |
| 分类/标签 | AI 自动分类 | | | | |

### 3.2 可直接借鉴的实现

列出具体可以参考的代码片段/设计模式，标注：

- 源项目 + 文件路径
- 解决什么问题
- 迁移到 Folio 的改动量评估（小 / 中 / 大）

### 3.3 Folio 的差异化优势确认

明确 Folio 做了而别人没做的（AI 自动分类、DeepSeek 摘要、本地优先 + 服务端混合架构），确保调研后不丢失自身定位。

---

## 第四阶段：结论与建议

- **技术选型建议**：哪些模块值得参考哪个项目的方案
- **风险点**：许可证兼容性、已归档项目的代码腐化风险
- **优先级排序**：按 Folio 当前阶段，最值得投入精力研究的 Top 3 模块
- **Action Items**：具体的下一步行动清单

---

## 执行建议

| 阶段 | 工作量 | 并行策略 |
|------|--------|---------|
| 第一阶段：发现筛选 | 轻 | 多个搜索关键词可并行 |
| 第二阶段：深度分析 | 重（核心） | 5 个项目可并行分析 |
| 第三阶段：对标分析 | 中 | 依赖第二阶段完成 |
| 第四阶段：结论 | 轻 | 依赖第三阶段完成 |

建议先完成第一阶段拿到项目列表，再对 Top 5 并行展开第二阶段的 6 个维度分析，效率最高。
