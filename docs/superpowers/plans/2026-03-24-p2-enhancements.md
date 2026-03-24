# P2 Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement 3 P2 features — transition animations, screenshot capture (Vision OCR), and voice capture (Speech) — with shared data model foundation.

**Architecture:** Shared data model foundation (Article.swift + backend) → 3 independent feature tracks that can run in parallel. Hero card-to-reader transition replaces NavigationStack push with ZStack overlay + matchedGeometryEffect. Screenshot and voice share a CaptureBarView at the bottom of Home. All new content types sync via the existing `submitManualContent` path.

**Tech Stack:** SwiftUI, SwiftData, Vision framework, Speech framework, AVFoundation, PhotosUI, Go/chi/asynq

**Spec:** `docs/superpowers/specs/2026-03-23-p2-enhancements-design.md`

---

## Task 1: Data Model Foundation — Article.swift

**Files:**
- Modify: `ios/Folio/Domain/Models/Article.swift`

- [ ] **Step 1: Add new SourceType cases**

In `Article.swift`, add `screenshot` and `voice` to the `SourceType` enum (after line 28 `case manual`):

```swift
case screenshot
case voice
```

Update `supportsClientExtraction` (around line 30) to return `false` for these:

```swift
var supportsClientExtraction: Bool {
    switch self {
    case .youtube, .manual, .screenshot, .voice:
        return false
    default:
        return true
    }
}
```

- [ ] **Step 2: Add localImagePath field to Article**

Add after `clientExtractedAt` (around line 99):

```swift
var localImagePath: String?  // App Group relative path for screenshot images
```

- [ ] **Step 3: Update SourceType display extensions**

In the `iconName` computed property (around line 263), add cases before `default`:

```swift
case .screenshot: return "camera.viewfinder"
case .voice: return "mic.fill"
```

In the `displayName` computed property (around line 276), add cases before `default`:

```swift
case .screenshot: return String(localized: "Screenshot", defaultValue: "截图")
case .voice: return String(localized: "Voice Note", defaultValue: "语音笔记")
```

- [ ] **Step 4: Build and verify**

Run: `xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add ios/Folio/Domain/Models/Article.swift
git commit -m "feat: add screenshot/voice source types and localImagePath field"
```

---

## Task 2: Backend — SourceType Constants + Manual Content Endpoint

**Files:**
- Modify: `server/internal/domain/article.go`
- Modify: `server/internal/api/handler/article.go`
- Modify: `server/internal/worker/crawl_handler.go`

- [ ] **Step 1: Add Go SourceType constants**

In `server/internal/domain/article.go`, add after `SourceManual` (line 25):

```go
SourceScreenshot SourceType = "screenshot"
SourceVoice      SourceType = "voice"
```

- [ ] **Step 2: Extend manual content request**

In `server/internal/api/handler/article.go`, add `SourceType` field to `submitManualRequest` struct (around line 96):

```go
type submitManualRequest struct {
    Content    string   `json:"content"`
    Title      *string  `json:"title,omitempty"`
    TagIDs     []string `json:"tag_ids,omitempty"`
    SourceType string   `json:"source_type,omitempty"`
}
```

In `HandleSubmitManual` (around line 126), pass sourceType to service. If empty, default to "manual":

```go
sourceType := req.SourceType
if sourceType == "" {
    sourceType = string(domain.SourceManual)
}
```

Verify the service layer accepts this — check `service.SubmitManualContentRequest` and add `SourceType string` field if needed.

- [ ] **Step 3: Worker routing protection**

In `server/internal/worker/crawl_handler.go`, in `ProcessTask` method, add an early return after loading the article (around line 100, before cache check):

```go
// Skip crawl for screenshot/voice — they have content, just need AI
if article.SourceType == domain.SourceScreenshot || article.SourceType == domain.SourceVoice {
    if article.MarkdownContent != nil && *article.MarkdownContent != "" {
        if err := h.enqueueAITask(ctx, p, *article.MarkdownContent); err != nil {
            return fmt.Errorf("enqueue AI for %s: %w", article.SourceType, err)
        }
        return nil
    }
    // No content — mark as ready (image-only screenshot)
    return h.repo.UpdateArticleStatus(ctx, p.ArticleID, domain.ArticleStatusReady)
}
```

- [ ] **Step 4: Build and test backend**

```bash
cd server && go build ./cmd/server
```

Expected: successful build, no errors.

- [ ] **Step 5: Commit**

```bash
git add server/internal/domain/article.go server/internal/api/handler/article.go server/internal/worker/crawl_handler.go
git commit -m "feat(server): add screenshot/voice source types, extend manual endpoint"
```

---

## Task 3: SyncService iOS — Route screenshot/voice

**Files:**
- Modify: `ios/Folio/Data/Sync/SyncService.swift`
- Modify: `ios/Folio/Data/Network/Network.swift`

- [ ] **Step 1: Update SubmitManualContentRequest**

In `Network.swift`, add `sourceType` to `SubmitManualContentRequest` (around line 93):

```swift
struct SubmitManualContentRequest: Encodable {
    let content: String
    var title: String?
    var tagIds: [String]?
    var clientId: String?
    var sourceType: String?  // NEW

    enum CodingKeys: String, CodingKey {
        case content, title
        case tagIds = "tag_ids"
        case clientId = "client_id"
        case sourceType = "source_type"  // NEW
    }
}
```

Update `submitManualContent` method (around line 618) to accept sourceType:

```swift
func submitManualContent(content: String, title: String? = nil, tagIds: [String] = [], clientId: String? = nil, sourceType: String? = nil) async throws -> SubmitArticleResponse {
    var body = SubmitManualContentRequest(content: content)
    body.title = title
    body.tagIds = tagIds.isEmpty ? nil : tagIds
    body.clientId = clientId
    body.sourceType = sourceType
    return try await request(method: "POST", path: "/api/v1/articles/manual", body: body)
}
```

