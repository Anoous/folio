# P2 增强功能设计 — 转场动画 + 截图收藏 + 语音捕捉

**日期**：2026-03-23
**状态**：设计确认，待实现
**范围**：3 个独立 P2 功能，可并行开发

---

## 1. 转场动画精细化

### 设计理念

不对抗系统——NavigationStack push、`.sheet`、`.fullScreenCover` 本身足够好。精细化的核心是**内容编排**（content choreography）：让每个页面的内容像被"铺开"而非"弹出"。

### Motion Token 系统（已实现）

```swift
// Motion.swift — 5 个命名动画曲线
enum Motion {
    static let settle = Animation.spring(duration: 0.4, bounce: 0.05)  // 元素落位
    static let quick  = Animation.spring(duration: 0.25, bounce: 0.0)  // 按钮反馈
    static let ink    = Animation.easeOut(duration: 0.15)              // 内容显现
    static let exit   = Animation.easeIn(duration: 0.2)               // 元素退出
    static let slow   = Animation.linear(duration: 2.0)               // 进度条

    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? .none : animation
    }
}
```

### 7 个转场规格

#### 1.1 Home → Reader（内容阶梯入场）

**方案**：保留系统 NavigationStack push，Reader 内部做三段阶梯入场。

```
时间轴：
0ms   — 返回按钮 "< 页集" 就位（无动画，跟随系统 push）
50ms  — 标题 + meta 信息淡入（Motion.ink）
150ms — WebView 正文淡入（Motion.ink）
```

**实现**：ReaderView 已有部分阶梯入场逻辑（`contentReady` state + delays），审计并统一为上述时间轴。确保使用 `Motion.resolved()` 包裹。

#### 1.2 搜索结果阶梯入场

**方案**：保留系统 `.searchable()` 展开动画。搜索结果列表项做阶梯淡入。

```
每个结果项延迟 = index * 30ms
动画：Motion.ink（opacity 0→1 + translateY 4pt→0）
```

**实现**：`HomeSearchResultsView` 中为每个结果添加 `.opacity` + `.offset` modifier，用 `onAppear` 触发带延迟的 `withAnimation(Motion.ink)`。

#### 1.3 Echo 揭晓

**方案**：点击"揭晓答案" → 卡片高度弹性展开 + 答案延迟淡入。

```
0ms   — 卡片高度展开（Motion.settle，0.4s spring）
       问题文字缩小变灰
       按钮隐藏（Motion.exit）
200ms — 答案文字淡入上浮（Motion.ink，opacity + translateY 8pt→0）
       反馈按钮淡入
```

**实现**：`EchoCardView` 现有动画审计，确保匹配上述时间轴。

#### 1.4 AI 洞察展开/折叠

**方案**：点击洞察面板 → 高度动画展开详情 + chevron 旋转。

```
展开：maxHeight 0→auto（Motion.settle，0.35s）+ chevron 旋转 0°→180°
折叠：反向，Motion.settle
关键点列表各项延迟 30ms 阶梯入场
```

**实现**：ReaderView 内 insight panel 已有部分实现，统一用 `Motion.settle`。

#### 1.5 RAG 打字机 + 来源卡片

**方案**：打字机效果已有，补充来源卡片入场。

```
文字结束后 300ms — 来源卡片淡入上浮
  opacity 0→1 + translateY 8pt→0
  动画：Motion.ink
```

**实现**：`RAGAnswerView` 中来源卡片添加延迟入场。

#### 1.6 图片全屏

图片查看有两个触发点，需分别处理：

**A. WebView 内图片**（ReaderView `onImageTap` JS bridge）：
- WKWebView 内的 DOM 图片无法附加 `matchedGeometryEffect`
- 保留现有 `.fullScreenCover`，改进为：scale(0.9→1.0) + opacity(0→1) 自定义 transition，0.3s ease-out
- 关闭时反向

**B. 原生 SwiftUI 图片**（ImageView.swift、截图文章的本地图片）：
- 用 `matchedGeometryEffect`（`@Namespace`）实现缩略图 → 全屏的空间连续过渡
- 替换 `.fullScreenCover` 为 ZStack overlay + `matchedGeometryEffect`

**两者共用**：保留现有手势（pinch-to-zoom、drag-to-dismiss）

#### 1.7 Sheet 内容阶梯入场

**方案**：系统 `.sheet` 弹出动画保留，sheet 内内容做阶梯入场。

```
Sheet 弹出后：
0ms   — handle bar 就位
50ms  — 第 1 个选项淡入（Motion.ink）
80ms  — 第 2 个选项淡入
110ms — 第 3 个选项淡入
...每项 +30ms
```

**实现**：Reader 菜单 sheet、ReadingPreferenceView 等 sheet 内容添加阶梯入场。

### 全局审计

- 所有 `withAnimation` 和 `.animation` 调用审计，确保：
  1. 使用 `Motion` token 而非内联 `Animation` 值
  2. 通过 `Motion.resolved()` 包裹，Reduce Motion 时跳过动画
- 不改动已正确使用 token 的现有动画（Toast、ScaleButtonStyle 等）

