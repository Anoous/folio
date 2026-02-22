# 客户端内容提取 — 需求文档

> 创建日期：2026-02-22
> 关联文档：[技术设计文档](client-extraction-technical-design.md) | [三份深度研究对比分析](../research/client-extraction-comparative-analysis.md) | [客户端抓取调研](client-scraping-research.md) | [系统架构](system-design.md)

---

## 一、功能概述

### 1.1 用户故事

> 作为 Folio 用户，我希望在任何 app 中分享链接后，**2-5 秒内就能打开 Folio 阅读完整文章内容**，而不是等待 5-15 秒的服务端处理。即使我在地铁/飞机上没有网络，分享的文章也能立即离线阅读。

### 1.2 动机

当前 Folio 的 Share Extension 仅保存 URL。内容提取完全依赖服务端链路（Go API → Node.js Reader → AI Service），存在以下问题：

1. **延迟高**：用户分享后需等待 5-15 秒才能阅读文章正文（网络往返 + 服务端抓取 + 解析）
2. **离线不可用**：无网络时，文章只有 URL，无法阅读内容
3. **依赖服务端**：服务端宕机或排队时，用户体验受阻

三份独立研究报告（Claude / Gemini / GPT）一致确认：**客户端提取是 Folio 最大的差异化机会**——目前没有任何主流开源 read-it-later 应用在 iOS 客户端实现了完整的正文提取。

### 1.3 核心价值

| 场景 | 当前体验 | 目标体验 |
|------|---------|---------|
| 用户在微信中分享公众号文章 | 保存 URL → 等待 5-15 秒 → 文章可读 | 保存 URL → **2-5 秒内文章可读** → 后台静默优化 |
| 用户在飞机上打开已分享文章 | 只有 URL，无法阅读 | **完整 Markdown 内容已保存，可离线阅读** |
| 服务端临时不可用 | 文章停留在 "processing" 状态 | **客户端已提取内容，不受影响** |

---

## 二、功能需求

### FR-1：Share Extension 内提取文章内容

Share Extension 在保存 URL 到 SwiftData 后，**立即在设备端获取 HTML 并提取文章正文**。提取管线：

```
URL → URLSession 下载 HTML → swift-readability 提取正文 → HTML→Markdown 转换 → 保存到 SwiftData
```

**验收标准**：
- 用户分享 URL 后，提取过程自动启动，无需用户额外操作
- 提取在 Share Extension 进程内完成（不依赖主 app 进程）
- 提取结果保存到与 URL 同一条 Article 记录中

### FR-2：提取结果保存为 Markdown

客户端提取的内容以 Markdown 格式保存到 `Article.markdownContent` 字段，同时填充 `title`、`author`、`siteName` 等元数据字段。

**验收标准**：
- 保存的 Markdown 格式与 Folio 现有 `MarkdownRenderer`（基于 `apple/swift-markdown`）兼容
- 支持的 Markdown 元素：标题（h1-h6）、段落、链接、图片、有序/无序列表、代码块、引用块、表格、强调（粗体/斜体/删除线）、分隔线
- 用户在 ReaderView 中打开文章时，客户端提取的内容能正常渲染阅读

### FR-3：优雅降级

任何提取失败（网络错误、解析失败、内存超限、超时）都**静默降级为仅保存 URL**——即当前已有的行为。客户端提取是增值功能，不能导致 Share Extension 崩溃或保存失败。

**验收标准**：
- 提取失败时，Article 记录仍然成功保存（仅有 URL，无 markdownContent）
- 提取失败不触发用户可见的错误提示
- 提取失败后，Article 的 `status` 保持 `pending`，等待服务端正常处理
- Share Extension 在任何情况下都不会因提取逻辑崩溃

### FR-4：服务端提取继续运行

客户端提取**不跳过服务端处理管线**。所有文章仍然提交到服务端进行：
1. 服务端内容抓取（Node.js Reader Service）
2. AI 分析（分类 + 标签 + 摘要）

**验收标准**：
- 客户端提取成功的文章，仍然通过 SyncService 提交到服务端
- 服务端仍执行完整的 crawl → AI 管线
- AI 分析结果（分类、标签、摘要、关键点）仍由服务端填充

### FR-5：服务端结果覆盖客户端结果

当服务端处理完成后，**服务端的 Markdown 内容替换客户端提取的内容**。服务端是权威质量层。

**验收标准**：
- 服务端 `ArticleDTO.markdownContent` 非空时，覆盖本地 `Article.markdownContent`
- 覆盖后，`Article.extractionSource` 更新为 `.server`
- 服务端 `title`、`author`、`siteName`、`wordCount` 等元数据同步覆盖
- 用户在阅读过程中如果服务端结果到达，内容静默更新（不打断阅读）

### FR-6：新增 `clientReady` 文章状态

在 `ArticleStatus` 枚举中新增 `clientReady` 状态，表示"客户端已提取到内容，等待服务端处理"。

**状态流转**：
```
pending → clientReady → processing → ready
                ↓                       ↓
              failed                  failed
```