- [ ] **Step 2: Update SyncService routing**

In `SyncService.swift` `submitPendingArticles` (around line 41), change the manual check to include screenshot and voice:

```swift
let textOnlyTypes: [SourceType] = [.manual, .screenshot, .voice]
if textOnlyTypes.contains(article.sourceType) {
```

Pass sourceType in the API call:

```swift
let response = try await apiClient.submitManualContent(
    content: article.markdownContent ?? "",
    title: article.title,
    clientId: article.id.uuidString,
    sourceType: article.sourceType.rawValue
)
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add ios/Folio/Data/Sync/SyncService.swift ios/Folio/Data/Network/Network.swift
git commit -m "feat: route screenshot/voice articles through manual content sync path"
```

---

## Task 4: ImageOCRExtractor — Vision OCR

**Files:**
- Create: `ios/Shared/Extraction/ImageOCRExtractor.swift`

- [ ] **Step 1: Create ImageOCRExtractor**

```swift
import UIKit
import Vision

struct ImageOCRExtractor {

    /// Extract text from an image using Vision OCR.
    /// Supports zh-Hans, zh-Hant, en-US mixed text.
    /// Returns nil if no text is found.
    func extract(from image: UIImage) async throws -> String? {
        guard let cgImage = image.cgImage else { return nil }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }

                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")

                continuation.resume(returning: text.isEmpty ? nil : text)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
```

- [ ] **Step 2: Create UIImage compression helper**

Add to the same file or a new file `ios/Shared/Extraction/UIImage+Compression.swift`:

```swift
import UIKit

extension UIImage {
    /// Resize to fit within maxWidth, maintaining aspect ratio, then compress as JPEG.
    func compressed(maxWidth: CGFloat, quality: CGFloat) -> Data? {
        let ratio = maxWidth / size.width
        guard ratio < 1 else {
            return jpegData(compressionQuality: quality)
        }
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
```

- [ ] **Step 3: Regenerate Xcode project**

```bash
cd ios && xcodegen generate
```

- [ ] **Step 4: Build and verify**

Run: `xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -5`

Expected: BUILD SUCCEEDED (new files picked up automatically via Shared/Extraction source path)

- [ ] **Step 5: Commit**

```bash
git add ios/Shared/Extraction/ImageOCRExtractor.swift ios/Shared/Extraction/UIImage+Compression.swift
git commit -m "feat: add ImageOCRExtractor (Vision OCR) and UIImage compression helper"
```

---

## Task 5: Share Extension — Image Support

**Files:**
- Modify: `ios/ShareExtension/ShareViewController.swift`
- Modify: `ios/ShareExtension/CompactShareView.swift`
- Modify: `ios/ShareExtension/Info.plist`

- [ ] **Step 1: Update Info.plist**

Add inside the `NSExtensionActivationRule` dict:

```xml
<key>NSExtensionActivationSupportsImageWithMaxCount</key>
<integer>5</integer>
```

- [ ] **Step 2: Add processing state to CompactShareView**

In `CompactShareView.swift`, add to `ShareState` enum (line 3-8):

```swift
case processing  // OCR in progress
```

Add the case to the body switch:

```swift
case .processing:
    ProgressView()
        .controlSize(.regular)
    Text("Recognizing...")
        .font(Typography.listTitle)
        .foregroundStyle(Color.folio.textSecondary)
```

- [ ] **Step 3: Add image processing to ShareViewController**

In `ShareViewController.swift`, add `import Vision` at top.

In `processInput()`, after the `UTType.plainText` handling (around line 60), add image handling:

```swift
// Image type
if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
    attachment.loadItem(forTypeIdentifier: UTType.image.identifier) { [weak self] item, error in
        guard let self else { return }
        Task { @MainActor in
            var image: UIImage?
            if let url = item as? URL {
                image = UIImage(contentsOfFile: url.path)
            } else if let data = item as? Data {
                image = UIImage(data: data)
            }
            guard let image else {
                self.showAndDismiss(.error)
                return
            }
            await self.processImage(image)
        }
    }
    return
}
```

Add the `processImage` method:

```swift
@MainActor
private func processImage(_ image: UIImage) async {
    guard let context = modelContainer?.mainContext else {
        showAndDismiss(.error)
        return
    }

    let isPro = UserDefaults.appGroup?.bool(forKey: "is_pro") ?? false
    guard SharedDataManager.canSave(isPro: isPro) else {
        showAndDismiss(.quotaExceeded)
        return
    }

    // Show processing state
    showAndDismiss(.processing, delay: 30) // long timeout, replaced on completion

    // Compress for storage and OCR
    guard let storageData = image.compressed(maxWidth: 1920, quality: 0.8) else {
        showAndDismiss(.error)
        return
    }
    let ocrImage = UIImage(data: image.compressed(maxWidth: 1280, quality: 0.9) ?? Data()) ?? image

    // Save image to App Group
    let filename = "\(UUID().uuidString).jpg"
    let imagesDir = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier
    )!.appendingPathComponent("Images")
    try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
    let imagePath = imagesDir.appendingPathComponent(filename)

    do {
        try storageData.write(to: imagePath)
    } catch {
        showAndDismiss(.error)
        return
    }

    // OCR (failure does not block save)
    let ocrText: String?
    do {
        ocrText = try await ImageOCRExtractor().extract(from: ocrImage)
    } catch {
        ocrText = nil
    }

    // Create article
    let manager = SharedDataManager(context: context)
    let article = Article(url: nil, sourceType: .screenshot)
    article.localImagePath = "Images/\(filename)"
    article.markdownContent = ocrText
    article.title = Self.generateScreenshotTitle(ocrText: ocrText)
    article.status = .clientReady
    article.wordCount = ocrText.map { Article.countWords($0) } ?? 0

    context.insert(article)
    try? context.save()

    SharedDataManager.incrementQuota()
    UserDefaults.appGroup?.set(true, forKey: AppConstants.shareExtensionDidSaveKey)

    showAndDismiss(.saved(domain: "截图"))
}

private static func generateScreenshotTitle(ocrText: String?) -> String {
    if let text = ocrText, !text.isEmpty {
        let firstLine = text.components(separatedBy: .newlines).first ?? text
        return String(firstLine.prefix(40))
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "M/d HH:mm"
    return "截图 · \(formatter.string(from: .now))"
}
```

