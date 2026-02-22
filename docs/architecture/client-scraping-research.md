# 客户端内容提取方案调研

> 创建日期：2026-02-22
> 关联文档：[扩展方案](scaling-plan.md) | [系统架构](system-design.md) | [三份深度研究对比分析与最终结论](../research/client-extraction-comparative-analysis.md)

---

## 一、竞品架构分析

### 1.1 Pocket（Mozilla）

**模式：服务端抓取 + 解析**

| 路径 | 技术 | 适用场景 |
|------|------|---------|
| 快速路径 | 服务端 HTTP 请求 + Mozilla Readability | 服务端渲染的页面（大多数） |
| 慢速路径 | 服务端 Puppeteer（无头 Chrome） | 客户端渲染的 SPA / JS 重页面 |

- 正文提取核心是 **Mozilla Readability**（Pocket 被 Mozilla 收购后直接使用）
- 有内容长度阈值判断：Readability 提取结果太短 → 自动切换到 Puppeteer 重新抓取
- 全局内容缓存：多个用户保存同一 URL，只抓取一次（article 与 user 解耦存储）
- 相对 URL 在服务端统一解析为绝对 URL
- HTML 在解析前做 sanitize 防注入

> 来源：https://blog.devesh.tech/post/how-pocket-works

### 1.2 Readwise Reader

**模式：客户端采集 HTML → 服务端解析**

- **浏览器扩展 / iOS Safari Share Sheet 发送完整渲染后的 HTML**（不是 URL）→ 服务端解析
- 直接分享 URL 时只发 URL → 服务端自己抓取 → 解析质量低于扩展方式
- 官方原话："Browser extensions result in the highest quality parsing because Reader is getting the full document content rather than the naked URL"
- **付费墙内容也能保存**（浏览器扩展有用户登录态，拿到的是已认证的 DOM）
- 解析引擎自研，有专人维护 parsing tickets
- 内部有 benchmark：对比 Instapaper/Pocket 的 Top 200 文章解析质量
- 有专门工程师持续优化 parsing

> 来源：https://docs.readwise.io/reader/docs/faqs/parsing

### 1.3 Instapaper

**模式：服务端抓取 + 自研解析**

- 使用**自研的 "statistical tag-and-prune" 系统**（非 Readability）
- 与 Readability 思路类似：分析 HTML 标签的文本密度和相对位置
- 比 Readability 更保守 — 宁可多留内容，不激进裁剪
- 服务端处理所有抓取和解析
- 解析引擎作为独立 API 对外开放（Instaparser API）

> 来源：https://www.quora.com/How-do-Pocket-Instapaper-Flipboard-etc-extract-articles-from-a-page

### 1.4 Omnivore（开源，2024 年被 ElevenLabs 收购后关闭）

**模式：服务端抓取 + 解析，完全开源**

| 组件 | 技术 | 作用 |
|------|------|------|
| content-fetch | TypeScript 服务 | 协调内容获取 |
| puppeteer-parse | Chromium 无头浏览器（端口 9090） | 渲染 JS 页面 |
| Readability.js | Mozilla 扩展版（AGPL-3.0） | 正文提取 |
| go-domdistiller | Chrome DomDistiller 的 Go 移植 | Chrome Reader Mode 算法的备选 |

- 浏览器扩展发送完整渲染后的 HTML
- 移动端发送 URL → 服务端 Puppeteer 渲染后用 Readability 提取
- 代码全开源：https://github.com/omnivore-app/omnivore

### 1.5 Hoarder / Karakeep（开源书签应用）

**模式：服务端抓取 + 解析**

- Puppeteer 抓取 + 内容提取
- monolith 做全页面归档（防 link rot）
- AI 自动打标签（与 Folio 类似）
- 技术栈：NextJS, tRPC, Drizzle, BullMQ, Meilisearch
- 开源：https://github.com/karakeep-app/karakeep

### 1.6 Matter

**模式：未公开，iOS-first**

- 自研解析引擎，以解析质量著称
- 作为 iOS-first 应用，很可能有客户端参与
- 具体架构未公开

---

## 二、行业模式总结

