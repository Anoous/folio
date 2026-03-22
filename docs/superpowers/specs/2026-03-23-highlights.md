# Highlights — Design Spec

> 日期：2026-03-23
> 状态：Approved
> 范围：P1.2 — 高亮标注系统（WKWebView 方案）

---

## 概述

用户在 Reader 中选中文字 → 高亮标注 → 存储到后端 → 自动生成 Echo "高亮回顾" 卡片。同时将 Reader 渲染层从 SwiftUI MarkdownRenderer 重构为 WKWebView，实现精确文本选择、高亮渲染、阅读进度追踪。

## 设计决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 渲染方案 | WKWebView | 精确偏移量、完整 Markdown 支持、行业标准、原型 CSS 可复用 |
| 偏移量计算 | JS Selection API → 字符偏移 | 精确、无歧义 |
| 创建流程 | 两步：选中 → 弹出"高亮/复制"菜单 → 点击创建 | 比自动高亮更不容易误操作 |
| 同步策略 | 本地先存 + 联网后同步（乐观更新） | 本地优先 App，离线也能高亮 |
| 离线支持 | 本地 SwiftData 立即保存，联网后 POST 到后端 | 复用 OfflineQueueManager 模式 |
| 内容变化保护 | 有高亮的文章不重新抓取 | 避免偏移量失效 |
| 同步去重 | DB UNIQUE (article_id, user_id, start_offset, end_offset) | 防止多设备重复高亮 |
| 阅读偏好 | 动态注入 CSS 变量（字号/行距/字体/主题） | 保留现有用户自定义能力 |
| Echo 集成 | 创建高亮时自动生成 | 高亮 = 用户标记"重要"，值得回忆 |

## 架构

```
Markdown → HTML + CSS → WKWebView
                            ↓
              JS Selection API → 精确偏移量
                            ↓
              WKScriptMessageHandler ← JS postMessage
                            ↓
              本地保存 + POST /highlights → 后端
                            ↓
              echo:generate (highlight 类型) → Echo 卡片
```

## Reader 渲染层重构

### 1. Markdown → HTML 转换器

**文件：** `ios/Folio/Presentation/Reader/MarkdownToHTML.swift`

将文章 Markdown 字符串转为完整 HTML document string：
- `<html>` + `<head>` (CSS) + `<body>` (内容)
- CSS 复用原型 04 样式：
  - 正文：LXGW WenKai TC 17px, line-height 1.75
  - H2：LXGW WenKai TC 20px bold, margin 32px 0 14px
  - 引用：border-left 2px text-4, italic, padding-left 16px
  - 代码：SF Mono 14px, subtle-bg background, 4px radius
  - 链接：accent color
  - 图片：max-width 100%, 8px radius
- 注入高亮列表作为 JS 数据（`window.existingHighlights = [...]`）
- **动态 CSS 变量**（从 `@AppStorage` 读取阅读偏好注入）：
  - `--font-size`: 用户设置的字号（默认 17px）
  - `--line-height`: 用户设置的行距（默认 1.75）
  - `--font-family`: 用户选择的字体（LXGW WenKai TC / Noto Serif SC / Georgia / system）
  - `--theme`: light / dark / sepia（跟随用户 ReadingTheme 设置）
- 背景色：light=#FAF9F6, dark=#000, sepia=#F5F0E8（通过 theme 变量控制）
- 字体偏好变化时通过 JS bridge 动态更新（`evaluateJavaScript("setPreferences(...)")`）

### 2. ArticleWebView（UIViewRepresentable）

**文件：** `ios/Folio/Presentation/Reader/ArticleWebView.swift`

包装 WKWebView 的 SwiftUI 组件：

**输入：**
- `htmlContent: String` — 完整 HTML
- `highlights: [Highlight]` — 已有高亮列表
- `onHighlightCreate: (String, Int, Int) -> Void` — (text, startOffset, endOffset)
- `onHighlightRemove: (String) -> Void` — (highlightId)
- `onScrollProgress: (Double) -> Void` — 阅读进度 0.0-1.0