**验收标准**：
- 客户端提取成功后，Article 状态从 `pending` 变为 `clientReady`
- `clientReady` 状态的文章在 Library 列表中显示为可阅读（有内容预览）
- 服务端开始处理后，状态从 `clientReady` 变为 `processing`，最终到 `ready`
- `clientReady` 状态的文章在 ReaderView 中可正常打开和阅读
- 向后兼容：旧版 app 遇到 `clientReady` 状态时，降级处理为 `pending`

### FR-7：内存安全

Share Extension 的提取过程受 **100MB 硬限制**保护（Apple 对 App Extension 的实际限制为 120MB，留 20MB 安全余量）。

**验收标准**：
- 提取过程中监控内存使用量
- 内存使用接近 100MB 阈值时，立即中止提取，降级为 URL-only 保存
- 正常提取的内存峰值不超过 65MB（基于研究报告的 35-65MB 估算）
- 内存超限中止不导致数据丢失或崩溃

### FR-8：超时控制

整个提取过程（下载 + 解析 + 转换 + 保存）的**总时间预算为 8 秒**。

**验收标准**：
- 超过 8 秒未完成提取时，中止提取，降级为 URL-only 保存
- 用户已保存的 URL 不受超时影响（URL 在提取开始前已保存）
- 超时后 Share Extension 正常关闭，不挂起

### FR-9：下载大小限制

HTML 下载限制为 **2MB**。超过此大小的页面直接放弃客户端提取。

**验收标准**：
- URLSession 下载过程中检测响应大小
- Content-Length 明确超过 2MB 时，取消下载
- 流式下载累积超过 2MB 时，取消下载
- 大小超限后降级为 URL-only 保存

### FR-10：内容源类型过滤

根据 URL 的 `SourceType` 决定是否尝试客户端提取：

| SourceType | 是否尝试客户端提取 | 原因 |
|------------|-----------------|------|
| `web` | ✅ 是 | 通用网页，大多数可提取 |
| `wechat` | ✅ 是 | 微信公众号文章 HTML 结构良好 |
| `twitter` | ✅ 是 | 推文页面可提取 |
| `weibo` | ✅ 是 | 微博内容可提取 |
| `zhihu` | ✅ 是 | 知乎文章 HTML 结构良好 |
| `newsletter` | ✅ 是 | 邮件正文通常结构清晰 |
| `youtube` | ❌ 否 | 视频页面无正文可提取 |

**验收标准**：
- YouTube 链接跳过客户端提取，直接保存 URL 等服务端处理
- 其他所有类型的链接均尝试客户端提取
- 过滤逻辑复用现有 `SourceType.detect(from:)` 方法

---

## 三、非功能需求

### 3.1 性能目标

| 指标 | 目标值 | 测量方式 |
|------|--------|---------|
| 提取成功率（标准网页） | ≥ 80% | 对 50 个代表性 URL 的测试集成功率 |
| 提取端到端耗时（P50） | ≤ 3 秒 | 从开始下载到 SwiftData 保存完成 |
| 提取端到端耗时（P95） | ≤ 6 秒 | 同上 |
| 内存峰值 | ≤ 65MB | Instruments Allocations 测量 |
| HTML 下载耗时 | ≤ 5 秒 | URLSession 超时配置 |
| Share Extension 总展示时间 | ≤ 10 秒 | 从出现到自动关闭 |

### 3.2 内存预算

| 阶段 | 预计内存 | 说明 |
|------|---------|------|
| URLSession 下载 HTML | ~5MB | 2MB HTML + 缓冲 |
| SwiftSoup DOM 解析 | ~10-25MB | 取决于 HTML 复杂度 |
| Readability 算法执行 | ~5-10MB | 评分 + 修剪 |
| Markdown 转换 + 保存 | ~5-10MB | 字符串操作 + SwiftData |
| **峰值总计** | **~35-65MB** | 在 120MB 限内有充足余量 |

### 3.3 错误处理矩阵

| 错误场景 | 处理方式 | 用户感知 |
|---------|---------|---------|
| 网络不可达 | 跳过提取，URL-only 保存 | 看到 "Added to Folio"（现有行为） |
| DNS 解析失败 | 跳过提取，URL-only 保存 | 同上 |
| HTTP 4xx/5xx | 跳过提取，URL-only 保存 | 同上 |
| SSL 证书错误 | 跳过提取，URL-only 保存 | 同上 |
| 下载超时（>5s） | 取消下载，URL-only 保存 | 同上 |
| HTML 超过 2MB | 取消下载，URL-only 保存 | 同上 |
| Readability 提取为空 | 跳过提取，URL-only 保存 | 同上 |
| Markdown 转换失败 | 跳过提取，URL-only 保存 | 同上 |
| 内存接近 100MB | 中止提取，URL-only 保存 | 同上 |
| 总超时（>8s） | 中止提取，URL-only 保存 | 同上 |
| SwiftData 保存失败 | URL 已保存，内容丢失 | 同上（内容等服务端） |
| YouTube 链接 | 跳过提取，URL-only 保存 | 同上 |

**核心原则**：所有提取相关的错误都静默处理，不影响 URL 保存，不向用户显示错误。