- [ ] **Step 4: Regenerate and build**

```bash
cd ios && xcodegen generate
xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add ios/ShareExtension/ ios/project.yml
git commit -m "feat: Share Extension image support with Vision OCR"
```

---

## Task 6: Home Feed — Visual Differentiation for New Source Types

**Files:**
- Modify: `ios/Folio/Presentation/Home/ArticleCardView.swift`
- Modify: `ios/Folio/Presentation/Home/HeroArticleCardView.swift`

- [ ] **Step 1: Update effectiveSourceName in ArticleCardView**

In `ArticleCardView.swift`, update `effectiveSourceName` (around line 132) to handle new types:

```swift
private var effectiveSourceName: String? {
    switch article.sourceType {
    case .manual:
        return article.wordCount < 200
            ? String(localized: "My Thought")
            : String(localized: "Pasted Content")
    case .screenshot:
        return String(localized: "Screenshot", defaultValue: "截图")
    case .voice:
        return String(localized: "Voice Note", defaultValue: "语音笔记")
    default:
        return article.siteName
    }
}
```

- [ ] **Step 2: Screenshot card shows local image thumbnail**

In `ArticleCardView.swift`, modify the thumbnail section (around line 67). Replace the `coverImageURL` check to also show `localImagePath`:

```swift
// Thumbnail — coverImageURL for web articles, localImagePath for screenshots
if let localPath = article.localImagePath,
   article.sourceType == .screenshot,
   let containerURL = FileManager.default.containerURL(
       forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier
   ) {
    let imageURL = containerURL.appendingPathComponent(localPath)
    if let uiImage = UIImage(contentsOfFile: imageURL.path) {
        Image(uiImage: uiImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
} else if let urlString = article.coverImageURL,
          let url = URL(string: urlString) {
    // existing LazyImage code
    LazyImage(url: url) { state in
        // ... existing code ...
    }
    .frame(width: 72, height: 72)
    .clipShape(RoundedRectangle(cornerRadius: 8))
}
```

- [ ] **Step 3: Voice card shows mic icon before title**

In `ArticleCardView.swift`, modify the title section (around line 30). Wrap in HStack for voice type:

```swift
HStack(spacing: 4) {
    if article.sourceType == .voice {
        Image(systemName: "mic.fill")
            .font(.system(size: 12))
            .foregroundStyle(Color.folio.textTertiary)
    }
    Text(article.displayTitle)
        .font(isUnread ? Typography.v3CardTitleUnread : Typography.v3CardTitle)
        .foregroundStyle(isFailed ? Color.folio.textTertiary : Color.folio.textPrimary)
        .lineSpacing(17 * 0.45)
        .lineLimit(2)
}
```

- [ ] **Step 4: Update HeroArticleCardView similarly**

In `HeroArticleCardView.swift`, add mic icon HStack for voice (before line 9 title), and update metadata to show source type for screenshot/voice.

- [ ] **Step 5: Build and verify**

```bash
xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -5
```

- [ ] **Step 6: Commit**

```bash
git add ios/Folio/Presentation/Home/ArticleCardView.swift ios/Folio/Presentation/Home/HeroArticleCardView.swift
git commit -m "feat: visual differentiation for screenshot/voice articles in Home feed"
```

---

## Task 7: CaptureBarView — Home Bottom Quick Capture

**Files:**
- Create: `ios/Folio/Presentation/Home/CaptureBarView.swift`
- Modify: `ios/Folio/Presentation/Home/HomeView.swift`

- [ ] **Step 1: Create CaptureBarView**

```swift
import SwiftUI
import PhotosUI

struct CaptureBarView: View {
    let onMicTap: () -> Void
    let onTextTap: () -> Void
    let onPhotoSelected: (UIImage) -> Void

    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        HStack(spacing: 12) {
            // Mic button
            Button(action: onMicTap) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.folio.textSecondary)
                    .frame(width: 36, height: 36)
            }

            // Text input area (tap to expand ManualNoteSheet)
            Button(action: onTextTap) {
                Text("记录一个想法...", tableName: "Localizable", bundle: .main)
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.folio.subtleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Camera button
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.folio.textSecondary)
                    .frame(width: 36, height: 36)
            }
            .onChange(of: selectedPhoto) { _, newValue in
                guard let item = newValue else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        onPhotoSelected(image)
                    }
                    selectedPhoto = nil
                }
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, 12)
        .background(Color.folio.cardBackground)
    }
}
```

- [ ] **Step 2: Integrate CaptureBarView into HomeView**

In `HomeView.swift`, add state for voice recording and photo processing:

```swift
@State private var showVoiceRecording = false
```

Replace the `mainContent` area. After the `articleList` (or alongside it), add the capture bar as a bottom overlay. In the `body`, wrap the main content in a ZStack:

```swift
// In body, after the articleList or mainContent
.safeAreaInset(edge: .bottom) {
    if !isSearchActive {
        CaptureBarView(
            onMicTap: { showVoiceRecording = true },
            onTextTap: {
                noteSheetText = ""
                showNoteSheet = true
            },
            onPhotoSelected: { image in
                saveScreenshot(image)
            }
        )
    }
}
```

