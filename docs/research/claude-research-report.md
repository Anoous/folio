# 开源「稍后读」iOS 应用深度技术研究报告

**Folio（页集）** 可从五个头部开源项目中借鉴关键实现：Omnivore 的 SPM 模块化与 GraphQL 层、Wallabag iOS 的 Share Extension 实战经验、NetNewsWire 的 HTML 模板 + WKWebView 主题渲染管线、Hipstapaper 的纯 SwiftUI 标识符导航架构，以及 reeeed 的双解析器回退策略。最关键的发现是 **lake-of-fire/swift-readability**（纯 Swift Readability 移植）可在 Share Extension 的 120MB 内存限制内完成客户端内容提取——这是 Omnivore 和 Wallabag 都未实现的能力，也正是 Folio 本地优先架构的核心差异化优势。

---

## Phase 1：项目筛选与全景图

经过对 GitHub、GitLab、awesome-selfhosted、awesome-ios 等来源的全面搜索，共发现 15+ 个相关项目。按筛选标准（原生 iOS 客户端、Stars ≥ 500 或代码量充实、具备内容提取、近两年活跃、开源许可）筛选后，入围项目如下：

| 项目 | GitHub URL | Stars | 许可证 | 最近活跃 | 技术栈（iOS） | 一句话描述 |
|------|-----------|-------|--------|---------|-------------|-----------|
| **Omnivore** | github.com/omnivore-app/omnivore | ~15,900 | AGPL-3.0 | 社区维护中（2024.11 团队被 ElevenLabs 收购） | Swift / SwiftUI / Core Data / SwiftGraphQL | 功能最完整的开源稍后读，含原生 iOS + 服务端 Readability 提取 |
| **Wallabag iOS** | github.com/wallabag/ios-app | ~205（服务端 12,500） | MIT | 2026.02 活跃 | Swift / SwiftUI 2 / Core Data / WallabagKit | 最成熟的自托管稍后读 iOS 原生客户端 |
| **NetNewsWire** | github.com/Ranchero-Software/NetNewsWire | ~8,400+ | MIT | 2026.02（v7.0 发布） | Swift / UIKit / SQLite(FMDB) / 多 Framework | 最精良的开源 iOS 阅读应用，模板化文章渲染系统 |
| **Hipstapaper** | github.com/jeffreybergier/Hipstapaper | ~91 | MIT | 近一年内活跃 | 100% SwiftUI / Core Data + CloudKit / 多 SPM 包 | 纯 SwiftUI 的 Instapaper 克隆，架构设计极具参考价值 |
| **reeeed** | github.com/nate-parrott/reeeed | ~175 | MIT | 可用 | SwiftUI / SwiftSoup + Fuzi / Mercury + Readability.js | 即插即用的 SwiftUI Reader Mode 组件库 |
| **Readeck iOS** | codeberg.org/readeck/readeck-ios | ~28 | MIT | 2025.11（Beta） | Swift / SwiftUI / URLShare Extension | 面向 Go 后端 Readeck 的原生 iOS 客户端 |
| **Luego** | github.com/esoxjem/Luego | ~5 | MIT | 活跃 | SwiftUI / SwiftData / Clean Architecture | 最现代技术栈的本地优先稍后读 App |
| **Karakeep** | github.com/karakeep-app/karakeep | ~22,900 | AGPL-3.0 | 2026.02 非常活跃 | React Native / Expo（非原生 Swift） | AI 自动标签+全文搜索的书签管理器，功能参考价值高 |

**关键发现**：原生 Swift/SwiftUI 的稍后读 iOS 客户端极为稀缺。市场上大量新项目（Karakeep、Linkwarden）选择了 React Native 跨平台方案。Omnivore 曾是功能最完整的原生方案，但已被收购；Wallabag iOS 是目前最成熟的活跃原生客户端。这意味着 **Folio 选择原生 SwiftUI 路线本身就是一个重要的差异化定位**。

---

## Phase 2：Top 5 项目六维深度分析

### 内容提取：服务端主导，客户端是蓝海

五个头部项目的内容提取策略惊人地一致——**全部依赖服务端**。Omnivore 使用 Puppeteer + Mozilla Readability.js 在服务端用无头浏览器提取；Wallabag 使用 PHP 的 Graby + php-readability + ftr-site-config（社区维护的数千个站点专属规则）；NetNewsWire 依赖 RSS Feed 本身提供的内容。没有任何一个项目在 iOS 端实现了完整的内容提取。

