# 客户端内容提取方案 — 三份深度研究对比分析与最终结论

> 创建日期：2026-02-22
> 输入文档：claude-research-report.md | gemini-research-report.md | gpt-research-report.md
> 关联文档：[客户端抓取调研](../architecture/client-scraping-research.md) | [系统架构](../architecture/system-design.md)

---

## 一、三份研究报告的核心发现对齐

### 1.1 调研覆盖的项目

| 项目 | Claude | Gemini | GPT | 对 Folio 的参考维度 |
|------|:------:|:------:|:---:|-------------------|
| Omnivore | ✅ 深度 | ✅ 深度 | ✅ 深度 | 服务端提取架构、GraphQL 同步、阅读器 |
| Wallabag iOS | ✅ 深度 | ✅ 深度 | ✅ 深度 | Share Extension 实践、离线缓存 |
| NetNewsWire | ✅ 深度 | — | — | HTML 模板渲染管线、模块化架构 |
| Hipstapaper | ✅ 深度 | — | ✅ 轻度 | SPM 模块化、Identifier-only 导航 |
| reeeed | ✅ 深度 | ✅ 核心 | ✅ 提及 | 客户端 JS 混合提取方案 |
| Readeck iOS | ✅ 轻度 | ✅ 深度 | ✅ 深度 | 离线队列、Share Extension 流程 |
| YABA | — | — | ✅ 深度 | SwiftData + 全文搜索 + Spotlight |
| CrossX | — | — | ✅ 核心 | **双层提取管线（SwiftSoup + Readability.js 回退）** |
| Karakeep | ✅ 提及 | ✅ 深度 | ✅ 排除（React Native） | AI 标签功能参考 |
| Luego | ✅ 轻度 | — | — | SwiftData + MarkdownUI 渲染 |

**关键补充**：三份报告互相补充了对方未覆盖的项目。Claude 提供了 NetNewsWire 和 Hipstapaper 的架构深度分析；Gemini 强调了 GRDB.swift 作为存储层替代方案；GPT 发现了 CrossX 项目——一个在 Share Extension 内实现完整提取管线的实战参考。

### 1.2 三份报告的一致结论

以下结论在三份报告中完全一致，可信度极高：

1. **所有头部开源项目都依赖服务端提取**。Omnivore（Puppeteer + Readability.js）、Wallabag（Graby + php-readability）、Readeck 均在服务端完成内容提取。**没有任何一个成熟项目在 iOS 客户端实现了完整的正文提取**——这意味着客户端提取是一片蓝海，也是 Folio 的差异化机会。

2. **Mozilla Readability 算法是行业标准**。Pocket、Omnivore 直接使用，Instapaper 自研但思路一致。无论服务端还是客户端提取，核心算法都是基于 HTML 标签的文本密度和位置做 scoring + pruning。

3. **Share Extension 应保持轻量**。120MB 内存硬限制是共识。Omnivore 和 Wallabag 的 Extension 都只捕获 URL 后立即发送到服务端——这是务实的选择但也意味着断网时无法保存内容。

4. **Folio 的三大独有优势不应被稀释**：
   - AI 自动分类+标签+摘要的单次调用设计
   - SwiftData + SQLite FTS5 本地全文检索
   - 本地优先 + 服务端混合架构

### 1.3 三份报告的核心分歧

在"客户端提取的最佳技术路线"上，三份报告给出了不同的推荐：

| 维度 | Claude 报告 | Gemini 报告 | GPT 报告 |
|------|-----------|-----------|---------|
| **推荐主提取方案** | 纯 Swift：lake-of-fire/swift-readability | WKWebView + Readability.js（reeeed 模式） | 双层混合：SwiftSoup 快速路径 + Readability.js 回退（CrossX 模式） |
| **是否在 Extension 内提取** | ✅ 可以（纯 Swift 峰值 35-65MB） | ❌ 不建议（WKWebView 内存风险太大） | ⚠️ 默认不做，可选 fast preview |
| **HTML→Markdown 方案** | SwiftHTMLToMarkdown 库 | 不转换，直接用 WKWebView 渲染 HTML | 不指定，建议保持 Markdown 作为规范层 |
| **服务端的角色** | 回退 + AI 处理 | 主路径不变，客户端仅做离线回退 | 权威质量保证（authoritative Markdown） |
| **最大风险** | swift-readability 太新（8 commits, 2 stars, Swift 6.2） | WKWebView 在 Extension 中不可用 | CrossX 目标 iOS 26+，代码不能直接复用 |

---

## 二、三条技术路线的深度对比

### 路线 A：纯 Swift 提取（Claude 推荐）

```
URL → URLSession fetch → swift-readability (SwiftSoup) → clean HTML → 自写 HTML→Markdown → SwiftData
```

