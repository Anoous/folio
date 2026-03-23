# P2 增强功能设计 — 转场动画 + 截图收藏 + 语音捕捉

**日期**：2026-03-24
**状态**：设计确认，待实现
**范围**：3 个独立 P2 功能，可并行开发

---

## 1. 转场动画精细化

### 设计理念

动画不是装饰，是信息。每个过渡都在告诉用户：你从哪里来，要去哪里。

**空间隐喻**：Folio 的内容层级是 Feed → Article → Detail。每一层转场传达"深入"的感觉——卡片是窗口，展开后你进入了内容世界；折叠后你回到了全景。

### Motion Token 系统（已实现）

```swift
enum Motion {
    static let settle = Animation.spring(duration: 0.4, bounce: 0.05)  // 落位——元素安顿到最终位置
    static let quick  = Animation.spring(duration: 0.25, bounce: 0.0)  // 反馈——按钮回应你的触碰
    static let ink    = Animation.easeOut(duration: 0.15)              // 显现——内容像被印上去
    static let exit   = Animation.easeIn(duration: 0.2)               // 退场——元素安静地离开
    static let slow   = Animation.linear(duration: 2.0)               // 进度——缓慢推进的过程

    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? .none : animation
    }
}
```

### 7 个转场规格

#### 1.1 Home → Reader — "潜入"

**情感意图**：用户点击一张卡片，卡片展开为整个阅读世界。标题、引文、来源标签从卡片位置平滑变形到阅读器位置。这是 Folio 中执行最频繁的操作，是品质感的定义性时刻。

**方案**：**ZStack overlay + matchedGeometryEffect**，不走 NavigationStack push。

```
用户点击文章卡片
  → selectedArticle = article
  → Feed 列表用 Motion.exit 淡出（opacity 0, 0.2s）
  → 卡片元素通过 matchedGeometryEffect 平滑过渡到 Reader 位置（Motion.settle, 0.4s）
     · 标题文字：卡片位置 → Reader 标题位置（字号、颜色同步过渡）
     · 洞察引文：卡片引文 → Reader 洞察面板
     · 来源标签：卡片 meta → Reader meta
  → Reader 专属内容延迟入场：
     · 150ms — 返回按钮 "< 页集" 淡入（Motion.ink）
     · 200ms — WebView 正文淡入（Motion.ink）
  → 触觉反馈：.impact(.light)

返回：
  → 点击 "< 页集" 或右滑手势
  → 反向动画：Reader 元素回到卡片位置
  → Feed 列表淡入（Motion.ink）
```

**架构变更**：

```swift
// HomeView 或 FolioApp — 新增 ZStack overlay 方式呈现 Reader
@Namespace private var heroNamespace
@State private var selectedArticle: Article?

ZStack {
    // 底层：Feed 列表（selectedArticle 有值时淡出）
    NavigationStack(path: $navigationPath) {
        HomeView()
    }
    .opacity(selectedArticle == nil ? 1 : 0)

    // 顶层：Reader overlay
    if let article = selectedArticle {
        ReaderView(article: article, namespace: heroNamespace)
            .transition(.identity)  // matchedGeometryEffect 负责动画
    }
}
```

```swift
// ArticleCardView — 给共享元素标记 matchedGeometryEffect
Text(article.displayTitle)
    .matchedGeometryEffect(id: "title-\(article.id)", in: heroNamespace)

// Reader 标题区 — 对应标记
Text(article.displayTitle)
    .matchedGeometryEffect(id: "title-\(article.id)", in: heroNamespace)
```

**NavigationStack 保留**：Settings、Auth 等页面仍走 NavigationStack push。只有 Home → Reader 改为 overlay 方式。ArticleCardView 从 `NavigationLink(value:)` 改为 `.onTapGesture { selectedArticle = article }`。

**返回手势**：自定义 `DragGesture`，右滑超过 80pt 触发返回，手指跟随有实时进度（Reader 跟随手指向右偏移 + 缩小），松手后根据距离决定完成返回还是弹回。

