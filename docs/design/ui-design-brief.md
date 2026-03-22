# Folio UI 设计任务书

> 本文件是给 UI 设计会话的完整上下文。请按顺序阅读。

---

## 一、你的角色

你是一位世界级 iOS UI/UX 设计师（曾在 Apple Human Interface 团队工作），精通 iOS 设计规范和高保真原型制作。你的风格是乔布斯式极致简约 + 情感化微交互。

## 二、输出方式

**使用 HTML/CSS/JS 生成可交互的高保真原型**，模拟 iPhone 屏幕，在浏览器中直接预览。

### 原型规范

- 每个原型输出为**单个自包含 HTML 文件**，保存到 `docs/design/prototypes/`
- iPhone 15 Pro 尺寸（393×852pt），居中显示，带圆角设备边框和 Dynamic Island
- 字体：`-apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display"`
- 衬线体：`"Georgia", "Noto Serif SC", serif`（模拟 App 中的 New York / Noto Serif SC）
- 支持 Light + Dark 模式（CSS `prefers-color-scheme`，且提供手动切换按钮）
- 所有交互状态用 JS 实现：点击、滑动、展开/折叠、状态切换
- 动效参数严格匹配设计系统（见下方 Motion tokens）
- 使用模拟数据（中文文章标题、真实感摘要、合理的标签）
- 每个原型文件顶部用 HTML 注释写明：设计思路、交互说明、状态列表

### 查看方式

完成后告诉我文件路径，我通过 `open <path>` 在浏览器预览。

---

## 三、产品背景

### 产品定位

**Folio 记得。然后帮你也记得。**

Folio 是一款本地优先的个人知识记忆 iOS App。核心变化：从"帮你存+找"升级为"帮你存+记+用"。

### 三个动词

- **存** — 链接/截图/语音/高亮/手动输入，零摩擦流入。AI 自动阅读、理解、提炼洞察摘要
- **记** — 间隔重复 + 主动回忆（Daily Echo）：Folio 在你快忘时提问，你主动回忆，10 秒一次
- **用** — RAG 问答 + 语义搜索 + 知识简报：自然语言提问，综合收藏回答，溯源到原文

### 必读文件（按顺序）

1. `docs/design/product-vision.md` — 产品愿景全文
2. `docs/superpowers/specs/2026-03-22-product-vision-redesign.md` — 设计决策 Spec（订阅模型、冷启动策略等）
3. `docs/interaction/core-flows.md` — 当前交互流程文档

### App 架构约束

- 单 NavigationStack，没有 TabView
- **只有 3 个页面**：Home、Reader、Settings。**新功能不加新页面，全部融入现有界面**
- 部署目标 iOS 17.0
- 设计语言：**安静、有质感、留白充分**。不花哨，不打扰。像 Apple Notes 而不是 Notion

---

## 四、设计系统（当前实现）

设计新界面时必须复用这些 token。如需新增 token，在原型注释中标明。

### Typography

**界面字体（SF Pro，Dynamic Type）**

| Token | 字体 | 字号 | 字重 | 用途 |
|-------|------|------|------|------|
| navTitle | SF Pro Display | ~20pt | Semibold | 导航栏标题 |
| pageTitle | SF Pro Display | ~28pt | Bold | 页面大标题 |
| listTitle | SF Pro Text | ~17pt | Semibold | 列表项标题 |
| body | SF Pro Text | ~15pt | Regular | 正文/描述 |
| caption | SF Pro Text | ~13pt | Regular | 辅助信息 |

**编辑/卡片字体（衬线体）**

| Token | 字体 | 字号 | 字重 | 用途 |
|-------|------|------|------|------|
| cardTitle | New York (serif) | ~17pt | Regular | 文章卡片标题（已读） |
| cardTitleUnread | New York (serif) | ~17pt | Semibold | 文章卡片标题（未读） |
| cardSummary | SF Pro Text | ~15pt | Regular | 卡片摘要 |
| cardMeta | SF Pro Text | ~13pt | Regular | 卡片元信息 |
| emptyHeadline | New York (serif) | ~24pt | Regular | 空状态标题 |
| tag | SF Pro Text | ~13pt | Medium | 标签文字 |

**阅读器字体**

| Token | 字体 | 字号 | 行距 | 用途 |
|-------|------|------|------|------|
| articleTitle | Noto Serif SC | 28pt | — | 文章标题 |
| articleBody | Noto Serif SC | 17pt | 1.7 | 正文 |
| articleCode | SF Mono | 14pt | — | 代码块 |