**WKWebView 配置：**
- `isEditable = false`
- `allowsBackForwardNavigationGestures = false`
- 注册 `WKScriptMessageHandler` 监听 JS 消息
- 禁用默认长按菜单，使用自定义 JS 菜单

**JS → Swift 消息协议：**

```json
// 创建高亮
{ "type": "highlight.create", "text": "...", "startOffset": 123, "endOffset": 156 }

// 删除高亮
{ "type": "highlight.remove", "id": "uuid" }

// 阅读进度
{ "type": "scroll.progress", "percent": 0.42 }
```

**Swift → JS 调用：**
```swift
// 加载已有高亮
webView.evaluateJavaScript("addHighlight('\(id)', \(start), \(end))")

// 移除高亮
webView.evaluateJavaScript("removeHighlight('\(id)')")

// 设置 dark mode
webView.evaluateJavaScript("setTheme('dark')")
```

### 3. JS 逻辑

**注入到 HTML 的 `<script>`：**

**文本选择 → 高亮：**
1. 监听 `touchend` / `mouseup` 事件（WKWebView 上 `selectionchange` 不可靠）
2. 延迟 200ms 检查 `window.getSelection()`
3. 如果 selection 长度 > 2 字符且不在已高亮 `<mark>` 区域内：
   - 显示自定义浮动菜单（"高亮" / "复制"）
   - 菜单定位：`bottom: calc(100% + 8px); left: 50%; transform: translateX(-50%)`（相对于 selection rect）
   - 菜单有向下三角箭头（CSS border trick）
4. 点击"高亮"：
   - 获取 selection 在纯文本中的 start/end offset
   - 用 `<mark class="hl" data-id="temp">` 包裹选中文字（`surroundContents`，部分重叠时 try/catch 静默失败）
   - `window.webkit.messageHandlers.folio.postMessage({ type: "highlight.create", ... })`
   - **限制：** text 长度不超过 500 字符（超长选择静默截断）
5. 点击"复制"：复制选中文本 → toast "已复制"
6. Swift 收到 create 消息后：本地 SwiftData 立即保存 → 显示成功 → 异步 POST 到后端
7. 后端返回 server ID → JS 更新 `data-id`
8. 如果网络不可用 → 本地排队，联网后批量同步（OfflineQueueManager 模式）

**偏移量计算方法：**
```javascript
function getTextOffset(node, offset) {
    // 遍历 article-body 内所有文本节点
    // 累加到目标 node 前的所有文本长度
    // 返回绝对字符偏移量
}
```

**已高亮交互：**
- 点击 `<mark class="hl">` → 显示菜单（"移除高亮" / "复制"）
- 点击"移除高亮" → 移除 `<mark>` 标签，还原文本 → postMessage `highlight.remove` → toast "已移除高亮"
- 点击"复制" → 复制高亮文本 → toast "已复制"
- 点击其他区域 → 关闭所有菜单

**Toast 通知：**
- 通过 JS bridge → Swift → 复用现有 ToastView 显示
- postMessage `{ type: "toast", message: "已移除高亮" }`

**高亮菜单样式（原型 04）：**
- 位置：选中区域上方 8px
- 背景：text-1（深色背景）
- 文字：background 色（浅色）
- 圆角：8px
- 阴影：0 4px 12px rgba(0,0,0,0.15)
- 按钮间：0.5px 分隔线
- 动画：popIn 0.15s ease

**阅读进度：**
- 监听 `scroll` 事件
- `percent = scrollTop / (scrollHeight - clientHeight)`
- 节流 100ms
- postMessage `scroll.progress`

### 4. CSS