#### 1.2 搜索结果 — "浮现"

**情感意图**：结果从水面下一条条浮上来，不是一下子全部出现。

```
每个结果项延迟 = index * 30ms
动画：Motion.ink（opacity 0→1 + translateY 4pt→0）
```

**实现**：`HomeSearchResultsView` 中每个结果用 `onAppear` 触发带延迟的 `withAnimation(Motion.ink)`。

#### 1.3 Echo 揭晓 — "掀开"

**情感意图**：答案从问题下方被托起，有重量感。不是弹出，是缓慢揭开。

```
0ms   — 卡片高度展开（Motion.settle, 0.4s spring）
        问题文字缩小变灰
        按钮隐藏（Motion.exit）
200ms — 答案文字淡入上浮（Motion.ink, opacity + translateY 8pt→0）
        反馈按钮淡入
触觉  — .impact(.light) 在答案出现时
```

**实现**：`EchoCardView` 现有动画审计，确保匹配上述时间轴。

#### 1.4 AI 洞察展开 — "展卷"

**情感意图**：知识如卷轴展开，一层层呈现细节。

```
展开：maxHeight 0→auto（Motion.settle, 0.35s）+ chevron 旋转 0°→180°
关键点列表各项延迟 30ms 阶梯入场
折叠：反向
```

**实现**：ReaderView 内 insight panel 统一用 `Motion.settle`。

#### 1.5 RAG 打字机 — "书写"

**情感意图**：AI 正在为你书写答案，来源在写完后安静地放在桌面上。

```
打字机效果（已有）
文字结束后 300ms — 来源卡片淡入上浮
  opacity 0→1 + translateY 8pt→0
  动画：Motion.ink
```

**实现**：`RAGAnswerView` 中来源卡片添加延迟入场。

#### 1.6 图片全屏 — "聚焦"

**情感意图**：周围世界暗下来，这张图成为你注意力的唯一焦点。

**A. WebView 内图片**（ReaderView `onImageTap` JS bridge）：
- DOM 图片无法用 `matchedGeometryEffect`
- 改进 `.fullScreenCover`：scale(0.9→1.0) + opacity(0→1) 自定义 transition，0.3s ease-out
- 触觉：`.impact(.light)` 打开时

**B. 原生 SwiftUI 图片**（ImageView、截图文章本地图片）：
- `matchedGeometryEffect`（`@Namespace`）实现缩略图 → 全屏的空间连续过渡
- 替换 `.fullScreenCover` 为 ZStack overlay + `matchedGeometryEffect`

**两者共用**：保留现有手势（pinch-to-zoom、drag-to-dismiss）

#### 1.7 Sheet — "浮现"

**情感意图**：内容一层层从水面下升起。

```
Sheet 弹出后（系统动画保留）：
0ms   — handle bar 就位
50ms  — 第 1 个选项淡入（Motion.ink）
80ms  — 第 2 个选项
110ms — 第 3 个选项
...每项 +30ms
```

**实现**：Reader 菜单 sheet、ReadingPreferenceView 等添加阶梯入场。

### 全局审计

- 所有 `withAnimation` 和 `.animation` 调用审计：
  1. 使用 `Motion` token 而非内联 `Animation` 值（如 `RAGLoadingView` 中的 `.easeInOut(duration: 1.5)` 需替换）
  2. 通过 `Motion.resolved()` 包裹，Reduce Motion 时跳过动画
- 不改动已正确使用 token 的现有动画（Toast、ScaleButtonStyle 等）

---

## 2. 截图收藏（Vision OCR）

### 核心体验

分享截图 → 看到 ✓ → 完成。和分享链接一样零摩擦。截图在 Folio 中是**一等公民**——可搜索、可分类、可回顾，不是一张图片的附庸。

### 入口

1. **Share Extension**（主入口）：任意 App 分享图片到 Folio
2. **App 内快捷捕捉栏**：Home 底部 📷 按钮（见 Feature 3 "快捷捕捉栏"）

### 数据模型变更

#### SourceType 新增 case