Wallabag v7.4.0 是唯一的例外——PR #420 在 Share Extension 中增加了从 Safari 分享时提取页面 title 和 content 的能力，但这只是辅助加速服务端处理，并非独立提取。

这个现状为 Folio 开辟了独特的技术路线：使用 **lake-of-fire/swift-readability**（纯 Swift 移植的 Mozilla Readability v0.6.0），可以在 Share Extension 内完成**客户端侧内容提取**。该库依赖 SwiftSoup 进行 DOM 解析，无需 WKWebView，典型文章（50-200KB HTML）内存消耗约 **5-20MB**，完整提取流水线峰值约 **35-65MB**，远低于 120MB 限制。而 reeeed 库提供了另一种思路——使用隐藏 WKWebView 同时运行 Mercury Parser 和 Readability.js 双解析器，extraction 质量更高但内存风险也更大。

**输出格式对比**：Omnivore 和 Wallabag 均以 HTML 存储提取内容；Luego 转换为 Markdown 存储并用 MarkdownUI 渲染；Folio 当前的服务端 HTML→Markdown 路线与 Luego 类似。客户端侧可使用 SwiftHTMLToMarkdown 库完成 HTML→Markdown 转换。

### Share Extension 实现：极简主义是共识

| 维度 | Omnivore | Wallabag | Hipstapaper | Readeck iOS | Luego |
|------|---------|---------|------------|------------|-------|
| 保存策略 | 仅发送 URL 到服务端 | URL + 可选 title/content 发送到服务端 | URL→WKWebView 提取标题+截图→Core Data | URL 发送到服务端 API | URL→本地提取→SwiftData |
| UI 复杂度 | 极简确认 + 标签选择 | 极简灰色弹窗，无标签编辑 | SPM 包内共享 UI | 带标题编辑和标签管理 | 基础确认 |
| 数据共享 | App Group（Auth Token 共享） | App Group（OAuth 凭证共享） | SPM Package + Core Data 共享容器 | App Group + Keychain | App Group + SwiftData 共享容器 |
| 离线处理 | 需联网（发送到服务端） | 需联网（无离线队列） | 本地保存（Core Data + CloudKit） | 有离线队列（重连后同步） | 本地保存（SwiftData） |
| 内存管理 | 极低（仅网络请求） | 极低（仅网络请求） | 中等（WKWebView 加载页面） | 低（仅 API 调用） | 中等（本地提取） |

**核心发现**：Omnivore 和 Wallabag 的 Share Extension 都极度轻量——只捕获 URL 后立即发送到服务端，将所有重活交给后端处理。这是在内存限制下的务实选择，但也意味着**断网时无法保存内容**。Readeck iOS 的离线队列模式值得 Folio 借鉴——保存 URL 和基础元数据到本地队列，重连后批量同步。而 Folio 可以走得更远：在 Extension 内直接完成轻量提取（纯 Swift Readability），实现真正的**离线即保存即可读**。

### 本地存储与数据模型：从 Core Data 到 SwiftData 的迁移趋势

**Omnivore** 使用 Core Data，数据模型包括 `LinkedItem`（文章主实体，含 title、url、content HTML、readingProgress、wordsCount、estimatedReadingTime 等）、`LinkedItemLabel`（标签，多对多关系）、`Highlight`（高亮标注，含 quote、annotation、patch/prefix/suffix 锚点定位）、`SavedFilter`（搜索过滤器）。

**Wallabag iOS** 同样使用 Core Data，`Entry` 实体映射 API 响应的完整字段（id、title、url、content HTML、isArchived、isStarred、readingTime、tags 关系等），`Tag` 实体有 id/label/slug。

**NetNewsWire** 独树一帜地选择了 **SQLite + FMDB**（通过自研 RSDatabase 框架），明确拒绝 Core Data。其 `Article` 模型包含 articleID、feedID、uniqueID、title、contentHTML、contentText、url、summary、imageURL、authors、tags、attachments 等字段。每个 Account 有独立的 SQLite 数据库文件。

**Luego** 是唯一使用 **SwiftData** 的项目，数据模型基于 `@Model` 宏，与 Folio 的技术选型最接近。