| 模式 | 代表产品 | 工作方式 | 优势 | 劣势 |
|------|---------|---------|------|------|
| **A: 服务端抓取 + 解析** | Pocket, Instapaper, Omnivore, Hoarder | 客户端只发 URL，服务端 HTTP/Puppeteer 抓取 + Readability 提取 | 客户端零负担；解析逻辑集中维护 | IP 被封；无法处理付费墙；JS 渲染需 Puppeteer 开销大 |
| **B: 客户端采集 HTML → 服务端解析** | Readwise Reader | 浏览器扩展/Share Sheet 发送完整 HTML 到服务端，服务端做 Readability 提取 | 能拿到付费墙内容和 JS 渲染后的 DOM；解析逻辑集中迭代 | 传输全量 HTML 流量大；服务端仍需解析能力 |
| **C: 客户端抓取 + 客户端解析** | Safari Reading List, Folio Phase 1 | 完全在设备端完成下载和解析，服务端只做 AI | 零服务端抓取负担；用户自己的 IP/cookie；2-5 秒可读 | 客户端需维护解析逻辑；iOS 设备算力/内存有限 |

### 关键发现

1. **Mozilla Readability 是行业标准** — Pocket / Omnivore 直接使用，Instapaper 自研但思路一致
2. **Readwise 的 "客户端发完整 HTML" 模式是差异化** — 解决了付费墙和 JS 渲染问题，但需要浏览器扩展配合
3. **纯客户端抓取+解析（模式 C）在竞品中较少见** — Safari Reading List 是最接近的先例，Pocket/Instapaper 均在服务端做
4. **所有竞品的核心算法本质相同** — 都是基于 HTML 标签的文本密度和位置做 scoring + pruning

---

## 三、iOS 端可用的开源库

### 3.1 正文提取（Readability 算法）

| 库 | 技术方案 | WKWebView | 维护状态 | 备注 |
|----|---------|-----------|---------|------|
| [lake-of-fire/swift-readability](https://github.com/lake-of-fire/swift-readability) | Mozilla Readability.js 的纯 Swift 移植，基于 SwiftSoup | 不需要 | 新项目（9 commits），Swift 6.2, iOS 15+ | **最契合 Folio**：纯 Swift，50+ fixture 测试，输出 HTML |
| [Ryu0118/swift-readability](https://github.com/Ryu0118/swift-readability) | 包装 Mozilla Readability.js，通过 WKWebView 执行 JS | 需要 | 较成熟（51 stars, v0.3.0） | WKWebView 内存开销大，App Store 审核风险 |
| [exyte/ReadabilityKit](https://github.com/exyte/ReadabilityKit) | 提取 metadata（title, description, image） | 不需要 | 维护一般 | 仅提取预览信息，不做全文正文提取 |

### 3.2 HTML → Markdown 转换

| 库 | 技术方案 | WKWebView | 维护状态 | 备注 |
|----|---------|-----------|---------|------|
| [steipete/Demark](https://github.com/steipete/Demark) | WKWebView + Turndown.js | 需要 | 活跃（97 stars, MIT） | 5-100ms，但依赖 WebView |
| [ActuallyTaylor/SwiftHTMLToMarkdown](https://github.com/ActuallyTaylor/SwiftHTMLToMarkdown) | 纯 Swift | 不需要 | 一般（30 commits） | 不支持 table |

### 3.3 HTML 解析（底层）

| 库 | 说明 |
|----|------|
| [scinfu/SwiftSoup](https://github.com/scinfu/SwiftSoup) | 纯 Swift HTML 解析器（DOM + CSS selectors + jQuery 风格 API），上述方案的基础依赖 |

---

## 四、Folio 推荐方案

### 推荐组合：swift-readability + 自写 Markdown 转换

| 层次 | 方案 | 理由 |
|------|------|------|
| HTML 下载 | URLSession（15s 超时，2MB 上限） | 标准 iOS API，App Store 无风险 |
| 正文提取 | lake-of-fire/swift-readability | Mozilla Readability 算法的纯 Swift 移植，不需要 WKWebView，50+ fixture 测试保证质量 |
| Markdown 转换 | 自写 ~100 行（递归遍历 DOM → Markdown） | swift-readability 输出干净的 article HTML，转 Markdown 直接简单；避免引入 WKWebView 依赖 |

### 备选方案：SwiftSoup + 自写 heuristic

如果 swift-readability 评估后不够稳定（项目太新），退回到 SwiftSoup + 自定义正文提取 heuristic（selector 优先级 + element scoring）。工程量增加约 150 行，但正文提取质量不如经过 10 年验证的 Readability 算法。

### 与 Readwise 模式的对比

Readwise 的"客户端发 HTML → 服务端解析"模式对 Folio 的 Share Extension 场景不太适用：
- Share Extension 有 120MB 内存限制，不适合做 HTML 解析
- 发送完整 HTML 到服务端的流量开销大
- Folio 的核心目标是"2-5 秒可读"，需要本地直接出结果
- 但 Readwise 模式可以作为 **Phase 2 的增强**（比如处理 JS 渲染的页面）
