# 截图收藏完善设计

完善截图文章的展示体验：Reader 内图文混合展示、Home 卡片缩略图、全屏图片查看器。

## 现状

- 用户从 CaptureBar 选择图片 → ContentSaveService 保存到 App Group Images/ 目录 → 创建 Article (sourceType=.screenshot)
- Vision OCR 后台提取文本 → 写入 markdownContent
- Phase 2 已修复：OCR 失败时设置 fallback 标题 "Screenshot"，日志记录
- 问题：Reader 展示截图文章时只显示 OCR 文本（与普通文章一样），无法看到原图；Home 卡片也无缩略图区分

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
│ │       截图原图            │    │  图片占更大面积
│ │   (最大高度不限)          │    │
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

### 2. Home Feed 卡片

ArticleCardView 检测 `article.sourceType == .screenshot && article.localImagePath != nil`，在卡片左侧显示缩略图。

```
┌──────────────────────────────────────┐
│ ┌────┐  Screenshot 标题              │
│ │ 📷 │  3月27日 · 截图               │
│ │缩略│  OCR 文本预览...              │
│ └────┘                               │
└──────────────────────────────────────┘
```

缩略图规格：60x60pt，圆角 8，`ContentMode.fill` 裁剪。

### 3. 全屏图片查看器

点击截图图片 → 全屏 overlay：
- 黑色背景 + 白色关闭按钮
- 支持 pinch to zoom（最大 5x）
- 双击切换 1x / 2x
- 下拉手势关闭（可选，增加体验但增加复杂度）
- 过渡动画使用 `Motion.settle`

实现：`FullScreenImageViewer` 作为 `.fullScreenCover` 呈现，内部用 `ZoomableScrollView`（UIScrollView 包装）。

### 4. 本地图片加载

新建 `LocalImageLoader` 工具类：
- 输入：`localImagePath`（相对路径，如 `Images/xxx.jpg`）
- 从 App Group container 加载图片
- 支持缩略图模式（指定 maxDimension 降采样）
- 缓存：使用 `NSCache` 避免重复磁盘 I/O

```swift
@MainActor
final class LocalImageLoader {
    static let shared = LocalImageLoader()
    private let cache = NSCache<NSString, UIImage>()

    func load(relativePath: String, maxDimension: CGFloat? = nil) -> UIImage? {
        // ... App Group container + 降采样 + 缓存
    }
}
```

## 文件变更

| 操作 | 文件 |
|------|------|
| 新建 | `ios/Folio/Presentation/Reader/ScreenshotImageView.swift` |
| 新建 | `ios/Folio/Presentation/Components/FullScreenImageViewer.swift` |
| 新建 | `ios/Folio/Utils/LocalImageLoader.swift` |
| 修改 | `ios/Folio/Presentation/Reader/ReaderView.swift` — 插入截图图片 |
| 修改 | `ios/Folio/Presentation/Home/ArticleCardView.swift` — 截图缩略图 |

## 不在范围

- 多图截图（一次只保存一张）
- 图片编辑/裁剪
- 图片同步到服务器（截图是本地资源）
- OCR 重试机制
- 截图文章的 AI 分析（需要后端支持，另议）

## 测试

- LocalImageLoader 单元测试（加载、缓存、降采样）
- 手动验证：保存截图 → Home 显示缩略图 → Reader 显示图文 → 点击放大 → 关闭
- 无 OCR 文本截图的空状态展示