```swift
enum SourceType: String, Codable {
    // ... 现有 cases ...
    case screenshot  // 新增
    case voice       // 新增（Feature 3 共用）
}
```

扩展属性：
- `iconName`: `"camera.viewfinder"` (screenshot), `"mic.fill"` (voice)
- `displayName`: `"Screenshot"` / `"截图"` (screenshot), `"Voice"` / `"语音"` (voice)
- `supportsClientExtraction`: `false`（screenshot 和 voice 都不需要网页提取）

#### Article 新增字段

```swift
@Model final class Article {
    // ... 现有字段 ...
    var localImagePath: String?  // 新增：App Group 容器内相对路径
}
```

**SwiftData 迁移**：`localImagePath` 是 optional `String?`，默认 `nil`，属于 lightweight migration 兼容变更。无需 `VersionedSchema` 或 `SchemaMigrationPlan`。

### Home Feed 视觉区分

截图和语音文章在 Feed 中需要与普通文章视觉区分，用户扫一眼就能识别内容类型。

**截图文章卡片**：
```
┌─────────────────────────────────────┐
│  OCR 提取的第一行文字...        [截图] │  ← 标题区，右侧显示截图缩略图（72x72）
│  │ OCR 第二行作为引文...              │  ← 洞察引文区
│  截图 · 3小时前 · AI标签              │  ← meta 行，来源显示"截图"
└─────────────────────────────────────┘
```

- 右侧 72x72 缩略图改为从 `localImagePath` 加载本地截图（而非 `coverImageURL`）
- `effectiveSourceName` 对 `.screenshot` 返回 "截图"，对 `.voice` 返回 "语音笔记"

**语音文章卡片**：
```
┌─────────────────────────────────────┐
│  🎤 转写的第一句话...                  │  ← 标题前加 mic 图标
│  │ 后续内容作为引文...                │
│  语音笔记 · 3小时前 · AI标签          │
└─────────────────────────────────────┘
```

- 无缩略图，标题前显示小号 `mic.fill` 图标（Color.folio.textTertiary, 12pt）
- `effectiveSourceName` 返回 "语音笔记"

### Share Extension 改造

#### Info.plist

```xml
<!-- 新增图片支持 -->
<key>NSExtensionActivationSupportsImageWithMaxCount</key>
<integer>5</integer>
```

#### ShareViewController 新增图片处理

处理优先级：`UTType.url` → `UTType.plainText` → **`UTType.image`**（新增）

```swift
func processImage(_ image: UIImage) async {
    // 0. Quota 检查（截图计入月度配额）
    guard SharedDataManager.canSave(isPro: isPro) else {
        showAndDismiss(.quotaExceeded)
        return
    }

    // 1. 压缩：存储用 1920px，OCR 用 1280px（Share Extension 120MB 内存限制）
    let storageImage = image.compressed(maxWidth: 1920, quality: 0.8)
    let ocrImage = image.compressed(maxWidth: 1280, quality: 0.9)

    // 2. 保存到 App Group 容器
    let filename = "\(UUID().uuidString).jpg"
    let path = appGroupContainer.appendingPathComponent("Images/\(filename)")
    storageImage.write(to: path)

    // 3. Vision OCR（失败不阻塞保存）
    let text: String?
    do {
        text = try await ImageOCRExtractor().extract(from: ocrImage)
    } catch {
        text = nil
    }

    // 4. 创建 Article
    let article = Article(url: nil, sourceType: .screenshot)
    article.localImagePath = "Images/\(filename)"
    article.markdownContent = text
    article.title = generateTitle(ocrText: text)
    article.status = .clientReady  // 有图即 ready
    article.wordCount = text.map { Article.countWords($0) } ?? 0

    // 5. 配额 + 通知主 App
    SharedDataManager.incrementQuota()
    UserDefaults.appGroup.set(true, forKey: AppConstants.shareExtensionDidSaveKey)
}
```

**标题生成策略**：
- 截图：OCR 文字的第一行（截断 40 字）；无 OCR 文字时为 `"截图 · {date}"`
- 语音：转写文字的第一句（截断 40 字）；空文字时为 `"语音 · {date}"`

