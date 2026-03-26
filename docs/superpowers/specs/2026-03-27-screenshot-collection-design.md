# 截图收藏完善设计

增强已有截图展示：Reader 大图展示、HeroCard 缩略图、无 OCR 文本空状态、异步图片加载。

## 现状（已有功能）

- `ContentSaveService` — 保存截图到 App Group Images/，Vision OCR 提取文本
- `ReaderView.screenshotContentView` — 截图文章的 Reader 展示（80x120 缩略图 + "查看原图" + OCR 文本）
- `ImageViewerOverlay` — 全屏图片查看器（pinch, 双击缩放, 拖拽关闭），已支持本地文件
- `ArticleCardView` — Home 卡片已有截图缩略图（60x60）
- `cleanupLocalImage()` — 删除文章时清理本地图片

## 问题

1. Reader 截图缩略图太小（80x120），用户想看清截图内容要点击"查看原图"
2. HeroArticleCardView 无截图特殊处理
3. 无 OCR 文本时 Reader 只显示空白（无提示）
4. 图片加载是同步的 `UIImage(contentsOfFile:)`，长列表滚动可能卡顿

## 定义

**"有 OCR 文本"** = `article.markdownContent != nil && !article.markdownContent!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty`

## 改动

### 1. Reader 截图展示升级

修改 `ReaderView.screenshotContentView`，将 80x120 缩略图改为大图展示：

**有 OCR 文本时：**
```
┌─────────────────────────────────┐
│ ┌─────────────────────────┐    │
│ │       截图原图            │    │  宽度铺满, 高度按比例
│ │   (圆角 12, 可点击放大)   │    │  最大高度 300pt
│ └─────────────────────────┘    │
│                                │
│ OCR 文本（纯文本渲染）          │  现有 Text() 渲染
└─────────────────────────────────┘
```

**无 OCR 文本时：**
```
┌─────────────────────────────────┐
│ ┌─────────────────────────┐    │
│ │       截图原图            │    │  宽度铺满, 最大高度 400pt
│ └─────────────────────────┘    │
│                                │
│   📄 未识别到文本内容           │  空状态提示
│   点击图片可查看原图             │
└─────────────────────────────────┘
```

注意：长截图需要限制最大高度（300pt 有文本 / 400pt 无文本），全尺寸在 ImageViewerOverlay 中查看。

### 2. HeroArticleCardView 截图处理

在 HeroArticleCardView 中，截图文章在标题上方显示缩略图：
- 宽度铺满，高度 140pt，圆角 12，`ContentMode.fill` 裁剪
- 可点击进入文章详情（与 hero card 行为一致）

### 3. 异步图片加载

当前 `UIImage(contentsOfFile:)` 在主线程同步执行。改为：
- ReaderView 和 HeroCard 中用 `@State private var screenshotImage: UIImage?` + `.task { }` 异步加载
- ArticleCardView 已有的缩略图较小（60x60），同步加载可接受，暂不改

### 4. 无障碍

- 截图图片 `accessibilityLabel`：有 OCR 文本时用文本前 200 字符，无文本时用 "截图"
- 空状态提示 `accessibilityLabel = "未识别到文本内容"`

## 文件变更

| 操作 | 文件 | 改动 |
|------|------|------|
| 修改 | `ReaderView.swift` | `screenshotContentView` 大图 + 空状态 + async 加载 |
| 修改 | `HeroArticleCardView.swift` | 截图缩略图 + async 加载 |

**不新建文件。** 复用 `ImageViewerOverlay`（已有全屏查看器）。

## 不在范围

- 新建 LocalImageLoader / FullScreenImageViewer（已有 ImageViewerOverlay）
- ArticleCardView 改动（已有截图缩略图）
- 搜索结果行截图区分
- 图片同步到服务器（截图仅限原设备）
- 下拉手势关闭（ImageViewerOverlay 已支持）

## 测试

- 手动验证：保存截图 → Home 普通卡片显示缩略图 → Hero 卡片显示缩略图 → Reader 大图 + OCR 文本 → 点击放大 → 关闭
- 无 OCR 文本截图的空状态展示
- 删除截图文章后列表无崩溃
