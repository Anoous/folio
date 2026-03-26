# 截图收藏完善设计

完善截图文章的展示体验：Reader 内图文混合展示、Home 卡片缩略图、全屏图片查看器。

## 现状

- 用户从 CaptureBar 选择图片 → ContentSaveService 保存到 App Group Images/ 目录 → 创建 Article (sourceType=.screenshot)
- Vision OCR 后台提取文本 → 写入 markdownContent
- Phase 2 已修复：OCR 失败时设置 fallback 标题 "Screenshot"，日志记录
- `cleanupLocalImage()` 在删除时清理本地图片文件
- 问题：Reader 展示截图文章时只显示 OCR 文本（与普通文章一样），无法看到原图；Home 卡片也无缩略图区分

## 定义

**"有 OCR 文本"** = `article.markdownContent != nil && !article.markdownContent!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty`

## 设计

### 1. Reader 截图展示

ReaderView 检测 `article.sourceType == .screenshot`，在 markdown 正文上方插入截图图片。

**有 OCR 文本时：**
```
┌─────────────────────────────────┐
│ < 页集          ⋯              │
├─────────────────────────────────┤
│ ┌─────────────────────────┐    │
│ │       截图原图            │    │  可点击 → 全屏查看
│ │   (宽度铺满, 高度按比例,   │    │  最大高度 300pt
│ │    圆角 12, 可点击)       │    │
│ └─────────────────────────┘    │
│                                │
│ Screenshot 标题                 │  标题行
│ 3月27日 · 截图                  │  元信息行
│                                │
│ ✦ AI 摘要 (如有)               │  洞察面板
│                                │
│ OCR 文本作为 markdown 正文      │  WebView 渲染
└─────────────────────────────────┘
```

**无 OCR 文本时：**
```
┌─────────────────────────────────┐
│ ┌─────────────────────────┐    │
│ │       截图原图            │    │  图片占更大面积（无最大高度限制）
│ │                         │    │
│ └─────────────────────────┘    │
│                                │
│ Screenshot                      │
│ 3月27日 · 截图                  │
│                                │
│   📄 未识别到文本内容           │  空状态
│   点击图片可查看原图             │
└─────────────────────────────────┘
```

实现：在 ReaderView body 中，`insightPanel` 之前插入条件渲染的 `ScreenshotImageView`。

**无障碍**：图片 `accessibilityLabel` 使用 OCR 文本（截断至 200 字符），无文本时使用 "截图"。

### 2. Home Feed 卡片

ArticleCardView 和 HeroArticleCardView 检测 `article.sourceType == .screenshot && article.localImagePath != nil`，显示缩略图。

普通卡片：左侧 60x60pt 缩略图，圆角 8，`ContentMode.fill` 裁剪。
```
┌──────────────────────────────────────┐
│ ┌────┐  Screenshot 标题              │
│ │ 📷 │  3月27日 · 截图               │
│ │缩略│  OCR 文本预览...              │
│ └────┘                               │
└──────────────────────────────────────┘
```

Hero 卡片：顶部显示截图缩略图（宽度铺满，高度 160pt，圆角 12）。

**无障碍**：缩略图 `accessibilityLabel = "截图预览"`。

### 3. 全屏图片查看器

点击截图图片 → 全屏 overlay（ZStack，不使用 `.fullScreenCover`——iOS 17 不支持自定义 modal 过渡动画）：
- 黑色背景 + 右上角白色 X 按钮
- 支持 pinch to zoom（最大 5x）
- 双击切换 1x / 2x
- 过渡动画：`.opacity` + `Motion.settle`
- 不做下拉手势关闭（增加复杂度，X 按钮已足够）

实现：`FullScreenImageViewer` 作为 ZStack overlay 呈现，内部用 `ZoomableScrollView`（UIScrollView 包装的 UIViewRepresentable，通过 Coordinator 管理 zoom 状态和双击手势）。

**无障碍**：关闭按钮 `accessibilityLabel = "关闭图片"`，图片与 Reader 中的相同 label。

### 4. 本地图片加载

新建 `LocalImageLoader`：
- 输入：`localImagePath`（相对路径，如 `Images/xxx.jpg`）
- 从 App Group container 加载图片
- 支持缩略图模式（指定 maxDimension，使用 `ImageIO` 降采样避免全尺寸解码）
- **异步加载**：`func load(...) async -> UIImage?`，在后台队列执行磁盘 I/O
- 缓存：`NSCache<NSString, UIImage>`，`totalCostLimit = 50 * 1024 * 1024`（50 MB）
- 不标记 `@MainActor`——仅缓存访问需要线程安全（NSCache 自带线程安全）

```swift
final class LocalImageLoader {
    static let shared = LocalImageLoader()
    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.totalCostLimit = 50 * 1024 * 1024  // 50 MB
    }

    func load(relativePath: String, maxDimension: CGFloat? = nil) async -> UIImage? {
        let key = "\(relativePath)_\(maxDimension ?? 0)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        // Background: App Group container + ImageIO downsample + cache
        return await Task.detached { ... }.value
    }
}
```

View 层使用 `.task` modifier 异步加载，避免滚动卡顿。

### 5. 文件缺失容错

截图文章的图片文件可能被删除（手动清理、iCloud 同步等）。所有图片加载点必须处理文件缺失：
- `LocalImageLoader.load()` 返回 nil → View 显示占位符（灰色背景 + 相机图标）
- 删除文章时 `cleanupLocalImage()` 已处理文件清理
- 不需要额外的 stale reference 检测

## 文件变更

| 操作 | 文件 |
|------|------|
| 新建 | `ios/Folio/Presentation/Reader/ScreenshotImageView.swift` |
| 新建 | `ios/Folio/Presentation/Components/FullScreenImageViewer.swift` |
| 新建 | `ios/Folio/Utils/LocalImageLoader.swift` |
| 修改 | `ios/Folio/Presentation/Reader/ReaderView.swift` — 插入截图图片 |
| 修改 | `ios/Folio/Presentation/Home/ArticleCardView.swift` — 截图缩略图 |
| 修改 | `ios/Folio/Presentation/Home/HeroArticleCardView.swift` — Hero 截图缩略图 |

## 不在范围

- 多图截图（一次只保存一张）
- 图片编辑/裁剪
- 图片同步到服务器（截图是本地资源）
- OCR 重试机制
- 截图文章的 AI 分析（需要后端支持，另议）
- 搜索结果行（SearchResultRow）的截图区分——搜索频率低，后续迭代
- 下拉手势关闭图片查看器——X 按钮已足够

## 测试

- LocalImageLoader 单元测试（加载、缓存命中、降采样、文件缺失返回 nil、缓存上限）
- 手动验证：保存截图 → Home 显示缩略图 → Reader 显示图文 → 点击放大 → 双击缩放 → 关闭
- 无 OCR 文本截图的空状态展示
- 删除截图文章后重新进入列表无崩溃