**OCR 错误处理**：
- OCR 返回空文字：保存纯图片文章，显示 `.saved`
- 图片无法加载/压缩：显示 `.error`
- OCR 抛异常：仍保存图片，显示 `.saved`

多图分享：每张图一篇独立 Article，顺序处理，最后显示 `.saved(domain: "N 张截图")`。

#### OCR 实现

```swift
// Shared/Extraction/ImageOCRExtractor.swift（新文件，App 和 Extension 共享）
import Vision

struct ImageOCRExtractor {
    func extract(from image: UIImage) async throws -> String? {
        guard let cgImage = image.cgImage else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])

        let text = request.results?
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")

        return text?.isEmpty == true ? nil : text
    }
}
```

#### CompactShareView 新增状态

```swift
enum ShareState {
    // ... 现有 cases ...
    case processing  // 新增：OCR 进行中
}
// .processing → ProgressView() + "正在识别..."
```

### Reader 展示

截图文章以 OCR 文字为主体内容（可读、可搜索），原图作为上下文辅助。

```
┌─────────────────────────────┐
│  < 页集                      │
│                             │
│  ┌─────────┐                │
│  │ [截图缩] │ 查看原图 >     │  ← 缩略图 + 点击展开全屏
│  └─────────┘                │
│                             │
│  ✦ AI 摘要（如有）           │
│                             │
│  ─────────────────────────  │
│                             │
│  OCR 提取的完整文字          │  ← markdownContent，主阅读区
│  ...                        │
└─────────────────────────────┘
```

- 顶部：截图缩略图（高度 120pt，圆角，居左）+ "查看原图" 文字按钮
- 点击缩略图或"查看原图"触发 `ImageViewerOverlay`（matchedGeometryEffect）
- OCR 无文字时：仅展示截图全宽，无正文区域
- 截图文章**不走 WebView**，直接用 SwiftUI Text 渲染 markdownContent

### 图片存储

- 目录：`App Group Container/Images/`
- 命名：`{UUID}.jpg`
- 压缩策略：存储 max 1920px / quality 0.8；OCR 输入 max 1280px / quality 0.9
- **清理机制**：
  1. `ReaderViewModel.deleteArticle()` 中，删除前检查 `localImagePath`，如有值则删除文件
  2. App 启动时扫描 `Images/` 目录，清除无对应 Article 的孤儿文件

---

## 3. 语音捕捉（Speech）

### 核心体验

一个按钮、说一句话、保存。想法稍纵即逝，语音是唯一不打断心流的捕捉方式。

### 快捷捕捉栏（跨 Feature 2 & 3 共享）

**取代现有 ManualNoteSheet 入口**。Home 底部新增常驻捕捉栏，三种输入一步到位：

```
┌─ Home Feed ──────────────────────────┐
│  ...                                 │
│  ...                                 │
├──────────────────────────────────────┤
│  [🎤]   [ 记录一个想法... ]    [📷]   │  ← 快捷捕捉栏
└──────────────────────────────────────┘
```

- **🎤 麦克风**（左）：一步直达录音 Sheet
- **文字区域**（中）：点击展开 ManualNoteSheet（现有行为）
- **📷 相机**（右）：一步弹出 PhotosPicker → OCR → 保存

**设计细节**：
- 固定在 List 底部，不被滚动带走
- 样式：`Color.folio.cardBackground`，圆角 12，内边距 12
- 文字区域用 `Typography.caption`，`Color.folio.textTertiary`
- 🎤 和 📷 用 SF Symbol（17pt），`Color.folio.textSecondary`
- 安全区域：底部 padding 适配 home indicator

**替换现有入口**：搜索建议页的"记一条笔记"快捷操作保留，但改为触发同一个 ManualNoteSheet。

### 录制 UI

点击 🎤 → 弹出录制 Sheet（`.medium` detent）：

