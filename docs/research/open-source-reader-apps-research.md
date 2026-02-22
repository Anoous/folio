# 开源 iOS 稍后阅读/网页收藏应用 — 深度调研报告

> 调研日期：2026-02-22
> 调研目的：为 Folio（页集）找到可借鉴的开源 iOS 实现，重点关注内容提取、Share Extension、离线阅读、本地存储四个核心模块。

---

## 第一阶段：项目发现与筛选

### 1.1 筛选结果

通过 GitHub、Codeberg、awesome-selfhosted、awesome-ios 等渠道搜索，共发现 8 个有价值的开源项目：

| 项目 | GitHub/Codeberg URL | Stars | 许可证 | 最后活跃 | iOS 客户端 | 技术栈 | 一句话描述 |
|------|---------------------|-------|--------|---------|-----------|--------|-----------|
| **Omnivore** | [github.com/omnivore-app/omnivore](https://github.com/omnivore-app/omnivore) | 15.9k | AGPL-3.0 | 2026-01（社区） | 原生 Swift | TS/Node.js + GraphQL + Swift | 功能最完整的开源稍后阅读，2024-10 被 ElevenLabs 收购后停服 |
| **Karakeep** | [github.com/karakeep-app/karakeep](https://github.com/karakeep-app/karakeep) | 23.6k | AGPL-3.0 | 2026-02（活跃） | React Native (Expo) | TS/Next.js + tRPC + SQLite | 前身为 Hoarder，AI 自动打标签，增长最快的书签管理器 |
| **Wallabag** | [github.com/wallabag/wallabag](https://github.com/wallabag/wallabag) | 12.5k | MIT | 2025-02（活跃） | 原生 Swift (UIKit) | PHP/Symfony + PostgreSQL | 最成熟的自托管稍后阅读（2013 年至今，248+ 贡献者） |
| **Readeck** | [codeberg.org/readeck/readeck](https://codeberg.org/readeck/readeck) | 841 | AGPL-3.0 | 2025-11（活跃） | 原生 SwiftUI | Go + SQLite | 轻量级自托管阅读器，架构最接近 Folio |
| **Linkwarden** | [github.com/linkwarden/linkwarden](https://github.com/linkwarden/linkwarden) | 17.3k | AGPL-3.0 | 2026-02（活跃） | React Native | TS/Next.js | 协作式书签管理，自动截图+PDF+HTML 存档 |
| **Shiori** | [github.com/go-shiori/shiori](https://github.com/go-shiori/shiori) | 11.3k | MIT | 2025（活跃） | 无 | Go + Vue.js | 简洁的自托管 Pocket 替代品，Go 后端 + go-readability |
| **Linkding** | [github.com/sissbruecker/linkding](https://github.com/sissbruecker/linkding) | 10.2k | MIT | 2026（活跃） | 社区第三方 | Python/Django | 极简书签管理器，支持全文搜索和网页存档 |
| **Linkeeper** | [github.com/OmChachad/Linkeeper](https://github.com/OmChachad/Linkeeper) | 28 | CC0 | 2024 | 原生 SwiftUI | 纯客户端 | 纯 Apple 生态书签管理器（iOS/iPadOS/macOS/visionOS） |

### 1.2 Top 5 深度分析对象

基于筛选标准（原生 iOS 客户端、代码完整度、与 Folio 的可比性），选定以下 5 个项目进行深度分析：

1. **Omnivore** — 功能最完整的原生 Swift 稍后阅读，代码库完整度最高
2. **Karakeep** — AI 自动分类/打标签，功能定位最接近 Folio
3. **Wallabag** — 最成熟的项目，官方 Swift iOS 客户端持续维护
4. **Readeck** — Go 后端 + SwiftUI iOS，架构最接近 Folio
5. **Linkwarden** — 网页存档+协作，补充参考

---

## 第二阶段：架构深度分析

### 项目 1：Omnivore

> **状态**：2024-10 团队被 ElevenLabs 收购（acqui-hire），2024-11-15 服务停止并删除所有用户数据。代码库保持开源（AGPL-3.0），社区仍有 fork 和 PR。

#### 2.1 内容提取方案

| 维度 | 方案 |
|------|------|
| **提取库** | 自研 fork 的 Mozilla Readability.js（扩展了 tweet 嵌入、语言检测、srcset 解析） |
| **提取位置** | 完全服务端（`content-fetch` + `puppeteer-parse` 微服务） |
| **JS 渲染页面** | Puppeteer（headless Chromium）+ `puppeteer-extra-plugin-stealth`（反检测）+ `puppeteer-extra-plugin-adblocker`（广告拦截） |
| **提取结果格式** | HTML（经 `linkedom` 清洗和后处理） |
| **图片处理** | 服务端下载缓存到 Google Cloud Storage / AWS S3 |

**关键代码路径**：
- `packages/readabilityjs/` — fork 的 Readability.js
- `packages/puppeteer-parse/` — Puppeteer 爬取服务
- `packages/content-fetch/` — Express 爬取协调服务
- `packages/content-handler/` — HTML 清洗后处理

**对 Folio 的启示**：Omnivore 的 Readability.js fork 包含了大量实战中的 edge case 处理，比原版更健壮。Folio 的 `@vakra-dev/reader` 如果在特定站点遇到问题，可以参考 Omnivore 的修改。

#### 2.2 Share Extension 实现

| 维度 | 方案 |
|------|------|
| **架构** | UIViewController 嵌入 SwiftUI（`UIHostingController` 子视图） |
| **数据共享** | App Group（`group.app.omnivoreapp`），共享 Core Data SQLite 数据库 |
| **离线保存逻辑** | Extension 内发送 GraphQL `saveUrl` mutation 到服务端 + 本地 Core Data 立即存储 |
| **UI 复杂度** | 底部弹出面板（60% 高度），支持添加备注、编辑标签、编辑文章信息 |
| **代码复用** | Extension 导入完整 `OmnivoreKit` SPM 包，复用认证和数据层 |

**关键代码路径**：
- `apple/Sources/ShareExtension/ShareExtensionViewController.swift`
- `apple/OmnivoreKit/Sources/App/AppExtensions/Share/`

**对 Folio 的启示**：Omnivore 的 Share Extension 比 Folio 更重（导入完整 OmnivoreKit），但好处是可以在 Extension 中直接编辑标签和添加备注。Folio 目前的轻量级方案（只存 URL）在内存管理上更安全，但可以考虑在 Extension 中增加简单的标签选择功能。

#### 2.3 本地存储与数据模型

| 维度 | 方案 |
|------|------|
| **持久化** | Core Data + SQLite（`NSPersistentContainer`，版本化迁移 `store-v002.sqlite`） |
| **搜索** | 完全服务端（PostgreSQL `pg_trgm` + 可选 Elasticsearch），本地仅存储最近搜索词 |
| **数据模型** | `LibraryItem`、`Highlight`、`LinkedItemLabel`、`RecentSearchItem`、`Viewer` |
| **离线策略** | `ServerSyncStatus` 枚举跟踪同步状态（`.isNSync`/`.isSyncing`/`.needsDeletion`/`.needsCreation`/`.needsUpdate`），`OfflineSync` 类定期推送未同步项 |
| **合并策略** | `NSMergePolicy.mergeByPropertyObjectTrump`（对象属性优先） |

**对 Folio 的启示**：Folio 使用 SwiftData（比 Core Data 更现代），且搜索在本地（FTS5），这是正确的方向。Omnivore 的搜索完全依赖服务端意味着离线时无法搜索。但 Omnivore 的 `ServerSyncStatus` 同步状态机设计值得 Folio 参考，比简单的离线队列更精细。

#### 2.4 阅读器实现

| 维度 | 方案 |
|------|------|
| **渲染方案** | **WKWebView** — 将 HTML 包裹为完整网页，通过 JavaScript bridge 交互 |
| **共享代码** | 阅读器 JS bundle (`bundle.js`) 与 Web 前端共享，实现了完整的高亮、标注、进度跟踪 |
| **Markdown 渲染** | 不使用 — 服务端返回 HTML，直接在 WebView 中渲染 |
| **排版自定义** | 字体、字号、行距、最大宽度、对齐方式、高对比度 — 全部通过 JS window 变量传递给 CSS |
| **代码块高亮** | highlight.js（内嵌在 `bundle.js` 中），支持明暗主题切换 |
| **图片** | HTML 原生 `<img>` 标签，图片 URL 指向服务端缓存 |
| **数学公式** | MathJax 支持 |

**关键代码路径**：
- `apple/OmnivoreKit/Sources/App/Views/WebReader/WebReader.swift` — WKWebView 包装
- `apple/OmnivoreKit/Sources/App/Views/WebReader/WebReaderContent.swift` — HTML 模板生成
- `apple/OmnivoreKit/Sources/App/Views/WebReader/WebReaderViewModel.swift` — 阅读器状态管理

**对 Folio 的启示**：WKWebView 方案的最大优势是 JavaScript 生态（highlight.js、MathJax、高亮标注）的复用成本极低。Folio 的原生 SwiftUI 渲染方案虽然体验更原生，但需要自行实现所有这些功能。这是一个经典的 build vs. buy 权衡。

#### 2.5 同步与网络层

| 维度 | 方案 |
|------|------|
| **协议** | GraphQL（通过 `swift-graphql` 库，类型安全） |
| **Schema 规模** | 自动生成的 `GQLSchema.swift` 约 1.35 MB，14 个查询文件 + 35 个变更文件 |
| **同步策略** | `updatesSince` 查询 + 游标分页（差量同步） |
| **离线队列** | `OfflineSync.swift` — 查找 `serverSyncStatus != isNSync` 的对象并推送 |
| **后台获取** | `FetchLinkedItemsBackgroundTask` — 对比服务器和本地 ID，补齐缺失项 |
| **认证** | Apple Sign-In + Google Sign-In + 邮箱注册，Token 存储用 Valet（Square 的 Keychain 封装） |

**对 Folio 的启示**：GraphQL 提供了强类型的客户端-服务端契约，但 1.35 MB 的自动生成代码是显著的维护负担。Folio 的 REST API 方案更简单轻量。但 Omnivore 的差量同步设计（`updatesSince` + cursor）值得参考。

#### 2.6 项目工程实践

| 维度 | 方案 |
|------|------|
| **架构模式** | MVVM（`@MainActor final class XxxViewModel: ObservableObject`） |
| **模块化** | SPM 本地包 `OmnivoreKit`，5 个 library target（App、Views、Services、Models、Utils） |
| **外部依赖** | swift-graphql、Valet、GoogleSignIn-iOS、SwiftUI-Introspect、swift-markdown-ui、posthog-ios、Transmission、PSPDFKit |
| **测试** | 未发现显著的单元测试覆盖（社区版本） |
| **CI/CD** | GitHub Actions |
| **特色功能** | TTS（Microsoft Cognitive Services 语音合成）、PDF 支持（PSPDFKit）、RSS 订阅、Newsletter 邮件摄入、AI Digest |

---

### 项目 2：Karakeep（原 Hoarder）

> **状态**：活跃开发中，2026-02 仍有提交。2024-02 创建，2025-04 从 Hoarder 更名为 Karakeep。

#### 2.1 内容提取方案

| 维度 | 方案 |
|------|------|
| **提取库** | `@mozilla/readability` ^0.6.0（原版 Mozilla Readability.js） |
| **提取位置** | 完全服务端（`@karakeep/workers` 包） |
| **JS 渲染页面** | **Playwright** ^1.58.2（headless Chrome）+ `puppeteer-extra-plugin-stealth` + `@ghostery/adblocker-playwright` |
| **元数据提取** | `metascraper` ^5.49.5 + 大量插件（author, date, title, image, publisher 等） |
| **提取结果格式** | HTML（经 `dompurify` 清洗） |
| **图片处理** | 下载到本地文件系统或 S3 兼容存储 |
| **全页存档** | `monolith`（外部二进制）— 单文件 HTML 完整存档 |
| **视频** | `yt-dlp` 视频下载存档 |
| **OCR** | `tesseract.js` ^7.0.0 — 图片和扫描 PDF 的文字提取 |

**对 Folio 的启示**：Karakeep 的 `metascraper` 插件体系非常丰富，特别是针对 Twitter/X、YouTube、Amazon 等平台的专用提取器。Folio 的 reader 服务目前是通用提取，可以考虑为特定平台（微信公众号、推特）添加专用提取规则。

#### 2.2 Share Extension 实现

| 维度 | 方案 |
|------|------|
| **方案** | `expo-share-intent` v5.1.1（React Native Expo 插件） |
| **工作流** | 接收系统分享 → 通过 tRPC 发送到自托管服务器 |
| **UI** | React Native 渲染，非原生 |

**对 Folio 的启示**：React Native 的 Share Extension 体验和性能不如原生，这是 Folio 的差异化优势之一。

#### 2.3 本地存储与数据模型

| 维度 | 方案 |
|------|------|
| **服务端数据库** | SQLite（`better-sqlite3` + Drizzle ORM），单文件，无需 PostgreSQL |
| **客户端存储** | Zustand 状态 + @tanstack/react-query 缓存 + `expo-secure-store` |
| **搜索** | **Meilisearch** v1.13.3（独立容器，Rust 实现，支持容错搜索） |
| **任务队列** | `liteque`（SQLite-based 队列，无需 Redis） |

**对 Folio 的启示**：Karakeep 的「全 SQLite」方案（数据库 + 任务队列都用 SQLite）极大简化了部署，但牺牲了并发能力。Folio 的 PostgreSQL + Redis 方案更适合多用户场景。Meilisearch 的容错搜索（typo tolerance）是一个有价值的功能点。

#### 2.4 阅读器实现

| 维度 | 方案 |
|------|------|
| **渲染方案** | `react-native-webview` + `react-native-markdown-display` |
| **PDF** | `react-native-pdf` |
| **列表性能** | `@shopify/flash-list` |

**对 Folio 的启示**：Karakeep 的阅读器体验相对简单，没有高亮标注等高级功能。Folio 的原生 SwiftUI 渲染在阅读体验上有明显优势。

#### 2.5 同步与网络层

| 维度 | 方案 |
|------|------|
| **协议** | tRPC（端到端类型安全 RPC，TypeScript 共享类型） |
| **认证** | NextAuth（支持密码、OAuth/SSO、Cloudflare Turnstile） |
| **安全存储** | `expo-secure-store` |

#### 2.6 项目工程实践

| 维度 | 方案 |
|------|------|
| **架构** | Turborepo + pnpm workspaces 单仓多包 |
| **Linting** | oxlint（非 ESLint，更快） |
| **测试** | Vitest |
| **监控** | OpenTelemetry + Prometheus |
| **特色功能** | AI 自动打标签/摘要（OpenAI/Ollama）、全页存档（monolith）、视频存档（yt-dlp）、OCR（tesseract.js）、RSS 自动导入、规则引擎、协作列表、Webhook |

---

### 项目 3：Wallabag

> **状态**：最成熟的项目，2013 年至今，248+ 贡献者，持续维护。

#### 2.1 内容提取方案

| 维度 | 方案 |
|------|------|
| **提取库** | **三层提取**：(1) `ftr-site-config`（域名专用 XPath 规则）→ (2) `php-readability`（PHP 版 Readability）→ (3) 回退策略 |
| **提取位置** | 完全服务端（PHP Symfony） |
| **站点规则** | `fivefilters/ftr-site-config` — 社区维护的大量域名专用提取规则（XPath 选择器） |
| **提取结果格式** | HTML |
| **图片处理** | 可配置下载到本地 |

**对 Folio 的启示**：Wallabag 的三层提取策略（站点专用规则 → 通用 Readability → 回退）是最健壮的方案。对于微信公众号等特殊站点，Folio 可以借鉴这种「站点规则」机制，为特定域名定义专用提取逻辑。

#### 2.2 Share Extension 实现

| 维度 | 方案 |
|------|------|
| **iOS App** | [github.com/wallabag/ios-app](https://github.com/wallabag/ios-app)（205 stars，MIT） |
| **技术栈** | Swift (UIKit)，iOS 17.0+ |
| **功能** | Share Extension 从 Safari 添加文章、离线阅读、打标签、暗黑模式 |
| **最新版本** | v7.5.2（2025-02） |

#### 2.3 本地存储与数据模型

| 维度 | 方案 |
|------|------|
| **服务端数据库** | PostgreSQL / MySQL / SQLite |
| **iOS 持久化** | 未详细调查，推测 Core Data（UIKit 时代的标准方案） |
| **搜索** | 服务端 PostgreSQL 全文搜索 |

#### 2.4 阅读器实现

| 维度 | 方案 |
|------|------|
| **渲染方案** | 推测 WKWebView（UIKit 架构，服务端返回 HTML） |
| **自定义** | 暗黑模式支持 |

#### 2.5 同步与网络层

| 维度 | 方案 |
|------|------|
| **协议** | REST API |
| **认证** | OAuth 2.0 |

#### 2.6 项目工程实践

| 维度 | 方案 |
|------|------|
| **架构** | UIKit，传统 MVC/MVVM |
| **测试** | 有一定覆盖 |
| **国际化** | Weblate 多语言 |
| **生态** | 最丰富 — iOS、Android、GNOME 桌面、浏览器扩展、导入/导出工具、RSS 生成 |

---

### 项目 4：Readeck

> **状态**：活跃开发中，Go 后端 + SwiftUI iOS，架构最接近 Folio。

#### 2.1 内容提取方案

| 维度 | 方案 |
|------|------|
| **提取库** | `go-readability`（Readeck 自维护的 fork，Go 语言逐行移植 Mozilla Readability.js v0.6） |
| **提取位置** | 完全服务端（Go） |
| **内容脚本** | 支持用户自定义 JavaScript (ES5) 脚本，分两个 hook：`documentReady`（readability 前）和 `documentDone`（readability 后） |
| **提取结果格式** | HTML，所有图片和文本在保存时下载到本地 |
| **存储格式** | 每个书签存储为**不可变 ZIP 文件**，包含 HTML、图片和元数据。按需转换为网页或 EPUB |
| **图片处理** | 保存时下载到本地（隐私优先，阅读时不请求外部资源） |

**对 Folio 的启示**：Readeck 的 `go-readability` 是纯 Go 实现的 Readability.js 移植，理论上可以直接集成到 Folio 的 Go 后端中，减少对 Node.js reader 服务的依赖。这是一个值得探索的方向。

#### 2.2 Share Extension 实现

| 维度 | 方案 |
|------|------|
| **iOS App** | [codeberg.org/readeck/readeck-ios](https://codeberg.org/readeck/readeck-ios)（13 stars，MIT） |
| **技术栈** | Swift (100%), SwiftUI |
| **功能** | Share Extension 添加 URL、离线阅读（可配置缓存 5-100 篇文章）、高亮标注（4 色）、iPad 分栏、暗黑模式、字体自定义 |
| **Layout** | 紧凑/杂志/自然三种布局样式 |

#### 2.3 本地存储与数据模型

| 维度 | 方案 |
|------|------|
| **服务端数据库** | SQLite（推荐）或 PostgreSQL |
| **iOS 持久化** | SwiftUI/Swift 原生方案（具体待深入调查） |
| **搜索** | 服务端全文搜索 |
| **离线** | 后台同步，可配置缓存文章数量 |

#### 2.4 阅读器实现

| 维度 | 方案 |
|------|------|
| **渲染方案** | SwiftUI 原生（推测，基于 100% Swift 代码库） |
| **排版自定义** | 字体自定义 |
| **高亮** | 4 色高亮标注 |

#### 2.5 同步与网络层

| 维度 | 方案 |
|------|------|
| **协议** | REST API |
| **离线** | 后台同步，可配置缓存量 |

#### 2.6 项目工程实践

| 维度 | 方案 |
|------|------|
| **后端特色** | EPUB 导出、OPDS 目录（电子阅读器兼容）、集合（保存的搜索查询）、浏览器扩展 |
| **部署** | 单 Go 二进制文件，极其轻量 |

---

### 项目 5：Linkwarden

> **状态**：活跃开发中，协作式书签管理。

#### 2.1 内容提取方案

| 维度 | 方案 |
|------|------|
| **提取方式** | 自动截图 + PDF 生成 + 单文件 HTML 存档（三重保存） |
| **目的** | 对抗链接腐烂（link rot），确保内容永久保存 |

#### 2.2-2.6 其他维度

| 维度 | 方案 |
|------|------|
| **iOS 客户端** | React Native，App Store 上架 |
| **后端** | TypeScript/Next.js |
| **存储** | PostgreSQL + S3 兼容存储 |
| **特色** | 协作管理、标签和集合、RSS 导入 |

---

## 第三阶段：对标 Folio 的差距分析

### 3.1 特性对比矩阵

| 特性 | Folio 现状 | Omnivore | Karakeep | Wallabag | Readeck | 最佳实践 |
|------|-----------|----------|----------|----------|---------|---------|
| **内容提取** | 服务端 Node.js（`@vakra-dev/reader`） | 服务端 Puppeteer + fork Readability.js | 服务端 Playwright + Readability.js + metascraper | 服务端 PHP Graby + 站点规则 | 服务端 Go go-readability | Wallabag 的三层提取（站点规则→Readability→回退）最健壮 |
| **Share Extension** | 原生 SwiftUI，存 URL + 离线队列 | 原生 UIKit+SwiftUI，可编辑标签/备注 | React Native expo-share-intent | 原生 Swift，存文章 | 原生 SwiftUI | Omnivore 的可编辑标签 Share Extension 体验最好 |
| **本地搜索** | SQLite FTS5（完全本地） | 完全服务端（PostgreSQL + ES） | Meilisearch（独立服务） | 服务端 PostgreSQL | 服务端全文搜索 | **Folio 是唯一支持完全离线搜索的** |
| **阅读器渲染** | SwiftUI + apple/swift-markdown | WKWebView + bundle.js | react-native-webview | WKWebView（推测） | SwiftUI 原生（推测） | WKWebView 功能丰富（高亮/MathJax），SwiftUI 体验更原生 |
| **代码块高亮** | 无（纯白色文本） | highlight.js（通过 WebView） | react-native-markdown-display | N/A | N/A | HighlightSwift 是 SwiftUI 原生最佳选择 |
| **离线支持** | SwiftData + OfflineQueueManager | Core Data + OfflineSync | Zustand + react-query | Core Data + 本地缓存 | SwiftUI + 后台同步 | Omnivore 的 ServerSyncStatus 状态机最精细 |
| **分类/标签** | AI 自动分类（DeepSeek，9 类） | 手动标签 | **AI 自动打标签**（OpenAI/Ollama） | 手动标签 | 手动标签 | Folio + Karakeep 有 AI 分类，Folio 的 9 类预设+DeepSeek 更轻量 |
| **AI 摘要** | 服务端 DeepSeek 摘要 | AI Digest（后期加入） | AI 摘要（可选） | 无 | 无 | Folio 和 Karakeep 都有，Folio 的单次 API 调用更高效 |
| **排版自定义** | 3 字体族 + 字号/行距/4主题 | 字体/字号/行距/宽度/对齐/4主题 | 基础 | 暗黑模式 | 字体自定义 | Omnivore 最全面 |
| **高亮标注** | 无 | 完整（多色+批注+笔记本） | 基础高亮 | 无 | 4 色高亮 | Omnivore 的 JS-based 高亮是最成熟的方案 |
| **TTS 朗读** | 无 | 有（Microsoft Cognitive Services） | 无 | 无 | 无 | Omnivore 独有，也是被 ElevenLabs 收购的原因之一 |
| **数据模型** | Article/Tag/Category/User | LibraryItem/Highlight/Label/Viewer | Bookmark/Tag/List | Article/Tag/User | Bookmark/Label | Folio 的 Category 预设是差异化设计 |
| **同步协议** | REST (chi) | GraphQL (swift-graphql) | tRPC | REST | REST | REST 最简单，GraphQL 类型安全但复杂 |
| **iOS 部署目标** | iOS 17.0 | iOS 15.0 | N/A (React Native) | iOS 17.0 | iOS（具体版本待确认） | iOS 17 合理 |
| **全页存档** | 无 | 无 | monolith + yt-dlp | 无 | ZIP 存档 | Karakeep 和 Readeck 的存档方案值得参考 |

### 3.2 可直接借鉴的实现

#### 借鉴 1：代码块语法高亮 — HighlightSwift

- **解决问题**：Folio 的 `CodeBlockView` 当前无语法高亮（纯白色文本），阅读体验差
- **推荐方案**：集成 [HighlightSwift](https://github.com/appstefan/HighlightSwift)（MIT 许可，SwiftUI 原生）
- **竞品参考**：Omnivore 使用 highlight.js（通过 WKWebView），HighlightSwift 底层也是 highlight.js 但通过 JavaScriptCore 调用，无需 WKWebView
- **改动量**：**小** — 修改 `CodeBlockView.swift`，将 `Text(code)` 替换为 `CodeText(code)`

```swift
// 当前 Folio 实现
Text(code)
    .font(Typography.articleCode)
    .foregroundStyle(.white.opacity(0.9))

// 建议改为
CodeText(code)
    .codeTextLanguage(.init(rawValue: language))
    .codeTextTheme(.atomOneDark)
    .font(Typography.articleCode)
```

#### 借鉴 2：Markdown 渲染引擎升级 — 评估 Textual

- **解决问题**：Folio 当前使用 apple/swift-markdown + 自研 `MarkdownSwiftUIVisitor` 生成 `[AnyView]`，长文章性能可能退化，且 `AnyView` 阻碍 SwiftUI 差异化优化
- **推荐方案**：评估 [gonzalezreal/textual](https://github.com/gonzalezreal/textual)（MarkdownUI 的继任者，2025 年新项目）
- **Textual 优势**：内置语法高亮、数学公式渲染、原生文本选择/复制、动画图片支持、性能优于 MarkdownUI
- **竞品参考**：Omnivore 使用 MarkdownUI（swift-markdown-ui 2.0.0+）作为依赖，但主阅读器用 WKWebView
- **改动量**：**大** — 需要重构 `MarkdownRenderer.swift` 的渲染逻辑
- **建议**：先做性能基准测试，如果当前方案在长文章上确实有问题再考虑迁移

#### 借鉴 3：站点专用提取规则 — 借鉴 Wallabag 的 ftr-site-config

- **解决问题**：微信公众号、特定新闻站等需要特殊提取逻辑
- **推荐方案**：在 Folio 的 reader 服务中增加域名规则匹配层
- **源项目**：Wallabag 的 [fivefilters/ftr-site-config](https://github.com/fivefilters/ftr-site-config) — 社区维护的 XPath 规则库
- **改动量**：**中** — 需要在 reader-service 中增加规则引擎，但可以渐进式实现

#### 借鉴 4：SPM 本地包模块化 — 借鉴 Omnivore 的 OmnivoreKit

- **解决问题**：Folio 目前是单 Target 结构，随着功能增长可能需要更好的模块化
- **推荐方案**：参考 Omnivore 的 `OmnivoreKit` SPM 本地包架构（App/Views/Services/Models/Utils 5 个 target）
- **源项目**：`apple/OmnivoreKit/Package.swift`
- **改动量**：**大** — 重构项目结构，但可以渐进式抽取

#### 借鉴 5：同步状态机 — 借鉴 Omnivore 的 ServerSyncStatus

- **解决问题**：Folio 的 OfflineQueueManager 是简单的队列，缺少精细的同步状态跟踪
- **推荐方案**：参考 Omnivore 的 `ServerSyncStatus` 枚举设计（`.isNSync`/`.isSyncing`/`.needsDeletion`/`.needsCreation`/`.needsUpdate`）
- **源项目**：`apple/OmnivoreKit/Sources/Models/DataModels/LibraryItem.swift`
- **改动量**：**中** — 需要扩展 SwiftData 模型和 SyncService

#### 借鉴 6：图片预取 — 利用 Nuke 的 ImagePrefetcher

- **解决问题**：离线阅读时图片可能无法加载
- **推荐方案**：文章保存/同步时，使用 Nuke 的 `ImagePrefetcher` 预取所有图片 URL 到磁盘缓存
- **参考**：Readeck 的「保存时下载所有资源到本地」设计理念
- **改动量**：**小** — 在 SyncService 中添加图片预取逻辑

### 3.3 Folio 的差异化优势确认

通过调研确认，以下是 Folio 独有或领先的特性：

1. **AI 自动分类（9 类预设）**：只有 Karakeep 也有 AI 标签功能，但 Karakeep 是自由标签，Folio 的 9 类预设体系更结构化
2. **单次 AI 调用**：分类 + 标签 + 摘要 + 关键点合并为一次 DeepSeek 请求，Karakeep 需要多次调用
3. **完全本地搜索（FTS5）**：所有竞品的搜索都依赖服务端，Folio 是唯一支持完全离线全文搜索的
4. **原生 SwiftUI 渲染**：对比 Omnivore 的 WKWebView 和 Karakeep 的 React Native，Folio 的阅读体验最原生
5. **轻量级混合架构**：Go 后端（单进程 API+Worker）+ Node.js reader + Python AI，比 Omnivore 的微服务群和 Karakeep 的单体 monorepo 更灵活
6. **离线优先设计**：Share Extension 立即写本地 SwiftData，无需等待网络，比 Omnivore 的「Extension 中发 GraphQL」更可靠

---

## 第四阶段：结论与建议

### 4.1 技术选型建议

| 模块 | 推荐参考项目 | 具体建议 |
|------|------------|---------|
| **代码块高亮** | Omnivore (highlight.js) | 集成 HighlightSwift，成本极低，效果显著 |
| **Markdown 渲染** | Omnivore (WKWebView) / 独立 (Textual) | 短期维持现有方案，长期评估 Textual；如需高亮标注功能则考虑 WKWebView 混合方案 |
| **站点专用提取** | Wallabag (ftr-site-config) | 为微信公众号等高优站点添加专用提取规则 |
| **同步状态管理** | Omnivore (ServerSyncStatus) | 扩展离线队列为精细状态机 |
| **图片离线缓存** | Readeck (保存时下载) | 文章同步时预取图片 |
| **项目模块化** | Omnivore (OmnivoreKit SPM) | 随功能增长渐进式拆分 |

### 4.2 风险点

| 风险 | 说明 | 缓解措施 |
|------|------|---------|
| **Omnivore 代码腐化** | 项目已归档，依赖版本可能过时，社区维护不确定 | 参考设计思路而非直接复制代码，关注 fork 社区活跃度 |
| **AGPL-3.0 许可证** | Omnivore、Karakeep、Readeck 均为 AGPL-3.0，直接使用代码有传染风险 | 仅参考设计模式和架构思路，不直接复制代码。HighlightSwift、Textual 等第三方库均为 MIT |
| **Textual 库成熟度** | 2025 年新项目，社区采用率低 | 先在非关键路径上试用，确认稳定性后再全面迁移 |
| **WKWebView 方向抉择** | 如果未来需要高亮标注功能，可能需要切换到 WKWebView | 设计时保持渲染层可替换，预留 WebView 方案空间 |

### 4.3 优先级排序 — Top 3 最值得投入的模块

#### P0：代码块语法高亮（集成 HighlightSwift）
- **投入**：1-2 天
- **收益**：立即可见的阅读体验提升，技术文章的核心需求
- **风险**：极低

#### P1：图片预取与离线阅读增强
- **投入**：2-3 天
- **收益**：完善离线阅读体验，解决离线时图片缺失问题
- **风险**：低，Nuke 已内置相关 API

#### P2：特定站点提取规则（微信公众号优先）
- **投入**：3-5 天
- **收益**：解决高频用户场景的提取质量问题
- **风险**：中，需要持续维护规则

### 4.4 Action Items

- [ ] **短期（1-2 周）**
  - [ ] 集成 HighlightSwift 到 `CodeBlockView`，支持代码语法高亮
  - [ ] 在 SyncService 中添加 `ImagePrefetcher` 图片预取
  - [ ] 评估当前 Markdown 渲染在长文章（>5000 字）上的性能表现

- [ ] **中期（1-2 月）**
  - [ ] 研究 Wallabag 的 ftr-site-config 机制，为微信公众号添加专用提取规则
  - [ ] 评估 Textual 库的成熟度，考虑作为渲染引擎的替代方案
  - [ ] 参考 Omnivore 的 `ServerSyncStatus` 优化同步状态管理

- [ ] **长期（视需求）**
  - [ ] 如需高亮标注功能，评估 WKWebView 混合方案的可行性
  - [ ] 考虑 SPM 本地包模块化（当源文件超过 100 个时）
  - [ ] 评估 go-readability 替换/补充 Node.js reader 服务的可能性

---

## 附录：iOS 阅读器渲染方案对比

### 渲染方案总览

| 方案 | 使用者 | 长文性能 | 原生感 | 实现成本 | 语法高亮 | 高亮标注 |
|------|--------|---------|--------|---------|---------|---------|
| WKWebView | Omnivore, Readwise | 好 | 中 | 低 | 简单（highlight.js） | 简单（JS） |
| 原生 SwiftUI | Folio, Bear | 中（长文退化） | 优秀 | 高 | 需第三方库 | 复杂 |
| AttributedString | 聊天应用 | 好 | 好 | 中 | 中等 | 中等 |
| iOS 26 WebPage | 未来 | 好 | 好 | 低 | 简单 | 简单 |

### Markdown 渲染库对比

| 库 | 解析器 | 渲染器 | SwiftUI 原生 | 性能 | 语法高亮 | 状态 |
|----|--------|--------|-------------|------|---------|------|
| apple/swift-markdown | cmark-gfm | 无（自行实现） | N/A | 解析快 | 无 | 活跃 |
| MarkdownUI | cmark-gfm | SwiftUI 视图 | 是 | 长文卡顿 | 基础 | **维护模式** |
| **Textual** | Foundation | SwiftUI Text 管线 | 是 | 好 | **内置** | 活跃（新） |
| Down | cmark | NSAttributedString/WKWebView | 否 | 极快 | 无 | 维护中 |

### 代码高亮库对比

| 库 | 语言数 | 引擎 | SwiftUI 集成 | 输出 | 状态 |
|----|--------|------|-------------|------|------|
| **HighlightSwift** | 50+ | highlight.js (JavaScriptCore) | `CodeText` 视图 | `AttributedString` | **活跃，推荐** |
| Highlightr | 185 | highlight.js 9.13.4 (JavaScriptCore) | 无（UIKit） | `NSAttributedString` | 不再维护 |
| HighlighterSwift | 同 Highlightr | highlight.js 11.9.0 | 无 | `NSAttributedString` | 维护中 |
| Splash | 仅 Swift | 自研 | 有 | `AttributedString` | 不再维护 |

### 图片加载库对比

| 库 | SwiftUI 支持 | 内存效率 | 任务合并 | Stars |
|----|-------------|---------|---------|-------|
| **Nuke（Folio 当前）** | `LazyImage`（原生） | 最优（~40MB 少于 Kingfisher） | 是（去重相同请求） | 8.3k |
| Kingfisher | `KFImage` | 较高 | 否 | 23k |
| SDWebImage | `WebImage` | 低 | 有限 | 25k |

**结论**：Nuke 是 Folio 的正确选择，无需更换。

---

## 参考资源

### 项目仓库
- [Omnivore](https://github.com/omnivore-app/omnivore)
- [Karakeep (Hoarder)](https://github.com/karakeep-app/karakeep)
- [Wallabag](https://github.com/wallabag/wallabag) | [iOS App](https://github.com/wallabag/ios-app)
- [Readeck](https://codeberg.org/readeck/readeck) | [iOS App](https://codeberg.org/readeck/readeck-ios)
- [Linkwarden](https://github.com/linkwarden/linkwarden)
- [Shiori](https://github.com/go-shiori/shiori)
- [Linkding](https://github.com/sissbruecker/linkding)
- [Linkeeper](https://github.com/OmChachad/Linkeeper)

### 库和工具
- [HighlightSwift](https://github.com/appstefan/HighlightSwift) — SwiftUI 代码高亮
- [Textual](https://github.com/gonzalezreal/textual) — MarkdownUI 继任者
- [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) — 维护模式
- [apple/swift-markdown](https://github.com/apple/swift-markdown) — Folio 当前使用
- [Nuke](https://github.com/kean/Nuke) — Folio 当前使用
- [go-readability](https://codeberg.org/readeck/go-readability) — Go 版 Readability.js
- [ftr-site-config](https://github.com/fivefilters/ftr-site-config) — 站点提取规则库
- [reeeed](https://github.com/nate-parrott/reeeed) — SwiftUI 阅读模式库

### 文章和讨论
- [ElevenLabs 收购 Omnivore 公告](https://elevenlabs.io/blog/omnivore-joins-elevenlabs)
- [TechCrunch: ElevenLabs Hired the Omnivore Team](https://techcrunch.com/2024/10/29/elevenlabs-has-hired-the-team-behind-omnivore-a-reader-app/)
- [Omnivore is Dead: Where to Go Next](https://molodtsov.me/2024/10/omnivore-is-dead-where-to-go-next/)
- [WebKit in SwiftUI (WWDC 2025)](https://medium.com/@shubhamsanghavi100/webkit-is-now-native-in-swiftui-finally-a-first-class-webview-wwdc-2025-9f4a3a3e222f)