**全文搜索**：NetNewsWire 使用 SQLite 内置搜索（timeline 和 global 两种范围）；Omnivore 主要依赖服务端搜索；Wallabag 使用 Core Data 的 NSPredicate 文本匹配。五个项目中**没有一个在客户端实现了 SQLite FTS5 全文检索**——这是 Folio 使用 SwiftData + SQLite FTS5 的另一个差异化优势。

### 阅读器渲染：WKWebView 统治地位 vs 原生 Markdown 新路线

**主流方案是 WKWebView + HTML/CSS 注入**。Omnivore 将服务端提取的 HTML 加载到 WKWebView 中，通过 WKScriptMessageHandler 实现双向 JS Bridge（文本选择→高亮、滚动位置→阅读进度、主题/字体切换）。Wallabag iOS 同样使用 WKWebView + 自定义 CSS 主题注入。

NetNewsWire 的方案最精致——**模板化 HTML 渲染管线**：
1. `.nnwtheme` 主题包含 `template.html` + `stylesheet.css` + `Info.plist`
2. `ArticleRenderer.swift` 通过 `MacroProcessor` 宏替换将文章数据注入 HTML 模板
3. 运行时 CSS 分层：`core.css`（结构）+ `stylesheet.css`（视觉主题）
4. `ArticleThemesManager` 单例管理主题生命周期，实现 NSFilePresenter 监听主题文件变更
5. 自定义 URL Scheme Handler 在 WKWebView 中服务本地资源（如 Feed 图标）
6. 平台特定 JS：`main.js` + `main_ios.js` + `newsfoot.js`（脚注处理）

**Luego 走了完全不同的路线**——将内容转为 Markdown 后用 MarkdownUI 进行纯 SwiftUI 原生渲染，完全避开 WKWebView。这与 Folio 当前使用 apple/swift-markdown 的方向一致。

**MarkdownUI**（3,743 stars）提供了完善的主题系统，支持自定义每个 Markdown 元素的样式（字体、间距、颜色、代码块背景等），内置 `.gitHub` 和 `.docC` 预设主题。注意该库已进入**维护模式**，后继者是 **Textual**（支持 LaTeX 数学公式、文本选择、更现代的 API），但 Textual 仍处于早期阶段（7 commits）。

### 同步与网络层：架构抽象是关键

**Omnivore** 使用 SwiftGraphQL 代码生成 + GraphQL API，关键 Mutation 包括 `SaveUrl`（保存）、`SetLabels`（标签）、`CreateHighlight`（高亮）、`SaveArticleReadingProgress`（进度），使用 `clientRequestId` UUID 确保幂等性。

**Wallabag iOS** 使用 REST API + OAuth 2.0（Resource Owner Password Credentials 授权），通过分页 `/api/entries.json` 端点拉取文章。WallabagKit SDK 已归档并集成进主应用代码。同步采用简单的 pull-to-refresh 策略。

**NetNewsWire** 的设计最值得借鉴——**Account + AccountDelegate 协议抽象**。`Account` 类不可被继承，通过 `AccountDelegate` 协议实现多种同步后端（Local、iCloud/CloudKit、Feedbin REST、Feedly REST、NewsBlur REST、FreshRSS/Inoreader Google Reader API 等）。`AccountManager` 在启动时遍历 Accounts/ 文件夹创建实例，始终维持一个默认本地账户。`SyncDatabase.framework` 用独立 SQLite 文件跟踪同步进度。这种**解耦设计使得添加新同步后端只需实现一个协议**。

### 工程实践：模块化程度差异显著

**架构模式对比**：

| 项目 | 架构 | 模块化 | 测试 | CI/CD |
|------|------|--------|------|-------|
| Omnivore | MVVM + Services | OmnivoreKit 单 SPM 包 | iOS/Mac 分离测试计划 | SwiftFormat |
| Wallabag iOS | MVC→SwiftUI 迁移（混合） | 单 Target + Entity/Model/Lib 目录 | Fastlane 截图 UI 测试 | Fastlane + GitHub Actions |
| NetNewsWire | 分层 Framework 架构 | 5 个 Git Submodule + 4 个 Framework | 有单元测试 | 有 |
| Hipstapaper | 无 ViewModel 的纯 SwiftUI | 7+ 个 SPM Package 严格分层 | 依赖边界即测试 | - |
| reeeed | 库设计 | 单 SPM Package | ReeeedTests | - |