**录制状态**：
```
┌─────────────────────────────┐
│         ● 录音中 0:12        │  ← ● 有呼吸动画（Motion.slow 脉冲）
│                             │
│      ∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿       │  ← 实时波形，accent 色
│                             │
│  "数据飞轮比算法更重要，     │  ← 实时转写，Motion.ink 逐句淡入
│   今天播客的核心观点"        │
│                             │
│         ⏹ 停止录制           │
└─────────────────────────────┘

触觉：录制开始 .impact(.medium)
```

**预览状态**（停止后 / 静默自动停止后）：
```
┌─────────────────────────────┐
│        转写结果              │
│                             │
│  ┌───────────────────────┐  │
│  │ 数据飞轮比算法更重要， │  │  ← 可编辑 TextEditor
│  │ 今天播客的核心观点     │  │
│  └───────────────────────┘  │
│                             │
│   [重新录制]       [保存]    │
└─────────────────────────────┘

触觉：保存成功 .success
```

### 技术方案

#### 语音识别

```swift
// SFSpeechRecognizer — 端侧实时识别
let recognizer = SFSpeechRecognizer(locale: Locale.current)
let request = SFSpeechAudioBufferRecognitionRequest()
request.requiresOnDeviceRecognition = true  // 强制端侧
request.shouldReportPartialResults = true   // 实时部分结果

// AVAudioEngine — 音频采集 + 波形数据
let audioEngine = AVAudioEngine()
let inputNode = audioEngine.inputNode
inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
    request.append(buffer)
    // 计算 RMS 值驱动波形
}
```

#### 波形可视化

```swift
// AudioWaveformView — 居中对称振幅条
// 布局：水平排列 40 根竖条，高度 = RMS × maxHeight
// 新采样从右侧进入（Motion.quick），旧采样滚动左移
// 颜色：Color.folio.accent
// 静默时：所有条退回最小高度（2pt），保持呼吸感
```

#### 静默检测

连续 3 秒 RMS 低于阈值 → 自动停止录制 → 进入预览状态。减少一步操作。

#### 中断处理

- 来电、切换 App、通知打断 → `AVAudioSession.interruptionNotification`
- 中断时：立即停止录制，保留已转写文字，进入预览状态
- 用户返回时看到预览，可编辑后保存或重新录制
- 不丢失任何已识别的内容

#### 权限

首次点击麦克风时**依次**请求（避免同时弹两个系统弹窗）：
1. `AVAudioSession.requestRecordPermission`（Microphone）— 先请求
2. `SFSpeechRecognizer.requestAuthorization`（Speech Recognition）— 麦克风授权后再请求