Add the `saveScreenshot` method:

```swift
private func saveScreenshot(_ image: UIImage) {
    guard let context = viewModel?.modelContext else { return }
    Task {
        let isPro = authViewModel.currentUser?.subscriptionLevel != "free"
        guard SharedDataManager.canSave(isPro: isPro) else { return }

        guard let storageData = image.compressed(maxWidth: 1920, quality: 0.8) else { return }

        let imagesDir = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier
        )!.appendingPathComponent("Images")
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        let filename = "\(UUID().uuidString).jpg"
        let imagePath = imagesDir.appendingPathComponent(filename)
        try? storageData.write(to: imagePath)

        let ocrImage = UIImage(data: image.compressed(maxWidth: 1280, quality: 0.9) ?? Data()) ?? image
        let ocrText = try? await ImageOCRExtractor().extract(from: ocrImage)

        let article = Article(url: nil, sourceType: .screenshot)
        article.localImagePath = "Images/\(filename)"
        article.markdownContent = ocrText
        article.title = ocrText.flatMap { text in
            let firstLine = text.components(separatedBy: .newlines).first ?? text
            return String(firstLine.prefix(40))
        } ?? "截图 · \(Date.now.formatted(.dateTime.month().day().hour().minute()))"
        article.status = .clientReady
        article.wordCount = ocrText.map { Article.countWords($0) } ?? 0

        context.insert(article)
        try? context.save()
        SharedDataManager.incrementQuota()

        viewModel?.fetchArticles()
        syncService?.submitLocalPendingArticles()
    }
}
```

Add voice recording sheet:

```swift
.sheet(isPresented: $showVoiceRecording) {
    VoiceRecordingView { transcribedText in
        saveVoiceNote(transcribedText)
    }
    .presentationDetents([.medium])
}
```

- [ ] **Step 3: Regenerate Xcode project and build**

```bash
cd ios && xcodegen generate
xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -5
```

Note: VoiceRecordingView doesn't exist yet — create a stub first:

```swift
// Temporary stub — ios/Folio/Presentation/Home/VoiceRecordingView.swift
import SwiftUI

struct VoiceRecordingView: View {
    let onSave: (String) -> Void
    var body: some View {
        Text("Voice Recording — TODO")
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add ios/Folio/Presentation/Home/CaptureBarView.swift ios/Folio/Presentation/Home/VoiceRecordingView.swift ios/Folio/Presentation/Home/HomeView.swift
git commit -m "feat: add CaptureBarView with mic, text, and photo quick capture"
```

---

## Task 8: Screenshot Reader Display

**Files:**
- Modify: `ios/Folio/Presentation/Reader/ReaderView.swift`

- [ ] **Step 1: Add screenshot content view**

In `ReaderView.swift`, add a new private view for screenshot articles. This view shows a thumbnail + "查看原图" at top, then OCR text as plain SwiftUI Text (not WebView).

Add as a method inside ReaderView:

```swift
@ViewBuilder
private var screenshotContentView: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
        // Screenshot thumbnail + "View Original"
        if let localPath = article.localImagePath,
           let containerURL = FileManager.default.containerURL(
               forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier
           ) {
            let imageURL = containerURL.appendingPathComponent(localPath)
            if let uiImage = UIImage(contentsOfFile: imageURL.path) {
                HStack(alignment: .top, spacing: 12) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onTapGesture {
                            tappedImageURL = imageURL
                        }

                    Button {
                        tappedImageURL = imageURL
                    } label: {
                        HStack(spacing: 4) {
                            Text("查看原图")
                                .font(.system(size: 14))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(Color.folio.accent)
                    }

                    Spacer()
                }
                .padding(.horizontal, Spacing.screenPadding)
            }
        }

        // OCR text as readable content
        if let content = article.markdownContent, !content.isEmpty {
            Text(content)
                .font(Typography.body)
                .foregroundStyle(Color.folio.textPrimary)
                .lineSpacing(17 * 0.65)
                .padding(.horizontal, Spacing.screenPadding)
                .textSelection(.enabled)
        }
    }
}
```

- [ ] **Step 2: Route screenshot articles to native rendering**

In ReaderView's body, where the WebView content is rendered (around line 184), add a condition:

```swift
if article.sourceType == .screenshot || article.sourceType == .voice {
    screenshotContentView
} else {
    // Existing WebView content
    ArticleWebView(...)
}
```

- [ ] **Step 3: Build and verify**

```bash
xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add ios/Folio/Presentation/Reader/ReaderView.swift
git commit -m "feat: native screenshot/voice reader display with OCR text"
```

---

## Task 9: Image Cleanup

**Files:**
- Modify: `ios/Folio/Presentation/Reader/ReaderView.swift` (or ReaderViewModel if delete logic is there)
- Modify: `ios/Folio/App/FolioApp.swift`

- [ ] **Step 1: Add cleanup on article deletion**

Find the delete action in the ReaderView or its ViewModel. Add before the SwiftData deletion:

```swift
// Clean up local image if present
if let localPath = article.localImagePath,
   let containerURL = FileManager.default.containerURL(
       forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier
   ) {
    let imagePath = containerURL.appendingPathComponent(localPath)
    try? FileManager.default.removeItem(at: imagePath)
}
```

Also add the same cleanup in `HomeView.swift` where articles are deleted via swipe action.

- [ ] **Step 2: Add startup orphan cleanup**

In `FolioApp.swift`, add to the scene `.task` block:

```swift
.task {
    cleanupOrphanImages()
}
```