### Spacing

| Token | 值 | 用途 |
|-------|-----|------|
| xxs | 4pt | 图标间距、小间隙 |
| xs | 8pt | 卡片内边距、元信息间距 |
| sm | 12pt | 列表项内边距 |
| md | 16pt | 标准内间距、屏幕水平边距 |
| lg | 24pt | 区域间距 |
| xl | 32pt | 大区域间距 |
| screenPadding | 16pt | 屏幕左右边距 |

### Corner Radius

| Token | 值 | 用途 |
|-------|-----|------|
| small | 4pt | 标签、小徽章 |
| medium | 8pt | 卡片、缩略图、代码块 |
| large | 12pt | 弹窗、底部抽屉 |

### Motion / Animation

| Token | 参数 | 用途 |
|-------|------|------|
| settle | spring 0.4s, bounce 0.05 | 元素落位（有重量感） |
| quick | spring 0.25s, bounce 0.0 | 按钮/状态反馈（即时） |
| ink | easeOut 0.15s | 内容出现（快速印刷感） |
| exit | easeIn 0.2s | 元素离开（安静消失） |
| slow | linear 2.0s | 进度条、处理状态 |

### Colors（语义色，在原型中用 CSS 变量）

```css
:root {
  /* Light mode */
  --background: #FFFFFF;
  --card-background: #F8F8F8;
  --text-primary: #1C1C1E;
  --text-secondary: #8E8E93;
  --text-tertiary: #C7C7CC;
  --accent: #007AFF;
  --tag-background: #F2F2F7;
  --tag-text: #636366;
  --separator: #E5E5EA;
  --code-background: #1C1C1E;
  --success: #34C759;
  --error: #FF3B30;
  --warning: #FF9500;
}

@media (prefers-color-scheme: dark) {
  :root {
    --background: #000000;
    --card-background: #1C1C1E;
    --text-primary: #F2F2F7;
    --text-secondary: #8E8E93;
    --text-tertiary: #48484A;
    --accent: #0A84FF;
    --tag-background: #2C2C2E;
    --tag-text: #AEAEB2;
    --separator: #38383A;
    --code-background: #2C2C2E;
    --success: #30D158;
    --error: #FF453A;
    --warning: #FF9F0A;
  }
}
```

---

## 五、当前 App 完整状态

### 导航结构

```
FolioApp (root)
├── OnboardingView (首次启动)
│   ├── 4 页 TabView → Apple/Email 登录 → PermissionView → 完成
│   └── "不登录使用" → PermissionView → 完成
│
└── NavigationStack (已登录)
    ├── HomeView (root)
    │   ├── .searchable → HomeSearchResultsView
    │   ├── 文章行 tap → ReaderView
    │   └── 设置按钮 → SettingsView
    │
    ├── ReaderView (文章详情)
    │   ├── 更多菜单 → 收藏/归档/复制/偏好/删除
    │   ├── 图片 tap → ImageViewerOverlay (fullScreenCover)
    │   └── 底部工具栏 → 原文/分享
    │
    └── SettingsView
        └── 登录/登出/订阅/版本
```

### 每个页面的当前状态

#### HomeView — 6 种状态

1. **空状态**：无文章 → EmptyStateView（"你的收藏是空的"+ 粘贴按钮）
2. **正常列表**：文章时间线，每篇 ArticleCardView
3. **搜索中**：.searchable 激活 → HomeSearchResultsView
4. **离线**：顶部 banner（wifi.slash + "你当前离线..."）
5. **同步错误**：顶部 banner（错误消息 + 重试/关闭）
6. **加载中**：同步时顶部 SyncProgressBar

#### ArticleCardView — 6 种状态

1. **Loading**：骨架屏（ShimmerView）
2. **未读**：衬线粗体标题 + 主色
3. **已读**：衬线常规标题 + 次色
4. **失败**：三级文字色 + 感叹号图标
5. **处理中**：底部 ProcessingProgressBar（accent 色动画）
6. **客户端就绪**：底部 ProcessingProgressBar（success 色淡化）

#### ReaderView — 7 种状态

1. **加载中**：居中 ProgressView
2. **内容已加载**：Markdown 渲染 + 底部相关收藏
3. **内容加载中**：ProgressView + "正在加载内容..."
4. **加载错误**：错误图标 + 消息 + 重试 + 查看原文
5. **AI 处理中**：sparkles 图标 + "AI 正在分析..."
6. **处理失败**：三角感叹 + 失败消息
7. **通用不可用**：doc.magnifyingglass + "内容暂不可用"