Info.plist 新增：
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Folio uses microphone to capture your voice notes</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>Folio uses speech recognition to transcribe your voice notes</string>
```

### 数据模型

- `SourceType.voice`（已在 Feature 2 中定义）
- 不存储音频文件，只保存转写文字为 `markdownContent`
- 保存时手动设置 `sourceType = .voice`（不复用 `.manual` 的便捷初始化器）

### 录制限制

- **最大时长**：120 秒。到达上限自动停止并进入预览。
- 录制 UI 显示已录时长（最后 10 秒数字变 `Color.folio.error`）
- **静默自动停止**：连续 3 秒静默自动停止

### 配额

语音文章计入月度配额（与 URL、截图相同）。保存前检查 `SharedDataManager.canSave(isPro:)`。

### AI 流程

转写文字 → 正常 AI 分析管线（分类/标签/摘要），与手动笔记一致。

---

## 跨功能变更汇总

### 数据模型（Article.swift）

| 变更 | 类型 |
|------|------|
| `SourceType` 新增 `.screenshot`, `.voice` | enum case |
| `Article.localImagePath: String?` | 新字段（lightweight migration 兼容） |
| `SourceType.iconName` / `.displayName` 扩展 | computed property |
| `SourceType.supportsClientExtraction` 返回 `false` | computed property |

### 新文件

| 文件 | 位置 | 用途 |
|------|------|------|
| `ImageOCRExtractor.swift` | `Shared/Extraction/` | Vision OCR（App + Extension 共享） |
| `VoiceRecordingView.swift` | `Presentation/Home/` | 语音录制 Sheet UI + SFSpeechRecognizer |
| `AudioWaveformView.swift` | `Presentation/Components/` | 波形可视化组件 |
| `CaptureBarView.swift` | `Presentation/Home/` | 快捷捕捉栏（🎤 文字 📷） |

### 修改文件

| 文件 | 变更 |
|------|------|
| `Article.swift` | 新增 `localImagePath` 字段、`.screenshot`/`.voice` enum cases |
| `ArticleCardView.swift` | 截图卡片显示本地缩略图、语音卡片显示 mic 图标、`effectiveSourceName` 扩展 |
| `HeroArticleCardView.swift` | 同上 sourceType 视觉区分 |
| `HomeView.swift` | 移除文章的 `NavigationLink(value:)`，改为 `onTapGesture` 设置 `selectedArticle`；底部添加 `CaptureBarView`；`@Namespace` 定义 |
| `FolioApp.swift` | ZStack overlay 包裹 ReaderView，`matchedGeometryEffect` 转场 |
| `ReaderView.swift` | 接受 `Namespace` 参数，共享元素标记；截图文章展示本地图片+OCR文字（不走WebView）；自定义右滑返回手势 |
| `ImageViewerOverlay.swift` | 原生图片用 matchedGeometryEffect；WebView 图片用 scale+opacity transition |
| `ShareViewController.swift` | 新增图片处理流程（UTType.image + OCR + quota） |
| `CompactShareView.swift` | 新增 `.processing` 状态 |
| `ShareExtension/Info.plist` | 新增 `NSExtensionActivationSupportsImageWithMaxCount` |
| `Folio/Info.plist` | 新增 Microphone + Speech Recognition 权限描述 |
| `HomeSearchResultsView.swift` | 搜索结果阶梯入场动画 |
| `EchoCardView.swift` | 动画时间轴审计 + haptic |
| `RAGAnswerView.swift` | 来源卡片延迟入场；`RAGLoadingView` 替换内联动画为 Motion token |
| `project.yml` | 确认 Vision/Speech/AVFoundation/PhotosUI 框架链接 |
| `SyncService.swift` | `.screenshot`/`.voice` 路由到 `submitManualContent` |

### 同步管线（SyncService）

现有 `SyncService.submitPendingArticles` 按 sourceType 分支路由。截图和语音没有 URL，不是 `.manual`，会落入错误分支。

**修复**：扩展为 `[.manual, .screenshot, .voice]` 统一走 `submitManualContent` 路径。`SubmitManualContentRequest` 新增 `source_type` 字段。

```swift
let textOnlyTypes: [SourceType] = [.manual, .screenshot, .voice]
if textOnlyTypes.contains(article.sourceType) {
    try await submitManualContent(article)
} else if article.extractionSource == .client {
    ...
}
```

### 后端变更

#### 1. 新增 SourceType 常量

```go
// server/internal/domain/article.go
const (
    SourceScreenshot SourceType = "screenshot"
    SourceVoice      SourceType = "voice"
)
```

#### 2. 扩展手动内容接口

`POST /api/v1/articles/manual` request body 新增可选 `source_type`：

```go
type SubmitManualContentRequest struct {
    Content    string `json:"content"`
    SourceType string `json:"source_type,omitempty"` // manual | screenshot | voice
}
```

`source_type` 为空默认 `manual`（向后兼容）。

#### 3. Worker 路由保护

`article:crawl` Worker 对 `screenshot` / `voice` 跳过抓取，直接入队 `article:ai`。

#### 4. 数据库

无迁移。`source_type` 是 `VARCHAR(20)`，新值直接写入。`local_image_path` 纯客户端字段。

### 框架链接

`project.yml` 确认以下系统框架已链接：
- `Vision.framework`（OCR）
- `Speech.framework`（语音识别）
- `AVFoundation.framework`（音频录制）
- `PhotosUI`（iOS 17 PhotosPicker）