**Hipstapaper 的架构最为独特**。它采用 **7+ 个 SPM Package 严格分层**，架构核心理念是"Avoiding view models is difficult but important"——不使用 ViewModel，而是通过自定义 Property Wrapper 封装 Core Data 查询（`CDObjectQuery`、`CDListQuery`），让 View 直接观察数据变更。**Identifier-only 导航模式**：Screen 之间只传递 `Website.Identifier`（对 Core Data ObjectID URL 的类型安全封装），每个 Screen 自行从 Core Data 获取数据，确保 iCloud 同步时数据始终最新。`@Navigation` 自定义 Property Wrapper 将所有导航状态编码进 `SceneStorage`，实现自动状态恢复。

**NetNewsWire 的分层最清晰**。自底向上：Submodules（RSCore、RSDatabase、RSParser、RSWeb、RSTree，彼此零依赖）→ In-app Frameworks（Articles、ArticlesDatabase、SyncDatabase、Account）→ Shared Code → Platform UI（iOS/Mac 完全分离）。Brent Simmons 的设计哲学是"Framework 让你确保不会引入不想要的依赖"。

---

## Phase 3：Folio 差距分析

### 特性对比矩阵

| 维度 | Folio 当前方案 | Omnivore | Wallabag | NetNewsWire | Hipstapaper | 差距评估 |
|------|-------------|---------|---------|------------|------------|---------|
| **内容提取** | 服务端 Node.js 自研 reader（HTML→Markdown） | 服务端 Puppeteer + Readability.js | 服务端 Graby + php-readability | 依赖 Feed 内容 | 无（保存原始 URL） | Folio 缺少客户端提取能力 |
| **Share Extension** | 有（120MB 限制） | 极简，仅发 URL | 极简，仅发 URL（v7.4 加 title/content） | 无 Share Extension | 有，WKWebView 提取 | Folio 可做到比所有竞品更强的离线保存 |
| **本地搜索** | SwiftData + SQLite FTS5 | Core Data + NSPredicate + 服务端搜索 | Core Data + NSPredicate | SQLite + FMDB | Core Data | **Folio 领先**——FTS5 是最强方案 |
| **阅读器渲染** | SwiftUI + apple/swift-markdown 原生渲染 | WKWebView + HTML/CSS + JS Bridge | WKWebView + CSS 主题 | WKWebView + HTML 模板 + CSS 分层 | WKWebView（原始页面） | Folio 的原生路线更现代但需完善主题系统 |
| **离线支持** | 本地优先（SwiftData） | 缓存 HTML 到 Core Data | 缓存 HTML 到 Core Data | SQLite 本地存储 | Core Data + iCloud | **Folio 领先**——真正的 local-first |
| **分类/标签** | AI 自动分类（DeepSeek 一次调用：分类+标签+摘要） | 手动标签 | 手动标签 | Feed 分组 | 手动标签 | **Folio 独有**——AI 自动化 |
| **TTS 语音** | 未知 | ElevenLabs AI 语音 | AVSpeechSynthesizer（基础） | 无 | 无 | 可考虑集成 |

### 可借鉴的具体实现

**1. 客户端内容提取管线（新能力）**

- **来源**: lake-of-fire/swift-readability + SwiftHTMLToMarkdown
- **路径**: `Sources/SwiftReadability/Readability.swift`
- **解决的问题**: Share Extension 内完成内容提取，实现断网保存即可读
- **实现方案**: `URL → URLSession fetch → Readability(html:, url:).parse() → SwiftHTMLToMarkdown → SwiftData 保存`
- **迁移成本**: **中等** — 需集成两个库、编写管线代码、处理边界情况
- **内存预算**: 峰值约 35-65MB，安全在 120MB 限内

**2. SPM 模块化架构（重构）**

- **来源**: Hipstapaper（`V3Store`、`V3Model`、`V3Interface`、`V3Browser` 等 7+ SPM Package）
- **路径**: 仓库根目录 Package.swift 定义所有包及依赖关系
- **解决的问题**: App Target / Share Extension / Widget 间代码共享；依赖边界强制执行
- **推荐分包**: FolioKit（核心数据模型）、FolioExtraction（内容提取）、FolioReader（渲染）、FolioSync（同步）、FolioAI（AI 分析接口）
- **迁移成本**: **大** — 需重构现有代码结构

**3. HTML 模板 + CSS 分层主题系统（增强阅读器）**