---

## 四、验收标准（汇总）

### 4.1 核心功能验收

- [ ] 用户从 Safari 分享一篇博客文章，2-5 秒后在 Folio Library 中可看到文章标题和内容预览
- [ ] 用户打开该文章进入 ReaderView，可阅读完整 Markdown 渲染的正文
- [ ] 30 秒后服务端处理完成，文章静默升级为服务端质量的内容，并新增 AI 分类/标签/摘要
- [ ] 用户在飞行模式下分享一篇已缓存的网页（Safari 阅读列表），Folio 仍然能提取并保存内容

### 4.2 降级场景验收

- [ ] 分享 YouTube 链接时，仅保存 URL，不尝试提取
- [ ] 分享一个超大 HTML 页面（>2MB）时，仅保存 URL，不崩溃
- [ ] 分享一个不存在的 URL（404）时，保存 URL，提取静默失败
- [ ] 网络中断时分享链接，URL 保存成功，提取跳过
- [ ] 分享一个 JS 渲染的 SPA 页面（如 React app），提取可能为空，降级为 URL-only

### 4.3 兼容性验收

- [ ] 客户端提取的 Markdown 在 `MarkdownRenderer` 中渲染正确（标题、段落、列表、代码块、图片、链接、表格）
- [ ] 新增的 `clientReady` 状态不影响现有列表筛选、搜索功能
- [ ] 新增的 `extractionSourceRaw`、`clientExtractedAt` 字段向后兼容（旧数据默认值合理）
- [ ] Share Extension 内存峰值不超过 100MB（使用 Instruments 验证）
- [ ] Share Extension 自动关闭时间不超过 10 秒

### 4.4 数据完整性验收

- [ ] 服务端 `ArticleDTO` 的 `markdownContent` 到达后，正确覆盖客户端提取内容
- [ ] 服务端覆盖后，`extractionSource` 更新为 `server`
- [ ] 文章的 `createdAt`、`url`、`id` 在整个流程中不变
- [ ] 服务端从未收到过 `clientReady` 状态（状态仅在客户端本地使用）

---

## 五、范围外（Out of Scope）

以下功能**不在**本次需求范围内：

| 排除项 | 原因 |
|--------|------|
| JavaScript 渲染（SPA 页面处理） | 需要 WKWebView，内存风险高，由服务端 Puppeteer 兜底 |
| 图片本地缓存 | 图片通过 Nuke 库按需加载，不在提取阶段处理 |
| WKWebView 方案 | 在 Share Extension 120MB 限内不安全，与现有 Markdown 渲染管线冲突 |
| 设备端 AI 分析 | 模型大小和推理延迟不适合 Share Extension 场景 |
| 付费墙内容提取 | 需要用户 Cookie 注入，隐私和技术风险高 |
| 服务端跳过抓取 | 即使客户端已提取，服务端仍执行完整管线以保证质量和 AI 分析 |
| 提取质量对比 UI | 不向用户展示客户端 vs 服务端的质量差异 |
| 自定义站点规则 | 类似 Wallabag 的 ftr-site-config，留到后续质量迭代阶段 |
| 离线队列提取 | 不在主 app 进程中对已保存的 URL-only 文章重新尝试客户端提取 |

---

## 六、支持的内容类型与边界用例

### 6.1 目标内容类型

| 内容类型 | 优先级 | 预期提取质量 | 备注 |
|---------|--------|------------|------|
| 中文博客 | P0 | 高 | Readability 对标准博客结构效果好 |
| 微信公众号文章 | P0 | 中-高 | HTML 结构良好，但图片可能有防盗链 |
| Twitter/X 推文 | P0 | 中 | 推文正文可提取，嵌入内容可能丢失 |
| 英文博客（Medium / Substack） | P0 | 高 | 标准结构，Readability 原生支持良好 |
| 知乎专栏 | P1 | 中-高 | HTML 结构良好 |
| 微博 | P1 | 中 | 内容结构较简单 |
| Newsletter（邮件存档页） | P1 | 中-高 | 通常为纯文本/简单 HTML |
| 技术文档（GitHub README 等） | P2 | 高 | Markdown 原生，转换简单 |
| 新闻站点 | P2 | 中 | 广告/导航干扰，Readability 需要过滤 |

### 6.2 边界用例

| 场景 | 预期行为 |
|------|---------|
| URL 指向 PDF | 跳过客户端提取，URL-only 保存，服务端处理 |
| URL 指向图片文件 | 跳过客户端提取，URL-only 保存 |
| URL 包含非 UTF-8 编码 | 尝试检测编码并转换，失败则降级 |
| URL 重定向超过 5 次 | 取消下载，降级为 URL-only |
| URL 响应 Content-Type 非 text/html | 跳过提取，降级为 URL-only |
| 提取结果正文少于 50 字符 | 视为提取失败，降级为 URL-only（等服务端） |
| 页面 HTML 格式严重损坏 | SwiftSoup 尽力解析，Readability 可能失败，降级 |
| 同一 URL 重复分享 | 由现有去重逻辑（`SharedDataManager.saveArticle`）拦截，不触发提取 |