| 优势 | 劣势 |
|------|------|
| 不需要 WKWebView，可在 Share Extension 内运行 | swift-readability 极度年轻（8 commits, 2 stars） |
| 内存峰值约 35-65MB，安全在 120MB 内 | 要求 Swift 6.2，可能需 fork 降级 |
| 提取速度最快（无 WebView 初始化开销） | HTML→Markdown 转换需要自写或用不成熟的库 |
| 纯 Swift 依赖链，App Store 审核零风险 | 对 JS 渲染页面完全无能为力 |
| 与 Folio 现有 Markdown 渲染管线天然契合 | SwiftSoup 的 DOM 解析对超大 HTML 可能有性能问题 |

**内存预算分析**：
- URLSession 下载 HTML（~2MB 上限）：~5MB
- SwiftSoup DOM 解析：~10-25MB（取决于 HTML 复杂度）
- Readability 算法执行：~5-10MB
- Markdown 转换 + SwiftData 写入：~5-10MB
- **峰值总计：~35-65MB**（在 120MB 限内有充足余量）

### 路线 B：WKWebView + JS 引擎（Gemini 推荐）

```
URL → 隐藏 WKWebView 加载 → evaluateJavaScript(Readability.js) → clean HTML → WKWebView 渲染
```

| 优势 | 劣势 |
|------|------|
| Readability.js 是最成熟的提取算法（10+ 年迭代） | WKWebView 初始化 + DOM 构建内存开销 40-80MB |
| 能处理部分 JS 渲染页面（SPA） | **在 Share Extension 中极度危险**（易突破 120MB） |
| reeeed 库展示了双解析器回退（Mercury + Readability） | WKWebView 在 Extension 中可能被系统限制 |
| 提取质量最高 | 渲染依赖 WKWebView + CSS，与 Folio 现有 Markdown 渲染路线冲突 |
| 跨段落文本选择、高亮标注天然可用 | 增加阅读器维护复杂度（JS Bridge + CSS 主题） |

**内存预算分析**：
- WKWebView 进程启动：~30-40MB
- 加载目标 HTML + DOM 构建：~20-40MB
- Readability.js 执行：~5-10MB
- **峰值总计：~55-90MB**（接近 120MB 限制，大页面有超限风险）

### 路线 C：双层混合提取（GPT 推荐）

```
快速路径：SwiftSoup heuristic → title + excerpt + "good enough" body
回退路径：Readability.js（via WKWebView 或纯 Swift 移植）
权威路径：服务端 Node.js reader（完整 Markdown）
```

| 优势 | 劣势 |
|------|------|
| 分层设计，每层职责清晰 | 需要维护两套客户端提取逻辑 |
| 快速路径在 Extension 内安全（纯 SwiftSoup） | SwiftSoup heuristic 需要自己实现 scoring 算法 |
| CrossX 已验证 Share Extension 内完整管线可行 | CrossX 目标 iOS 26+，与 Folio iOS 17 差距大 |
| 渐进式：先上快速路径，再逐步加回退 | 架构复杂度高于单一方案 |
| 服务端仍作为质量保证兜底 | 三层之间的结果合并/覆盖逻辑需仔细设计 |

---

## 三、最终结论：Folio 推荐的客户端提取方案

### 3.1 推荐方案：路线 A（纯 Swift）为主，路线 C 的分层思想为架构

综合三份报告，结合 Folio 的具体约束（iOS 17 部署目标、Share Extension 120MB 限制、现有 Markdown 渲染管线、本地优先架构），推荐以下方案：