- **来源**: NetNewsWire（`Shared/Article Rendering/`）
- **路径**: `ArticleRenderer.swift`、`ArticleTheme.swift`、`ArticleThemesManager.swift`、`core.css`、`stylesheet.css`、`template.html`
- **解决的问题**: 用户可自定义阅读主题（字体、颜色、间距），支持第三方主题包
- **适用场景**: 如果 Folio 未来需要渲染复杂 HTML 内容（表格、嵌入视频等），可考虑 WKWebView + 此模板系统作为备选渲染管线
- **迁移成本**: **中等** — CSS/JS/模板资源 + WKWebView 封装

**4. Identifier-only 导航 + SceneStorage 状态恢复（架构模式）**

- **来源**: Hipstapaper（`V3Interface` 包）
- **路径**: Navigation Property Wrapper、各 Screen 的 View 定义
- **解决的问题**: 避免传递完整对象导致数据过期（尤其在 iCloud/远程同步场景下）；应用重启后恢复完整导航状态
- **迁移成本**: **小** — 设计模式可直接采纳到新代码中

**5. Account + AccountDelegate 同步抽象（网络层）**

- **来源**: NetNewsWire（`Account/` Framework）
- **路径**: `Account.swift`、`AccountDelegate.swift`、`AccountManager.swift`
- **解决的问题**: 解耦同步后端，未来可支持纯本地、自托管服务端、CloudKit 等多种模式
- **迁移成本**: **中等** — 需设计协议并实现至少两种 Delegate

**6. 双解析器回退 + Warmup 并行初始化（内容提取优化）**

- **来源**: reeeed（`Sources/Reeeed/`）
- **路径**: JS 资源目录含 Mercury + Readability 双引擎；`Reeeed.warmup()` 方法
- **解决的问题**: 单一解析器覆盖不足时自动回退；首次提取延迟优化
- **Folio 适配**: 客户端用 swift-readability 作主引擎，服务端用 Node.js reader 作回退；`warmup()` 模式可用于预加载 SwiftSoup 解析器
- **迁移成本**: **小**

**7. 离线保存队列（Share Extension 增强）**

- **来源**: Readeck iOS（`URLShare/` 目标）
- **解决的问题**: 服务端不可达时仍可保存书签，重连后自动同步
- **Folio 适配**: 与本地优先架构天然契合——先存本地 SwiftData，后台队列推送到服务端
- **迁移成本**: **小** — Folio 架构已支持

### Folio 的独有差异化优势

经过对比分析，Folio 具备三个竞品均未实现的能力：

**AI 自动分类与摘要**。Karakeep 虽然也有 AI 标签（OpenAI/Ollama），但其实现是简单的单功能调用。Folio 使用 DeepSeek 在一次调用中完成分类+标签+摘要的设计更高效，且成本更低。Omnivore 仅有 TTS；Wallabag v7.1 才开始试验 AI synthesis/tags 端点。

**本地优先 + 服务端混合架构**。Omnivore 和 Wallabag 是纯服务端依赖型；Luego 是纯本地型；Hipstapaper 是 Core Data + iCloud 型。Folio 的 SwiftData 本地存储 + Go 服务端 + asynq 任务队列的混合架构，既保证离线可用又支持 AI 分析等服务端增强能力，这种组合在开源项目中独一无二。

**客户端 SQLite FTS5 全文检索**。五个头部项目中无一在客户端实现了 FTS5。Omnivore 依赖服务端搜索，Wallabag 和 NetNewsWire 使用简单的文本匹配。FTS5 提供中文分词（通过自定义 tokenizer）、前缀匹配、BM25 排名等能力，是 Folio 在离线搜索体验上的护城河。

---

## Phase 4：结论与建议

### 技术建议：哪些模块应参考哪个项目