#### 交互行为清单

**Home 页交互**：
- 下拉刷新 → 增量同步
- 文章行 tap → 导航到 Reader
- 文章行左滑 → 收藏切换（全滑）
- 文章行右滑 → 删除（需确认）
- 文章行长按 → 上下文菜单（重试/收藏/归档/分享/复制链接/删除）
- 滚动到底 → 自动加载更多
- 搜索输入 → 200ms 防抖搜索
- 搜索检测到 URL → 保存链接 / 查看已存文章
- 搜索文本输入 → "保存为笔记"选项 + 搜索结果

**Reader 页交互**：
- 更多菜单：收藏/复制 Markdown/阅读偏好/归档/查看原文/删除
- 图片点击 → 全屏查看器（捏合缩放 1-5x，双击 1x/2.5x，下拉关闭）
- 滚动 → 更新阅读进度（1% 阈值持久化）
- AI 摘要区域 → 点击展开/折叠
- 底部工具栏：原文按钮 + 阅读进度 % + 分享按钮
- 入场动画：ink 动效序列（标题 → 元信息 → 内容）

---

## 六、设计任务（完整清单）

你需要为 Folio v3.0 设计**每一个页面的每一个状态的每一个交互**。按以下顺序逐个完成。

### 原型文件规划

| # | 文件名 | 内容 | 状态数 |
|---|--------|------|--------|
| 01 | `01-home-feed.html` | Home 完整体验：文章列表 + Echo 卡片穿插 + 洞察摘要升级 + 空状态 + 离线状态 | ~10 |
| 02 | `02-echo-interaction.html` | Echo 卡片完整交互流程：提问 → 思考 → 揭晓 → 记得/忘了 + 三种卡片类型 | ~6 |
| 03 | `03-search-and-qa.html` | 搜索 → 问答无缝融合：短查询结果 + 长问题 RAG 回答 + 来源溯源 + 无结果状态 | ~8 |
| 04 | `04-reader-full.html` | Reader 完整体验：洞察摘要展开 + 高亮标注交互 + 相关收藏 + 所有状态 | ~10 |
| 05 | `05-knowledge-map.html` | 知识地图：月度阅读版图 + 吸收统计 + 从 Home 进入的动画 | ~3 |
| 06 | `06-onboarding.html` | 引导流程：4 页 + 登录 + 权限（更新为"Folio 记得"定位） | ~6 |
| 07 | `07-settings.html` | 设置页：两层订阅展示 + 用户信息 + Pro 升级引导 | ~4 |
| 08 | `08-cold-start.html` | 冷启动旅程：第 1/3/5/10 篇里程碑体验 + Pro 试用期过渡 | ~5 |
| 09 | `09-widget.html` | 锁屏 Widget 设计：洞察展示 + Echo 入口 | ~2 |
| 10 | `10-transitions.html` | 页面转场动画集合：Home→Reader、搜索展开、Echo 翻转、Sheet 弹出 | ~8 |

### 每个原型必须包含

对于每个页面/组件，你必须设计并实现以下全部内容：

1. **所有状态**（正常、空、加载、错误、离线、首次使用）
2. **所有交互**（tap、swipe、long press、scroll、pull-to-refresh）
3. **所有动画**（入场、退场、状态切换，使用设计系统 Motion token）
4. **所有尺寸**（标题截断、长摘要、标签溢出、极端内容）
5. **Light + Dark 模式**（提供切换按钮）
6. **可访问性考虑**（对比度、触摸目标 44pt、动态字号）

### 控制面板

每个原型文件底部（设备框架外）放一个**控制面板**：

```
[Light ◉ Dark] [状态 1] [状态 2] [状态 3] ... [重置]
```

让我可以一键切换不同状态查看效果。

---

## 七、各原型详细设计要求

### 01 — Home Feed (`01-home-feed.html`)

**需要展示的所有状态**（控制面板切换）：

1. **空状态**（新用户）：EmptyStateView，更新文案为"Folio 记得"调性
2. **首篇收藏后**：1 篇文章 + 洞察摘要 + 冷启动引导提示
3. **正常 Feed**：8-10 篇文章混合 + 2 张 Echo 卡片穿插
4. **含处理中文章**：1 篇 shimmer + 1 篇 processing + 正常列表
5. **离线状态**：顶部离线 banner + 正常列表
6. **同步错误**：顶部错误 banner（带重试/关闭按钮）