```css
/* 高亮 */
.hl {
    background: rgba(0, 113, 227, 0.12);
    border-radius: 2px;
    padding: 1px 0;
    cursor: pointer;
    position: relative;
}

[data-theme="dark"] .hl { background: rgba(41, 151, 255, 0.15); }

/* 浮动菜单 */
.hl-popup {
    position: absolute;
    bottom: calc(100% + 8px);
    left: 50%;
    transform: translateX(-50%);
    display: none;
    background: var(--text-1);
    color: var(--bg);
    border-radius: 8px;
    padding: 6px 4px;
    box-shadow: 0 4px 12px rgba(0,0,0,0.15);
    z-index: 50;
    animation: popIn 0.15s ease;
}
.hl-popup.on { display: flex; }

/* 向下三角箭头 */
.hl-popup::after {
    content: '';
    position: absolute;
    top: 100%;
    left: 50%;
    transform: translateX(-50%);
    border: 5px solid transparent;
    border-top-color: var(--text-1);
}

.hl-popup-btn {
    padding: 6px 12px;
    font-size: 13px;
    font-weight: 500;
    border: none;
    background: none;
    color: inherit;
    border-radius: 4px;
}
.hl-popup-btn:active { opacity: 0.5; }
.hl-popup-btn + .hl-popup-btn { border-left: 0.5px solid rgba(255,255,255,0.15); }

@keyframes popIn {
    from { opacity: 0; transform: translateX(-50%) scale(0.9); }
    to { opacity: 1; transform: translateX(-50%) scale(1); }
}
```

## 后端

### 1. 补建 highlights 表

Migration 008 的 highlights 部分需要重新执行：
```sql
CREATE TABLE IF NOT EXISTS highlights (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    article_id UUID NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    text TEXT NOT NULL,
    start_offset INTEGER NOT NULL,
    end_offset INTEGER NOT NULL,
    color VARCHAR(20) NOT NULL DEFAULT 'accent',
    note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_highlights_unique ON highlights (article_id, user_id, start_offset, end_offset);
CREATE INDEX IF NOT EXISTS idx_highlights_article ON highlights (article_id, user_id);
CREATE INDEX IF NOT EXISTS idx_highlights_user ON highlights (user_id, created_at DESC);
```

**内容变化保护：** 有高亮的文章不重新抓取。在 `article:crawl` Worker 中检查 `articles.highlight_count > 0`，如果有高亮则跳过重新抓取。

### 2. 文件结构

```
server/internal/
├── domain/highlight.go          # Highlight struct
├── repository/highlight.go      # CRUD
├── service/highlight.go         # 创建时入队 echo:generate
├── api/handler/highlight.go     # HTTP handlers
```

### 3. API 端点

#### POST /api/v1/articles/{id}/highlights

创建高亮。

**请求：**
```json
{ "text": "选中的文字", "start_offset": 123, "end_offset": 156 }
```

**响应：**
```json
{
    "id": "uuid",
    "text": "选中的文字",
    "start_offset": 123,
    "end_offset": 156,
    "color": "accent",
    "created_at": "2026-03-23T10:00:00Z"
}
```

**逻辑：**
1. 验证 article 归属
2. 插入 highlights 表
3. 递增 articles.highlight_count
4. 入队 `echo:generate` with highlight_id + card_type='highlight'

**权限：** auth

#### GET /api/v1/articles/{id}/highlights

获取文章全部高亮。

**响应：**
```json
{
    "data": [
        { "id": "uuid", "text": "...", "start_offset": 123, "end_offset": 156, "color": "accent", "created_at": "..." }
    ]
}
```

**权限：** auth

#### DELETE /api/v1/highlights/{id}

删除高亮。

**逻辑：**
1. 验证归属
2. 删除 highlight
3. 递减 articles.highlight_count
4. 关联的 echo_card (highlight_id) 会因为 ON DELETE SET NULL 自动解关联

**权限：** auth

### 4. Echo 高亮回顾卡片