---

## 2. 截图收藏（Vision OCR）

### 核心体验

分享截图 → 看到 ✓ → 完成。和分享链接一样零摩擦。

### 入口

1. **Share Extension**（主入口）：任意 App 分享图片到 Folio
2. **App 内**：ManualNoteSheet 增加"从相册选图"按钮（PhotosPicker）

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
// 新增处理流程
func processImage(_ image: UIImage) async {
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
        text = nil  // OCR 失败仍保存图片
    }

    // 4. 创建 Article
    let article = Article(url: nil, sourceType: .screenshot)
    article.localImagePath = "Images/\(filename)"
    article.markdownContent = text
    article.title = generateTitle(ocrText: text)  // 见标题生成策略
    article.status = text != nil ? .clientReady : .clientReady  // 有图即 ready
    article.wordCount = text.map { Article.countWords($0) } ?? 0
}
```

**标题生成策略**：
- 截图：OCR 文字的第一行（截断 40 字）；无 OCR 文字时为 `"截图 · {date}"`
- 语音：转写文字的第一句话（截断 40 字）；空文字时为 `"语音 · {date}"`

**OCR 错误处理**：
- OCR 返回空文字：保存纯图片文章，显示 `.saved`（不是 `.error`）
- 图片无法加载/压缩：显示 `.error`
- OCR 抛异常：仍保存图片，显示 `.saved`

#### OCR 实现

```swift
// Shared/Extraction/ImageOCRExtractor.swift（新文件，App 和 Extension 共享）
import Vision