**文章卡片升级**（洞察级摘要）：
- 现有摘要区域改为洞察风格：
  - **一句核心洞察**（加粗，稍大字号，与正常摘要视觉上有区分）
  - 下方可选：1-2 个支撑要点（caption 字号）
- 未读 vs 已读的视觉差异保持（粗体 vs 常规）

**Echo 卡片在 Feed 中的样式**：
- 视觉上与文章卡片**有区分但不突兀**——建议：左侧 accent 色竖线 + 轻微不同的背景色
- 未回答状态：问题文字 + "揭晓答案"按钮
- 已回答状态：答案 + 🟢记得 / 🔴忘了 标记 + 下次回顾时间

**交互**：
- 文章卡片 tap → 跳转效果（模拟 NavigationLink push 动画）
- 下拉刷新动画
- 滚动到底 → "加载更多"指示器
- Echo 卡片点击 → 不跳转，原地展开（详细交互在 02 中设计）

### 02 — Echo 交互 (`02-echo-interaction.html`)

**完整交互流程**（分步可点击）：

```
Step 1: 初始状态
  ┌────────────────────────┐
  │ ✦ Echo                  │
  │                         │
  │ 你 3 周前存了一篇关于    │
  │ AI 项目失败率的文章。    │
  │                         │
  │ 还记得最反直觉的         │
  │ 结论是什么吗？           │
  │                         │
  │     [ 揭晓答案 ]        │
  └────────────────────────┘

Step 2: 揭晓动画（0.4s settle）
  卡片高度平滑扩展，答案从下方淡入

Step 3: 答案 + 反馈按钮
  ┌────────────────────────┐
  │ ✦ Echo                  │
  │                         │
  │ "失败的根因不是技术，    │
  │  而是问题定义错误。"     │
  │                         │
  │ — 来自《为什么 90% 的    │
  │   AI 项目失败》          │
  │                         │
  │  🟢 记得    🔴 忘了      │
  └────────────────────────┘

Step 4: 反馈后状态
  点击"记得"→ 卡片收缩为一行确认："✓ 已记录，下次 2 周后回顾"
  点击"忘了"→ "📌 已标记，3 天后再来"
```

**三种卡片类型**（标签切换）：
1. **核心洞察回忆**："这篇文章最反直觉的结论是什么？"
2. **高亮回顾**："你标注了这句话——它出现在什么上下文中？"
3. **关联发现**："这两篇文章关于 XX 的观点有什么不同？"

### 03 — 搜索与问答 (`03-search-and-qa.html`)

**状态切换**：

1. **搜索栏未激活**：Home 状态（搜索栏收起在导航栏下）
2. **搜索栏激活**：搜索栏展开 + 键盘弹起（模拟）+ 搜索历史/建议
3. **短查询结果**：输入"RAG" → 关键词搜索结果列表（高亮匹配词）
4. **长问题 → RAG 回答**：输入"我存过的文章里关于用户留存有哪些方法？"→ AI 综合回答
5. **RAG 回答详情**：回答文本 + 来源卡片（点击可展开原文段落）
6. **URL 检测**：粘贴板含 URL → "保存此链接"选项
7. **文本输入 → 保存为笔记**：输入非 URL 文本 → "保存为笔记"选项
8. **无结果**：搜索无结果 → "你的收藏中暂无相关内容"

**RAG 回答的 UI 设计**（重点）：
- 回答区域和搜索结果在**同一个界面**，不跳转
- 回答文本：正文样式，段落间有来源标注
- 来源标注：`— 来自《文章标题》，3月5日收藏` + 点击可展开原文段落
- 底部："基于你的 X 篇相关收藏" + 查看全部来源
- 打字机效果（可选）：回答文字逐字出现

### 04 — Reader 完整体验 (`04-reader-full.html`)

**需要展示的所有状态**（控制面板切换）：

1. **加载中**：骨架屏 / ProgressView
2. **正常阅读**：标题 + 元信息 + 洞察摘要（可展开）+ Markdown 内容 + 相关收藏
3. **AI 处理中**：sparkles + "AI 正在分析..."
4. **处理失败**：失败消息 + 查看原文
5. **内容不可用**：通用不可用状态

**洞察摘要区域（升级设计）**：
- 收起状态：sparkles 图标 + 一句核心洞察（加粗）+ 展开箭头
- 展开状态：核心洞察 + 2-3 个 key_points + 关联提示（"你 2 周前存的 XX 持相同观点"）