| Folio 模块 | 推荐参考 | 具体参考内容 |
|-----------|---------|------------|
| **Share Extension 内容提取** | lake-of-fire/swift-readability + reeeed | swift-readability 做主提取，reeeed 的 warmup/fallback 模式做架构参考 |
| **SPM 模块化** | Hipstapaper > Omnivore | Hipstapaper 的多包分层最彻底；Omnivore 的 OmnivoreKit 单包模式更简单可作过渡 |
| **阅读器主题系统** | MarkdownUI（当前）→ NetNewsWire（备选） | MarkdownUI 的 Theme API 做 Markdown 渲染主题；如需 HTML 渲染则参考 NNW 的 CSS 分层方案 |
| **导航架构** | Hipstapaper | Identifier-only 传递 + @Navigation SceneStorage 状态恢复 |
| **同步抽象层** | NetNewsWire | Account + AccountDelegate 协议设计，支持本地/自托管/CloudKit 多模式 |
| **离线队列** | Readeck iOS + Omnivore | Readeck 的离线保存队列 + Omnivore 的 clientRequestId 幂等性设计 |
| **数据模型** | Omnivore（字段设计）+ Luego（SwiftData 实践） | 参考 Omnivore 的 LinkedItem/Label/Highlight 关系设计，用 SwiftData @Model 实现 |

### 风险评估

**许可证兼容性**：Omnivore 和 Karakeep 使用 AGPL-3.0，直接复制代码会导致 Folio 必须开源。**建议**：仅参考其设计模式和架构思路，不直接使用 AGPL 代码。Wallabag、NetNewsWire、Hipstapaper、reeeed 均为 MIT，可安全借鉴。lake-of-fire/swift-readability 为 BSD-3-Clause，SwiftSoup 为 MIT，MarkdownUI 为 MIT——Folio 依赖链上无许可证风险。

**代码腐化风险**：Omnivore 虽有社区维护但核心团队已离开，长期维护不确定。lake-of-fire/swift-readability 仅 8 个 commit、2 stars，稳定性未经大规模验证——建议对其进行充分的 fixture 测试并准备 fork 维护。SwiftHTMLToMarkdown 同样年轻（49 stars），可考虑基于 SwiftSoup 自建 HTML→Markdown 转换器作为备案。MarkdownUI 已进入维护模式，后继者 Textual 尚不成熟——**建议当前使用 MarkdownUI v2.4.1，关注 Textual 发展，预留迁移路径**。

**Swift 6.2 要求**：lake-of-fire/swift-readability 要求 Swift 6.2，需确认 Folio 当前 Xcode/工具链版本兼容性。如不兼容，可考虑 fork 降级到 Swift 5.9 支持。

### 优先级排序：最值得投入研究的三个模块

**第一优先级：Share Extension 客户端提取管线**。这是 Folio 相对所有竞品最大的潜在差异化优势——在 120MB 内存限内实现"保存即可读"。推荐立即集成 swift-readability + SwiftHTMLToMarkdown，建立 `URL → fetch → Readability.parse() → HTML→Markdown → SwiftData save` 管线，并用 Omnivore 和 Wallabag 的服务端提取结果作为质量基准进行对比测试。

**第二优先级：SPM 模块化重构**。参考 Hipstapaper 的多包设计，将 Folio 拆分为 FolioKit（模型+服务）、FolioExtraction（提取）、FolioReader（渲染）、FolioSync（同步）四个核心包。这不仅解决 Share Extension 代码共享问题，更为后续 Widget、macOS 适配奠定基础。

**第三优先级：阅读器主题系统完善**。基于 MarkdownUI 的 Theme API 构建 Folio 专属阅读主题（明/暗/墨水屏模式），参考 NetNewsWire 的 CSS 分层理念设计可扩展的主题架构。同时预研 Textual 作为未来渲染引擎升级路径。

### 具体 Action Items

1. **本周**：Clone lake-of-fire/swift-readability，在 Folio 现有 Share Extension 中 PoC 集成，用 10 个目标网站（含微信公众号、Medium、知乎专栏等）测试提取质量，与服务端 Node.js reader 结果对比
2. **下周**：评估 swift-readability 的 Swift 6.2 依赖是否可降级；如不可行，考虑 fork 修改或使用 reeeed 的 JS-in-WKWebView 方案（仅在主 App 中使用，Extension 仍用纯 Swift 方案）
3. **第 2-3 周**：创建 FolioKit SPM Package，将数据模型和核心服务迁入；修改 Share Extension Target 依赖新 Package
4. **第 4 周**：基于 MarkdownUI 构建三套阅读主题（Light/Dark/Sepia），参考 NetNewsWire 的 `ArticleTheme` 设计实现主题切换 UI
5. **持续关注**：追踪 Textual 库进展；关注 Omnivore 社区 fork（如出现活跃重构可更新参考基线）；监控 Karakeep 的 AI tagging 实现演进以获取 prompt engineering 灵感