struct ImageOCRExtractor {
    /// 从 UIImage 提取文字，支持 zh + en 混排
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

// .processing 状态显示：
// ProgressView() + "正在识别..." 文字
```

多图分享时每张图创建一篇独立 Article，顺序处理，最后统一显示 `.saved(domain: "N 张截图")`。

### App 内入口

ManualNoteSheet 底部工具栏新增相册按钮：

```
┌─────────────────────────────┐
│  记录一个想法...              │  ← 现有文本输入
│                             │
│  [📷 相册]  [🎤 语音]        │  ← 新增底部工具栏
│                    [保存]    │
└─────────────────────────────┘
```

点击 📷 → `PhotosPicker`（iOS 17 原生）→ 选图 → 同一 OCR 流程 → 保存。

### Reader 展示

截图文章在 ReaderView 中的展示：

```
┌─────────────────────────────┐
│  < 页集                      │
│                             │
│  ┌───────────────────────┐  │
│  │                       │  │  ← 原始截图（可点击放大）
│  │     [截图图片]         │  │
│  │                       │  │
│  └───────────────────────┘  │
│                             │
│  ✦ AI 摘要（如有）           │
│                             │
│  ─────────────────────────  │
│                             │
│  OCR 识别文字正文            │  ← markdownContent
│  ...                        │
└─────────────────────────────┘
```

- `localImagePath` 有值时，在标题区域展示本地图片（从 App Group 容器加载）
- 点击图片触发 `ImageViewerOverlay`（原生 SwiftUI Image，可用 Feature 1 的 matchedGeometryEffect）
- OCR 无文字时仅展示图片，不显示正文区域

### 图片存储

- 目录：`App Group Container/Images/`
- 命名：`{UUID}.jpg`
- 压缩策略：存储 max 1920px / quality 0.8；OCR 输入 max 1280px / quality 0.9
- **清理机制**：在 `ReaderViewModel.deleteArticle()` 中，删除 Article 前检查 `localImagePath`，如有值则同步删除对应文件。另加启动时扫描清理（`Images/` 目录中不再有对应 Article 的孤儿文件）

---

## 3. 语音捕捉（Speech）

### 核心体验

一个按钮、说一句话、保存。捕捉稍纵即逝的想法。

### 入口

**ManualNoteSheet 麦克风按钮**（与 Feature 2 的相册按钮并列）

### 录制 UI

点击 🎤 → 弹出录制 Sheet（`.medium` detent）：

**录制状态**：
```
┌─────────────────────────────┐
│         ● 录音中 0:12        │
│                             │
│      ∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿       │  ← 实时音频波形
│                             │
│  "数据飞轮比算法更重要，     │  ← SFSpeechRecognizer 实时转写
│   今天播客的核心观点"        │
│                             │
│         ⏹ 停止录制           │
└─────────────────────────────┘
```

**预览状态**（停止后）：
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
```

### 技术方案

#### 语音识别

```swift
// Presentation/Home/VoiceRecordingView.swift（新文件）

// SFSpeechRecognizer — 端侧实时识别
let recognizer = SFSpeechRecognizer(locale: Locale.current)
let request = SFSpeechAudioBufferRecognitionRequest()
request.requiresOnDeviceRecognition = true  // 强制端侧，iOS 17 支持 zh + en
request.shouldReportPartialResults = true   // 实时部分结果

// AVAudioEngine — 音频采集 + 波形数据
let audioEngine = AVAudioEngine()
let inputNode = audioEngine.inputNode
inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
    request.append(buffer)
    // 计算 RMS 值驱动波形可视化
}
```

#### 波形可视化

```swift
// 简洁波形：中心线 + 左右对称的振幅条
// 数据源：AVAudioEngine tap 计算的 RMS 值
// 滚动显示最近 N 个采样点
// 动画：每个新采样点用 Motion.quick 进入
```

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
- `Article(content: transcribedText)` 便捷初始化器可复用，但 sourceType 需改为 `.voice`
  - 新增便捷初始化器或在保存时手动设置 `sourceType = .voice`

### 录制限制

- **最大录制时长**：120 秒。到达上限自动停止并进入预览状态。
- 录制 UI 显示时长倒计时（最后 10 秒变红）

### AI 流程

转写文字 → 正常 AI 分析管线（分类/标签/摘要），与手动笔记一致。

---

## 跨功能变更汇总

### 数据模型（Article.swift）

| 变更 | 类型 |
|------|------|
| `SourceType` 新增 `.screenshot`, `.voice` | enum case |
| `Article.localImagePath: String?` | 新字段 |
| `SourceType.iconName` / `.displayName` 扩展 | computed property |
| `SourceType.supportsClientExtraction` 返回 `false` | computed property |

### 新文件

| 文件 | 位置 | 用途 |
|------|------|------|
| `ImageOCRExtractor.swift` | `Shared/Extraction/` | Vision OCR（App + Extension 共享） |
| `VoiceRecordingView.swift` | `Presentation/Home/` | 语音录制 Sheet UI |
| `AudioWaveformView.swift` | `Presentation/Components/` | 波形可视化组件 |

### 修改文件

| 文件 | 变更 |
|------|------|
| `Article.swift` | 新增字段和 enum cases |
| `Motion.swift` | 无变更（已完备） |
| `ShareViewController.swift` | 新增图片处理流程 |
| `CompactShareView.swift` | 新增 `.processing` 状态 |
| `ShareExtension/Info.plist` | 新增图片支持 |
| `Folio/Info.plist` | 新增麦克风和语音识别权限描述 |
| `ManualNoteSheet.swift` | 新增相册和麦克风按钮 |
| `ReaderView.swift` | 截图文章展示本地图片；matchedGeometryEffect |
| `ImageViewerOverlay.swift` | matchedGeometryEffect 改造 |
| `HomeSearchResultsView.swift` | 搜索结果阶梯入场 |
| `EchoCardView.swift` | 动画时间轴审计 |
| `RAGAnswerView.swift` | 来源卡片延迟入场 |
| `ReaderView.swift` | 内容阶梯入场、insight 展开动画、sheet 内容入场 |
| `project.yml` | 确认 Vision/Speech/AVFoundation 框架链接 |
| `SyncService.swift` | 新增 `.screenshot`/`.voice` 路由到 `submitManualContent` |

### 同步管线（SyncService）

现有 `SyncService.submitPendingArticles` 按 sourceType 分支路由：
- `.manual` → `submitManualContent`
- 有客户端提取 → `submitArticle(content:)`
- 其他 → `submitArticle(url:)`

截图和语音没有 URL，不是 `.manual`，会落入 `submitArticle(url: nil)` 导致服务端报错。

**修复**：扩展 `.manual` 分支为 `[.manual, .screenshot, .voice]`，统一走 `submitManualContent` 路径。`SubmitManualContentRequest` 新增 `source_type` 字段，让服务端正确记录。

```swift
// SyncService.swift — 路由修改
let textOnlyTypes: [SourceType] = [.manual, .screenshot, .voice]
if textOnlyTypes.contains(article.sourceType) {
    try await submitManualContent(article)
} else if article.extractionSource == .client {
    ...
}
```

### 后端变更

虽然 OCR 和语音转写都在端侧完成，但同步管线需要后端配合：

#### 1. 新增 SourceType 常量

```go
// server/internal/domain/article.go
const (
    // ... 现有 ...
    SourceScreenshot SourceType = "screenshot"
    SourceVoice      SourceType = "voice"
)
```

#### 2. 扩展手动内容接口

`POST /api/v1/articles/manual` 的 request body 新增可选 `source_type` 字段：

```go
type SubmitManualContentRequest struct {
    Content    string `json:"content"`
    SourceType string `json:"source_type,omitempty"` // 新增：manual | screenshot | voice
}
```

Handler 中：如果 `source_type` 为空则默认 `manual`（向后兼容）。

#### 3. Worker 路由保护

`article:crawl` Worker 检查 sourceType，对 `screenshot` / `voice` 跳过抓取，直接入队 `article:ai`。

#### 4. 数据库

无迁移。`source_type` 是 `VARCHAR(20)`，新值直接写入。`local_image_path` 是纯客户端字段，不上传。

### 框架链接

`project.yml` 需确认以下系统框架已链接（可能被 `import` 自动链接，但显式声明更安全）：
- `Vision.framework`（OCR）
- `Speech.framework`（语音识别）
- `AVFoundation.framework`（音频录制）
- `PhotosUI`（iOS 17 PhotosPicker，`import PhotosUI` 自动链接）