```swift
private func cleanupOrphanImages() {
    guard let containerURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier
    ) else { return }

    let imagesDir = containerURL.appendingPathComponent("Images")
    guard let files = try? FileManager.default.contentsOfDirectory(
        at: imagesDir, includingPropertiesForKeys: nil
    ) else { return }

    let context = container.mainContext
    let descriptor = FetchDescriptor<Article>(
        predicate: #Predicate { $0.localImagePath != nil }
    )
    let articles = (try? context.fetch(descriptor)) ?? []
    let validPaths = Set(articles.compactMap(\.localImagePath))

    for file in files {
        let relativePath = "Images/\(file.lastPathComponent)"
        if !validPaths.contains(relativePath) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
```

- [ ] **Step 3: Build and commit**

```bash
xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -5
git add ios/Folio/Presentation/Reader/ReaderView.swift ios/Folio/App/FolioApp.swift ios/Folio/Presentation/Home/HomeView.swift
git commit -m "feat: image cleanup on article deletion and startup orphan sweep"
```

---

## Task 10: Voice Recording — Full Implementation

**Files:**
- Rewrite: `ios/Folio/Presentation/Home/VoiceRecordingView.swift` (replace stub)
- Create: `ios/Folio/Presentation/Components/AudioWaveformView.swift`

- [ ] **Step 1: Create AudioWaveformView**

```swift
import SwiftUI

struct AudioWaveformView: View {
    let levels: [CGFloat]  // 0.0 to 1.0 RMS values
    let barCount = 40
    let barWidth: CGFloat = 3
    let barSpacing: CGFloat = 2
    let maxBarHeight: CGFloat = 40
    let minBarHeight: CGFloat = 2

    var body: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(displayLevels.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(Color.folio.accent)
                    .frame(width: barWidth, height: barHeight(for: displayLevels[index]))
            }
        }
        .frame(height: maxBarHeight)
    }

    private var displayLevels: [CGFloat] {
        let padded = Array(repeating: CGFloat(0), count: max(0, barCount - levels.count)) + levels.suffix(barCount)
        return Array(padded.suffix(barCount))
    }

    private func barHeight(for level: CGFloat) -> CGFloat {
        let clamped = min(max(level, 0), 1)
        return minBarHeight + clamped * (maxBarHeight - minBarHeight)
    }
}
```

- [ ] **Step 2: Implement VoiceRecordingView**

Replace the stub with the full implementation:

```swift
import SwiftUI
import Speech
import AVFoundation

struct VoiceRecordingView: View {
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var state: RecordingState = .idle
    @State private var transcribedText = ""
    @State private var editableText = ""
    @State private var duration: TimeInterval = 0
    @State private var audioLevels: [CGFloat] = []
    @State private var timer: Timer?
    @State private var silenceCounter: Int = 0

    private let maxDuration: TimeInterval = 120
    private let silenceThreshold: Float = -50  // dB
    private let silenceAutoStopSeconds = 3

    // Audio & Speech
    @State private var audioEngine: AVAudioEngine?
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?

    enum RecordingState {
        case idle, recording, preview
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                switch state {
                case .idle:
                    idleView
                case .recording:
                    recordingView
                case .preview:
                    previewView
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .navigationTitle(state == .preview ? "转写结果" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { stopAndCleanup(); dismiss() }
                }
            }
        }
    }

    // MARK: - Recording View

    private var recordingView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            // Recording indicator + duration
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .opacity(0.8)

                Text(formattedDuration)
                    .font(.system(size: 17, weight: .medium, design: .monospaced))
                    .foregroundStyle(duration >= maxDuration - 10 ? Color.folio.error : Color.folio.textPrimary)
            }

            // Waveform
            AudioWaveformView(levels: audioLevels)
                .frame(height: 40)

            // Live transcription
            if !transcribedText.isEmpty {
                Text(transcribedText)
                    .font(Typography.body)
                    .foregroundStyle(Color.folio.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal)
            }

            Spacer()

            // Stop button
            Button(action: stopRecording) {
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14))
                    Text("停止录制")
                }
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(Color.folio.textPrimary)
                .clipShape(Capsule())
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: state)
        }
    }

    // MARK: - Preview View

    private var previewView: some View {
        VStack(spacing: Spacing.lg) {
            TextEditor(text: $editableText)
                .font(Typography.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(12)
                .background(Color.folio.subtleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer()

            HStack(spacing: 16) {
                Button("重新录制") {
                    editableText = ""
                    transcribedText = ""
                    startRecording()
                }
                .foregroundStyle(Color.folio.textSecondary)

                Spacer()

                Button("保存") {
                    let trimmed = editableText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSave(trimmed)
                    dismiss()
                }
                .fontWeight(.semibold)
                .foregroundStyle(Color.folio.accent)
                .disabled(editableText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .sensoryFeedback(.success, trigger: false)  // triggered on save
            }
        }
    }

    // MARK: - Idle View

    private var idleView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Button(action: requestPermissionsAndStart) {
                VStack(spacing: 12) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.folio.accent)
                    Text("点击开始录音")
                        .font(Typography.body)
                        .foregroundStyle(Color.folio.textSecondary)
                }
            }
            Spacer()
        }
        .onAppear { requestPermissionsAndStart() }
    }

    // MARK: - Formatted Duration

    private var formattedDuration: String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Permissions

    private func requestPermissionsAndStart() {
        AVAudioApplication.requestRecordPermission { granted in
            guard granted else { return }
            SFSpeechRecognizer.requestAuthorization { authStatus in
                guard authStatus == .authorized else { return }
                DispatchQueue.main.async { startRecording() }
            }
        }
    }

    // MARK: - Recording Control

    private func startRecording() {
        let engine = AVAudioEngine()
        let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)

            // Calculate RMS for waveform
            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)
            guard let data = channelData, frameLength > 0 else { return }

            var rms: Float = 0
            for i in 0..<frameLength {
                rms += data[i] * data[i]
            }
            rms = sqrtf(rms / Float(frameLength))
            let db = 20 * log10f(max(rms, 1e-6))

            // Normalize: -60dB..0dB -> 0..1
            let normalized = CGFloat(max(0, min(1, (db + 60) / 60)))

            DispatchQueue.main.async {
                audioLevels.append(normalized)
                if audioLevels.count > 60 { audioLevels.removeFirst() }

                // Silence detection
                if db < silenceThreshold {
                    silenceCounter += 1
                    // ~43 buffers/sec at 1024 buffer size / 44100 Hz
                    if silenceCounter > 43 * silenceAutoStopSeconds {
                        stopRecording()
                    }
                } else {
                    silenceCounter = 0
                }
            }
        }

        let task = speechRecognizer?.recognitionTask(with: request) { result, error in
            if let result {
                DispatchQueue.main.async {
                    transcribedText = result.bestTranscription.formattedString
                }
            }
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            try engine.start()
        } catch {
            return
        }

        audioEngine = engine
        recognitionRequest = request
        recognitionTask = task
        duration = 0
        silenceCounter = 0
        audioLevels = []

        withAnimation(Motion.quick) { state = .recording }

        // Duration timer
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            duration += 1
            if duration >= maxDuration {
                stopRecording()
            }
        }

        // Interruption handler
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main
        ) { _ in
            stopRecording()
        }
    }

    private func stopRecording() {
        guard state == .recording else { return }

        timer?.invalidate()
        timer = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        try? AVAudioSession.sharedInstance().setActive(false)

        editableText = transcribedText
        withAnimation(Motion.settle) { state = .preview }
    }

    private func stopAndCleanup() {
        timer?.invalidate()
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
```

