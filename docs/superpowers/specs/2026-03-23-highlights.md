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
| 同步策略 | 立刻同步（乐观更新） | 跨设备同步、Echo 卡片生成依赖后端 |
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
- 支持 Light/Dark mode（CSS media query 或 JS 注入 theme）
- 背景色：`#FAF9F6` (light) / `#000` (dark)

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
1. 监听 `selectionchange` 事件
2. 选中文字后延迟 200ms 检查 selection
3. 如果 selection 长度 > 2 字符且不在已高亮区域内：
   - 显示自定义浮动菜单（"高亮" / "复制"）
   - 菜单定位在 selection 上方
4. 点击"高亮"：
   - 获取 selection 在纯文本中的 start/end offset
   - 用 `<mark class="hl" data-id="temp">` 包裹选中文字
   - `window.webkit.messageHandlers.folio.postMessage({ type: "highlight.create", ... })`
5. Swift 收到后创建 Highlight，返回 server ID
6. JS 更新 `data-id` 为真实 ID

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
- 点击"移除高亮" → 移除 `<mark>` 标签，还原文本 → postMessage `highlight.remove`
- 点击其他区域 → 关闭菜单

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
}

@media (prefers-color-scheme: dark) {
    .hl { background: rgba(41, 151, 255, 0.15); }
}

/* 浮动菜单 */
.hl-popup {
    position: absolute;
    display: flex;
    background: var(--text-1);
    color: var(--bg);
    border-radius: 8px;
    padding: 6px 4px;
    box-shadow: 0 4px 12px rgba(0,0,0,0.15);
    z-index: 50;
    animation: popIn 0.15s ease;
}

.hl-popup-btn {
    padding: 6px 12px;
    font-size: 13px;
    font-weight: 500;
    border: none;
    background: none;
    color: inherit;
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
CREATE INDEX IF NOT EXISTS idx_highlights_article ON highlights (article_id, user_id);
CREATE INDEX IF NOT EXISTS idx_highlights_user ON highlights (user_id, created_at DESC);
```

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
- AI prompt：基于高亮文本 + 文章标题，生成"你标注了这句话——它出现在什么上下文中？"风格的问题
- answer = 高亮原文
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

## 不做

- 多色高亮
- 高亮笔记/备注
- 高亮导出
- 离线高亮创建（需要网络同步到后端）
- 高亮搜索（P1.3 RAG 自然支持）