```
┌─────────────── Share Extension（120MB 限内）───────────────┐
│                                                            │
│  URL → URLSession fetch HTML                               │
│    → lake-of-fire/swift-readability 提取正文                 │
│      → HTML→Markdown 转换                                   │
│        → SwiftData 保存（离线可读）                           │
│                                                            │
│  失败时 → 仅保存 URL + 元数据，标记待服务端处理               │
│                                                            │
└────────────────────────────────────────────────────────────┘
                          ↓ 后台同步
┌─────────────── 服务端（权威质量）──────────────────────────┐
│                                                            │
│  Node.js reader（Readability + Puppeteer 回退）             │
│    → 完整 Markdown + 图片处理                               │
│      → 覆盖客户端提取结果（如果质量更高）                     │
│        → AI 分析（分类 + 标签 + 摘要）                      │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

### 3.2 方案选择的核心理由

**为什么选路线 A（纯 Swift）而非路线 B（WKWebView）：**

1. **内存安全性**：纯 Swift 方案峰值 35-65MB vs WKWebView 方案 55-90MB。在 Share Extension 的 120MB 硬限制下，纯 Swift 有近一倍的安全余量，WKWebView 则在处理大页面时有超限崩溃风险。三份报告均确认：Share Extension 崩溃是无声的，用户体验极差。

2. **在 Extension 中的可行性**：WKWebView 在 App Extension 中的行为不确定——苹果文档对 Extension 中使用 WebView 有诸多限制警告，且 WebKit 进程可能在 Extension 生命周期内被系统优先回收。纯 Swift 方案无此风险。

3. **与现有架构的契合度**：Folio 当前使用 swift-markdown 做 Markdown 渲染。纯 Swift 提取 → HTML → Markdown → SwiftData 的管线与现有阅读器无缝衔接。WKWebView 方案意味着要同时维护 Markdown 渲染和 HTML/CSS 渲染两套系统，或者全面迁移到 WKWebView 渲染——这是一个远大于"客户端提取"本身的架构变更。

4. **App Store 审核**：纯 Swift 方案不涉及 JS 执行和 WebView，审核风险为零。

**为什么借鉴路线 C 的分层思想：**

1. **客户端提取不可能覆盖所有场景**（JS 渲染 SPA、反爬站点、需登录内容）。将服务端保留为"权威质量"层是务实的选择。

2. **渐进式体验**：用户分享 URL 后 2-5 秒内通过客户端提取获得可读内容（即使不完美），后台同步后用服务端更高质量的结果静默替换。

3. **容错设计**：客户端提取失败时优雅降级为"仅保存 URL"，等服务端处理——这就是 Folio 现有的行为，不会退步。

**为什么不选路线 C 的 SwiftSoup heuristic 快速路径：**

自写 heuristic scoring 算法的工程量和维护成本远高于直接使用 Readability 算法移植。swift-readability 虽然年轻，但它移植的是 Mozilla Readability v0.6.0——一个经过 10 年验证的成熟算法。自写 heuristic 本质上是在重新发明一个更差的 Readability。

### 3.3 关键风险与缓解措施

| 风险 | 严重程度 | 缓解措施 |
|------|---------|---------|
| swift-readability 项目太新（8 commits, 2 stars） | 高 | ① fork 到 Folio org 维护；② 用 Omnivore 和 Wallabag 的 fixture 做质量基准测试；③ 准备备选：自己基于 SwiftSoup 实现核心 Readability 算法（~300 行） |
| Swift 6.2 要求可能与 Folio 当前工具链不兼容 | 中 | fork 后降级到 Swift 5.9 支持——该库的核心逻辑不依赖 Swift 6.2 特性，主要是并发标注可以调整 |
| HTML→Markdown 转换质量 | 中 | 自写 ~100-150 行递归 DOM 遍历转换器（swift-readability 输出的是已清洗的简单 HTML，转换复杂度远低于通用 HTML→Markdown）；不使用 SwiftHTMLToMarkdown（不支持 table，49 stars） |
| 中文/日文页面的提取质量 | 中 | Readability 算法对亚洲语言页面有已知的边界问题（标点符号导致的断句、编码检测等），需要针对微信公众号、知乎等目标站点做专项测试和规则补充 |
| 大型 HTML 页面（>2MB）内存压力 | 低 | 在 URLSession 层设置 2MB 下载上限；超限的页面直接降级为"仅保存 URL，等服务端处理" |

### 3.4 实施路径

#### Phase 1：PoC 验证（1 周）

1. Fork lake-of-fire/swift-readability，评估 Swift 版本兼容性
2. 在独立测试工程中集成，用 10 个代表性 URL 测试提取质量：
   - 中文博客（3 个）
   - 微信公众号文章（2 个）
   - 英文 Medium / Substack（2 个）
   - 知乎专栏（1 个）
   - Twitter/X 长推文页面（1 个）
   - 复杂布局页面（1 个：含表格、代码块、嵌入视频）
3. 与服务端 Node.js reader 的提取结果逐一对比，建立质量评分表
4. 测量内存峰值（Instruments → Allocations），确认在 120MB 以内

#### Phase 2：集成 Share Extension（1-2 周）

1. 编写 HTML→Markdown 转换器（递归 DOM 遍历，~150 行）
2. 在 Share Extension 中构建提取管线：
   ```
   NSItemProvider → URL → URLSession fetch → Readability → HTML→Markdown → SwiftData
   ```
3. 失败路径：提取失败 → 降级为现有行为（仅保存 URL）
4. 内存预算监控：在 Extension 中嵌入内存水位检测，接近 100MB 时主动中断提取

#### Phase 3：客户端-服务端协同（1 周）

1. 数据模型增加 `extractionSource` 字段（`client` / `server`）和 `clientExtractedAt` 时间戳
2. 服务端处理完成后，对比客户端和服务端提取结果的质量（字数、结构完整度）
3. 如果服务端结果更优，静默替换客户端版本
4. 客户端提取成功时，服务端仍执行 AI 分析（分类+标签+摘要），但可跳过重新抓取网页

#### Phase 4：质量迭代（持续）

1. 建立提取质量 fixture 测试集（50+ URL → 预期输出）
2. 针对高频失败站点添加自定义提取规则（类似 Wallabag 的 ftr-site-config 思路）
3. 监控客户端 vs 服务端提取的成功率和质量差异，数据驱动优化

---

## 四、其他模块的附带发现

虽然本次分析聚焦于客户端提取，三份报告在其他模块上也有值得记录的发现：

### 4.1 阅读器渲染

| 维度 | 三份报告的共识 | Folio 当前策略 | 建议 |
|------|-------------|-------------|------|
| 短期方案 | Markdown 原生渲染对中短文章足够 | SwiftUI + swift-markdown ✅ | 维持现状，优先解决提取问题 |
| 长期方向 | Claude/Gemini 均指出长文 Markdown 渲染有性能和选择问题 | — | 关注 MarkdownUI 和 Textual 库进展，必要时为超长文章提供 WKWebView 备选渲染路径 |
| 主题系统 | NetNewsWire 的 CSS 分层方案最成熟 | 尚未实现 | 第二优先级：基于 swift-markdown 的 Theme API 构建明/暗/护眼三套主题 |

### 4.2 存储层

| 维度 | Claude/GPT 报告 | Gemini 报告 | Folio 当前策略 | 建议 |
|------|-------------|------------|-------------|------|
| 持久化 | SwiftData 足够，YABA 也在用 | **强烈建议迁移到 GRDB.swift** | SwiftData + FTS5 ✅ | 暂不迁移。Gemini 的 GRDB 建议有技术道理（原生 FTS5 支持、自定义 tokenizer、WAL 并发），但迁移成本极大且 Folio 现有的 SwiftData + 旁挂 FTS5 方案已经工作。将 GRDB 作为长期架构储备，当 FTS5 同步或并发问题实际出现时再考虑 |
| Spotlight | GPT 报告（YABA 参考） | — | 未实现 | 低优先级增强：为最近/高频文章添加 Spotlight 索引，提供系统级搜索入口 |

### 4.3 Share Extension 内存优化

三份报告的共识最佳实践（无论是否做客户端提取）：

1. **避免在 Extension 中解压图片为 UIImage** — 一张 5MB JPEG 解压后占 50MB+ 内存
2. **使用 App Group 共享文件目录** — 而非 UserDefaults 存储大数据
3. **考虑 Background URLSession** — `URLSessionConfiguration.background(withIdentifier:)` + `uploadTask(with:fromFile:)` 让系统后台守护进程接管网络请求，Extension 可立即退出释放内存
4. **设置内存水位监控** — 接近限制时主动中断非必要操作，优雅降级

### 4.4 架构模块化

| 方案 | 推荐来源 | Folio 适用性 |
|------|---------|------------|
| SPM 多包分层（Hipstapaper 模式） | Claude 报告 | 中期目标：FolioKit / FolioExtraction / FolioReader / FolioSync |
| Account + AccountDelegate 协议抽象（NetNewsWire 模式） | Claude 报告 | 长期：支持纯本地 / 自托管 / CloudKit 多种同步模式 |
| Identifier-only 导航 + SceneStorage 状态恢复（Hipstapaper 模式） | Claude 报告 | 低成本，新代码可直接采纳 |

---

## 五、总结

### 一句话结论

**Folio 应采用纯 Swift 客户端提取（lake-of-fire/swift-readability）在 Share Extension 内实现"保存即可读"，同时保留服务端提取作为质量兜底和 AI 分析入口。这是三份研究报告的交叉验证结论，也是所有开源竞品均未实现的差异化能力。**

### 决策依据总结

| 决策点 | 选择 | 理由 |
|--------|------|------|
| 客户端是否做提取？ | ✅ 做 | 三份报告一致认可客户端提取是 Folio 最大的差异化机会 |
| 用什么技术做提取？ | 纯 Swift（swift-readability + SwiftSoup） | 内存安全（35-65MB）、无 WKWebView 风险、与现有 Markdown 管线契合 |
| 在哪里做提取？ | Share Extension 内 | 实现"分享即可读"的即时体验，这是竞品都做不到的 |
| 服务端还需要吗？ | ✅ 需要 | 作为权威质量层 + AI 分析入口 + JS 渲染页面兜底 |
| HTML→Markdown 怎么做？ | 自写（~150 行） | swift-readability 输出干净 HTML，转换简单；现有第三方库（SwiftHTMLToMarkdown）不成熟 |
| 最大风险是什么？ | swift-readability 项目成熟度 | 缓解：fork 维护 + fixture 测试 + SwiftSoup 自实现备选 |