- [ ] **Step 3: Wire saveVoiceNote in HomeView**

In `HomeView.swift`, add:

```swift
private func saveVoiceNote(_ text: String) {
    guard let context = viewModel?.modelContext else { return }
    let isPro = authViewModel.currentUser?.subscriptionLevel != "free"
    guard SharedDataManager.canSave(isPro: isPro) else { return }

    let article = Article(url: nil, sourceType: .voice)
    article.markdownContent = text
    let firstSentence = text.components(separatedBy: CharacterSet(charactersIn: "。.!！?？\n")).first ?? text
    article.title = String(firstSentence.prefix(40))
    article.status = .clientReady
    article.wordCount = Article.countWords(text)
    article.sourceTypeRaw = SourceType.voice.rawValue

    context.insert(article)
    try? context.save()
    SharedDataManager.incrementQuota()

    viewModel?.fetchArticles()
    syncService?.submitLocalPendingArticles()
}
```

- [ ] **Step 4: Add permissions to Info.plist**

In `ios/Folio/Info.plist` (or via project.yml settings), add:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Folio uses microphone to capture your voice notes</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>Folio uses speech recognition to transcribe your voice notes</string>
```

- [ ] **Step 5: Regenerate, build, and commit**

```bash
cd ios && xcodegen generate
xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -5
git add ios/Folio/Presentation/Home/VoiceRecordingView.swift ios/Folio/Presentation/Components/AudioWaveformView.swift ios/Folio/Presentation/Home/HomeView.swift ios/project.yml
git commit -m "feat: voice recording with real-time transcription, waveform, silence detection"
```

---

## Task 11: Hero Card-to-Reader Transition

This is the largest and most architecturally significant task. It replaces NavigationStack push for articles with a ZStack overlay + matchedGeometryEffect.

**Files:**
- Modify: `ios/Folio/App/FolioApp.swift`
- Modify: `ios/Folio/Presentation/Home/HomeView.swift`
- Modify: `ios/Folio/Presentation/Home/HomeArticleRow.swift`
- Modify: `ios/Folio/Presentation/Home/ArticleCardView.swift`
- Modify: `ios/Folio/Presentation/Home/HeroArticleCardView.swift`
- Modify: `ios/Folio/Presentation/Reader/ReaderView.swift`
- Modify: `ios/Folio/Presentation/Home/HomeSearchResultsView.swift`

- [ ] **Step 1: Add shared state to FolioApp**

In `FolioApp.swift`, add state and namespace:

```swift
@Namespace private var heroNamespace
@State private var selectedArticle: Article?
```

Wrap the NavigationStack in a ZStack overlay:

```swift
ZStack {
    NavigationStack(path: $navigationPath) {
        HomeView()
    }
    .opacity(selectedArticle == nil ? 1 : 0)
    .animation(Motion.exit, value: selectedArticle == nil)

    if let article = selectedArticle {
        ReaderView(article: article, onDismiss: {
            withAnimation(Motion.settle) {
                selectedArticle = nil
            }
        })
        .transition(.identity)
        .zIndex(1)
    }
}
.environment(\.heroNamespace, heroNamespace)
.environment(\.selectArticle, SelectArticleAction { article in
    withAnimation(Motion.settle) {
        selectedArticle = article
    }
})
```

- [ ] **Step 2: Create environment keys for hero namespace and article selection**

Create a small file or add to an existing shared location:

```swift
// ios/Folio/Presentation/Components/HeroTransition.swift
import SwiftUI

// Environment key for hero namespace
struct HeroNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var heroNamespace: Namespace.ID? {
        get { self[HeroNamespaceKey.self] }
        set { self[HeroNamespaceKey.self] = newValue }
    }
}

// Environment key for article selection action
struct SelectArticleAction {
    let action: (Article) -> Void
    func callAsFunction(_ article: Article) { action(article) }
}

struct SelectArticleKey: EnvironmentKey {
    static let defaultValue = SelectArticleAction { _ in }
}

extension EnvironmentValues {
    var selectArticle: SelectArticleAction {
        get { self[SelectArticleKey.self] }
        set { self[SelectArticleKey.self] = newValue }
    }
}
```

- [ ] **Step 3: Remove NavigationLink from HomeArticleRow**

In `HomeArticleRow.swift`, replace `NavigationLink(value: article.id)` with a plain view + tap gesture:

```swift
@Environment(\.selectArticle) private var selectArticle