创建高亮时入队 `echo:generate`：
- 传入 `highlight_id` + `article_id` + `user_id`
- Worker 检测到 highlight_id → 生成 `card_type = 'highlight'` 卡片
- AI prompt 风格（匹配原型 02）：
  - question："你在一篇关于 {主题} 的文章中标注了一句话。还记得你标注的原文是什么吗？"
  - answer：高亮原文（如"API 的终极目标不是完备性，而是可预测性。用户不读文档就能猜对参数名。"）
  - source_context："你在 {日期} 标注了这段文字 · 来自《{文章标题}》"
- echo_cards.highlight_id = highlight_id

## iOS 数据层

### Highlight SwiftData 模型

**文件：** `ios/Folio/Domain/Models/Highlight.swift`

```
@Model class Highlight:
    id: UUID
    serverID: String?
    articleID: UUID
    text: String
    startOffset: Int
    endOffset: Int
    color: String = "accent"
    createdAt: Date
```

注册到 `DataManager.schema`。

### DTO + APIClient

**Network.swift 新增：**
```swift
struct HighlightDTO: Codable { id, text, startOffset, endOffset, color, createdAt }
struct CreateHighlightRequest: Codable { text, startOffset, endOffset }
struct HighlightsResponse: Codable { data: [HighlightDTO] }

// APIClient methods:
func createHighlight(articleID: String, text: String, startOffset: Int, endOffset: Int) async throws -> HighlightDTO
func getHighlights(articleID: String) async throws -> HighlightsResponse
func deleteHighlight(id: String) async throws
```

### ReaderView 改造

- 替换 `MarkdownRenderer` 为 `ArticleWebView`
- `ReaderViewModel` 新增：`highlights: [Highlight]`
- 打开文章时 GET highlights → 传入 WebView
- 高亮创建/删除通过 bridge 回调处理

## 现有代码处理

- **保留** `MarkdownRenderer.swift`、`MarkdownBlock.swift`、`CodeBlockView.swift` 等（不删除，可能被其他地方引用）
- **ReaderView** 中将 MarkdownRenderer 替换为 ArticleWebView
- **阅读进度**从 WebView scroll 事件获取（替代当前 SwiftUI GeometryReader 方案）
- **图片查看**：WebView 内图片点击通过 JS bridge 通知 Swift，复用现有 ImageViewerOverlay

## WKWebView Reader 功能对等清单

从 SwiftUI MarkdownRenderer 迁移到 WKWebView 时，必须保留以下现有功能：

| 现有功能 | WKWebView 方案 |
|---------|---------------|
| 阅读偏好（字号/行距/字体/主题） | 动态 CSS 变量注入，偏好变化时 JS bridge 更新 |
| 图片点击 → 全屏查看器 | JS 拦截 img click → postMessage `{ type: "image.tap", src: "..." }` → 复用 ImageViewerOverlay |
| 链接点击 → Safari | JS 拦截 a click → postMessage `{ type: "link.tap", href: "..." }` → Swift 打开 SafariViewController |
| 阅读进度追踪 | JS scroll 事件 → postMessage `scroll.progress` → 更新 ReaderViewModel |
| 滚动位置恢复 | 打开文章时传入 `readProgress` → JS `window.scrollTo(0, height * progress)` |
| 入场动画 | WebView 内容加载完成后回调 → Swift 控制容器 opacity 0→1（ink 动效） |
| 表格渲染 | HTML `<table>` + CSS 样式（水平滚动容器） |
| 代码块 | `<pre><code>` + SF Mono 字体 + 灰背景 + 圆角 |
| Dark mode | CSS theme 变量 + JS `setTheme()` 切换 |
| WKWebView 安全 | 禁用外部导航（`decidePolicyFor navigationAction`），拦截所有链接和表单 |

## 不做

- 多色高亮
- 高亮笔记/备注（DB `note` 列预留，不实现 UI）
- 高亮导出
- 高亮搜索（P1.3 RAG 自然支持）
- 单篇文章高亮数量限制（暂不限制，观察实际使用）