**高亮标注交互**（新功能）：
- 长按文字 → 选中状态（iOS 原生选择 handles）
- 选中后弹出菜单：[高亮] [复制]
- 高亮效果：accent 色半透明底色
- 已高亮文字再次点击 → [移除高亮] [复制]

**相关收藏**（底部）：
- 标题："你的收藏中有 3 篇相关文章"
- 水平滚动卡片（3 篇）：缩略标题 + 来源 + 卡片背景
- 点击 → 模拟导航到该文章

**底部工具栏**：
- 左：原文按钮（safari 图标）
- 中：阅读进度百分比
- 右：分享按钮

**阅读进度条**：
- 导航栏下方细线，宽度 = 进度 %

### 05 — 知识地图 (`05-knowledge-map.html`)

**从 Home 页进入方式**：
- Home 底部"知识地图"入口（或 Settings 子页面，你来决定最佳位置）
- 过渡动画：sheet 或 push

**内容**：
1. **月度概览**：本月存了 X 篇 / 吸收了 Y 个洞察 / 最长连续回忆 Z 天
2. **主题分布**：水平条形图（按收藏数排序）
3. **趋势洞察**：一句话 AI 分析——"你的关注重心正在从 AI 技术转向 AI 产品化"
4. **吸收统计**：本月 Echo 回忆率 XX%

### 06 — Onboarding (`06-onboarding.html`)

更新文案为 v3.0 定位。4 页 + 登录 + 权限。

1. **Page 1**：Folio · 页集 — "Folio 记得。然后帮你也记得。"
2. **Page 2**：存 — "从任何 App 一键保存"
3. **Page 3**：记 — "间隔重复，帮你真正记住"（Echo 动画预览）
4. **Page 4**：用 — "问它任何你读过的事"（RAG 演示预览）
5. **登录**：Apple / Email / 不登录
6. **通知权限**：（不在这里请求，仅展示"开始使用"）

### 07 — Settings (`07-settings.html`)

1. **已登录状态**：头像 + 昵称/邮箱 + 订阅状态
2. **未登录状态**：登录引导
3. **Pro 订阅展示**：Free vs Pro 对比表 + 升级按钮
4. **Pro 已订阅**：显示到期日期 + 管理订阅

### 08 — 冷启动旅程 (`08-cold-start.html`)

模拟新用户从 0 到 10 篇的完整体验：

1. **第 1 篇**：保存成功 → 洞察摘要出现 → "Folio 已读过这篇"提示
2. **第 3 篇**：首次文章关联提示 → "你存的这篇和之前那篇有关联"
3. **第 5 篇**：首次 Echo 触发 → 迷你 RAG 演示 → "试试问我一个问题"
4. **第 10 篇**：Pro 试用期总结 → "你已吸收 X 个洞察" → 升级引导
5. **第 11 篇**：Free 版限制生效 → 平滑过渡提示

### 09 — Widget (`09-widget.html`)

- **锁屏 Widget（小尺寸）**：一行洞察文字 + Folio 图标
- **锁屏 Widget（中尺寸）**：洞察文字 + 来源文章标题
- **主屏 Widget（小）**：今日 Echo 问题预览
- **主屏 Widget（中）**：Echo 问题 + 本月吸收统计

### 10 — 转场动画 (`10-transitions.html`)

用动画演示以下转场：

1. **Home → Reader**：push 动画（标题可共享元素过渡）
2. **搜索栏展开**：从导航栏下方滑出
3. **Echo 卡片揭晓**：高度扩展 + 答案淡入（settle 动效）
4. **Echo 反馈后收缩**：卡片收缩为一行（exit 动效）
5. **AI 摘要展开/折叠**：高度动画 + chevron 旋转
6. **RAG 回答出现**：打字机效果 + 来源卡片依次淡入
7. **图片全屏**：从原位扩展到全屏
8. **Sheet 弹出**：标准 iOS sheet 动画

---

## 八、工作流程

1. **从 01-home-feed.html 开始**——这是用户看到的第一个界面，也是体验最复杂的页面
2. 每完成一个原型，告诉我文件路径，我预览后给反馈
3. 根据反馈迭代，直到我确认 OK
4. 然后进入下一个原型
5. 所有原型完成后，我们做一次整体一致性检查

**重要**：如果你觉得某个设计决策需要讨论（比如 Echo 卡片应该用什么颜色区分），主动提出来，不要自己猜。宁可问我一次，不要做一个我不喜欢的设计然后返工。