var body: some View {
    ArticleCardView(article: article)
        .contentShape(Rectangle())
        .onTapGesture { selectArticle(article) }
        .onAppear { if isLast { onAction(.loadMore) } }
        // ... keep swipe actions and context menu ...
}
```

- [ ] **Step 4: Remove NavigationLink from HeroArticleCardView in HomeView**

In `HomeView.swift`, where `HeroArticleCardView` is rendered inside a `NavigationLink(value: article.id)` (around line 452), replace with:

```swift
HeroArticleCardView(article: article)
    .contentShape(Rectangle())
    .onTapGesture { selectArticle(article) }
```

Add `@Environment(\.selectArticle) private var selectArticle` to HomeView.

- [ ] **Step 5: Remove the UUID navigationDestination**

In `HomeView.swift`, remove or comment out the `.navigationDestination(for: UUID.self)` block (lines 91-95). Articles are no longer navigated via NavigationStack.

Keep `.navigationDestination(for: HomeDestination.self)` for Settings.

- [ ] **Step 6: Add matchedGeometryEffect to ArticleCardView**

In `ArticleCardView.swift`, add namespace environment:

```swift
@Environment(\.heroNamespace) private var heroNamespace
```

Add `.matchedGeometryEffect` to the title:

```swift
Text(article.displayTitle)
    // ... existing modifiers ...
    .matchedGeometryEffect(
        id: heroNamespace != nil ? "title-\(article.id)" : "",
        in: heroNamespace ?? Namespace().wrappedValue,
        isSource: heroNamespace != nil
    )
```

Note: Use a guard pattern — only apply matchedGeometryEffect when namespace is available.

Better approach — use a conditional modifier:

```swift
.modifier(HeroGeometryModifier(id: "title-\(article.id)", namespace: heroNamespace))
```

```swift
struct HeroGeometryModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let ns = namespace {
            content.matchedGeometryEffect(id: id, in: ns)
        } else {
            content
        }
    }
}
```

Add this to `HeroTransition.swift`.

Apply to: title, insight pull quote bar, meta line.

- [ ] **Step 7: Add matching matchedGeometryEffect to ReaderView**

In `ReaderView.swift`, add `onDismiss` closure parameter:

```swift
var onDismiss: (() -> Void)?
```

Add namespace environment:

```swift
@Environment(\.heroNamespace) private var heroNamespace
```

Apply `.modifier(HeroGeometryModifier(...))` to matching elements in the reader:
- Title text
- Insight panel summary text

Replace the custom back button action (around line 63 `dismiss()`) to call `onDismiss?()` when available:

```swift
Button {
    if let onDismiss {
        onDismiss()
    } else {
        dismiss()
    }
} label: {
    // existing chevron + "页集"
}
```

- [ ] **Step 8: Add swipe-to-dismiss gesture**

Add to ReaderView body:

```swift
@GestureState private var dragOffset: CGFloat = 0

// On the reader content
.offset(x: dragOffset)
.scaleEffect(1 - dragOffset / 1000)
.gesture(
    DragGesture()
        .updating($dragOffset) { value, state, _ in
            if value.translation.width > 0 {
                state = value.translation.width
            }
        }
        .onEnded { value in
            if value.translation.width > 80 {
                onDismiss?()
            }
        }
)
```

- [ ] **Step 9: Update SearchResultsView navigation**

In `HomeSearchResultsView.swift`, replace `NavigationLink(value: item.article.id)` (around line 182) with the selectArticle environment action:

```swift
@Environment(\.selectArticle) private var selectArticle

// In resultsSection ForEach:
Button {
    selectArticle(item.article)
} label: {
    SearchResultRow(...)
}
```

- [ ] **Step 10: Add haptic feedback**

In FolioApp.swift, add `.sensoryFeedback(.impact(weight: .light), trigger: selectedArticle != nil)`.

- [ ] **Step 11: Build and verify**

```bash
cd ios && xcodegen generate
xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -5
```

- [ ] **Step 12: Commit**

```bash
git add ios/Folio/App/FolioApp.swift ios/Folio/Presentation/Components/HeroTransition.swift ios/Folio/Presentation/Home/HomeView.swift ios/Folio/Presentation/Home/HomeArticleRow.swift ios/Folio/Presentation/Home/ArticleCardView.swift ios/Folio/Presentation/Home/HeroArticleCardView.swift ios/Folio/Presentation/Reader/ReaderView.swift ios/Folio/Presentation/Home/HomeSearchResultsView.swift
git commit -m "feat: hero card-to-reader transition with matchedGeometryEffect"
```

---

## Task 12: Micro-Transition Animations

**Files:**
- Modify: `ios/Folio/Presentation/Home/HomeSearchResultsView.swift`
- Modify: `ios/Folio/Presentation/Home/EchoCardView.swift`
- Modify: `ios/Folio/Presentation/Search/RAGAnswerView.swift`
- Modify: `ios/Folio/Presentation/Reader/ReaderView.swift`
- Modify: `ios/Folio/Presentation/Reader/ImageViewerOverlay.swift`

- [ ] **Step 1: Search result stagger animation**

In `HomeSearchResultsView.swift`, in `resultsSection`, add stagger animation to each result:

```swift
ForEach(Array(filteredResults.enumerated()), id: \.element.article.id) { index, item in
    SearchResultRow(...)
        .opacity(resultAppeared[item.article.id] ?? false ? 1 : 0)
        .offset(y: resultAppeared[item.article.id] ?? false ? 0 : 4)
        .onAppear {
            withAnimation(Motion.ink.delay(Double(index) * 0.03)) {
                resultAppeared[item.article.id] = true
            }
        }
}
```

Add `@State private var resultAppeared: [UUID: Bool] = [:]` to the view. Reset it when search text changes.

- [ ] **Step 2: Echo haptic on reveal**

In `EchoCardView.swift`, add `.sensoryFeedback(.impact(weight: .light), trigger: step == 1)` on the card. Existing animation logic is already using Motion tokens correctly.

- [ ] **Step 3: RAG source card delayed entrance**

In `RAGAnswerView.swift`, in `sourcesSection`, add:

```swift
@State private var sourcesVisible = false

// After answer finishes rendering:
.onAppear {
    withAnimation(Motion.ink.delay(0.3)) {
        sourcesVisible = true
    }
}

// On source cards:
.opacity(sourcesVisible ? 1 : 0)
.offset(y: sourcesVisible ? 0 : 8)
```

Replace `RAGLoadingView` hardcoded animation (line 342-344) with Motion token:

```swift
.animation(Motion.slow.repeatForever(autoreverses: true), value: isAnimating)
```

- [ ] **Step 4: ImageViewerOverlay — improve WebView image transition**

In `ImageViewerOverlay.swift`, replace hardcoded `.easeInOut(duration: 0.3)` and `.easeOut(duration: 0.2)` with Motion tokens:

```swift
// Double-tap zoom: replace .easeInOut(duration: 0.3) with Motion.settle
// Drag snap-back: replace .easeOut(duration: 0.2) with Motion.quick
```

Add `.sensoryFeedback(.impact(weight: .light), trigger: true)` on appear for the "focus" feel.

- [ ] **Step 5: Sheet content stagger**

In ReaderView's menu sheet content (around line 417), wrap each option in a stagger modifier:

```swift
ForEach(Array(menuOptions.enumerated()), id: \.element.id) { index, option in
    option.view
        .opacity(sheetAppeared ? 1 : 0)
        .animation(Motion.ink.delay(0.05 + Double(index) * 0.03), value: sheetAppeared)
}

// Set sheetAppeared = true in .onAppear of the sheet
```

- [ ] **Step 6: Build and verify**

```bash
xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -5
```

- [ ] **Step 7: Commit**

```bash
git add ios/Folio/Presentation/Home/HomeSearchResultsView.swift ios/Folio/Presentation/Home/EchoCardView.swift ios/Folio/Presentation/Search/RAGAnswerView.swift ios/Folio/Presentation/Reader/ReaderView.swift ios/Folio/Presentation/Reader/ImageViewerOverlay.swift
git commit -m "feat: micro-transition animations — search stagger, echo haptic, RAG source entrance, sheet stagger"
```

---

## Task 13: Global Animation Audit

**Files:**
- Audit all files using `withAnimation` or `.animation`

- [ ] **Step 1: Find all non-Motion animation usages**

```bash
# Find all inline animation values not using Motion tokens
grep -rn '\.animation(\.' ios/Folio/ --include='*.swift' | grep -v 'Motion\.' | grep -v '//__'
grep -rn 'withAnimation(\.' ios/Folio/ --include='*.swift' | grep -v 'Motion\.' | grep -v '//__'
```

- [ ] **Step 2: Replace inline animations with Motion tokens**

For each finding, determine the intent and map to the correct token:
- `.easeInOut(duration: 1.x)` repeating → `Motion.slow`
- `.easeOut(duration: 0.1-0.2)` → `Motion.ink`
- `.easeIn(duration: 0.1-0.2)` → `Motion.exit`
- `.spring(...)` → `Motion.settle` or `Motion.quick`

Skip: system framework animations, third-party code, animations in test files.

- [ ] **Step 3: Verify Reduce Motion compliance**

Ensure `Motion.resolved()` is used where appropriate. Simple state toggles (`.animation(Motion.quick, value:)`) are acceptable as SwiftUI respects the system `reduceMotion` preference for these.

- [ ] **Step 4: Build and commit**

```bash
xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -5
git add -A && git commit -m "refactor: global animation audit — unify on Motion tokens"
```

---

## Task 14: Framework Linking and XcodeGen

**Files:**
- Modify: `ios/project.yml`

- [ ] **Step 1: Add system framework dependencies**

In `project.yml`, under the Folio target dependencies (around line 65), add:

```yaml
- sdk: Vision.framework
- sdk: Speech.framework
- sdk: AVFoundation.framework
```

Under ShareExtension target dependencies (around line 112), add:

```yaml
- sdk: Vision.framework
```

(Speech and AVFoundation are not needed in the Share Extension.)

- [ ] **Step 2: Regenerate and build**

```bash
cd ios && xcodegen generate
xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add ios/project.yml ios/Folio.xcodeproj
git commit -m "chore: add Vision, Speech, AVFoundation framework linking"
```

---

## Execution Order

Tasks can be partially parallelized:

```
Task 1 (Data Model) ──┬── Task 2 (Backend) ── Task 3 (SyncService)
                       │
                       ├── Task 4 (OCR) ── Task 5 (Share Extension) ── Task 6 (Feed Visual)
                       │                                                       │
                       │                                               Task 8 (Screenshot Reader)
                       │                                                       │
                       │                                               Task 9 (Image Cleanup)
                       │
                       ├── Task 7 (CaptureBar) ── Task 10 (Voice Recording)
                       │
                       └── Task 11 (Hero Transition) ── Task 12 (Micro-Transitions)
                                                               │
                                                        Task 13 (Animation Audit)
                                                               │
                                                        Task 14 (Framework Linking)
```

**Critical path:** Task 1 → Task 11 → Task 12 → Task 13 (transition animations are the most complex)

**Independent tracks after Task 1:**
- Screenshot: Tasks 4 → 5 → 6 → 8 → 9
- Voice: Tasks 7 → 10
- Animations: Tasks 11 → 12 → 13
- Backend: Tasks 2 → 3
