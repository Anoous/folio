# Quiet Gravity (沉静的分量感) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Systematically add haptics, animations, visual hierarchy, and loading states to Folio iOS, following the "Quiet Gravity" design philosophy — every element has weight, content appears like ink on paper, 90% stillness makes motion meaningful.

**Architecture:** Pure presentation layer changes. New reusable components (Motion, ShimmerView, ProcessingProgressBar, ScaleButtonStyle, ReadingProgressBar) built first, then applied to existing views (ArticleCardView, HomeView, ReaderView, ToastView). No data/network changes.

**Tech Stack:** SwiftUI (iOS 17+), Swift 5.9+, `.sensoryFeedback()` for haptics, XcodeGen for project regeneration.

**Spec:** `docs/superpowers/specs/2026-03-19-quiet-gravity-design.md`

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `ios/Folio/Presentation/Components/Motion.swift` | Animation constants + Reduce Motion helper |
| `ios/Folio/Presentation/Components/ScaleButtonStyle.swift` | Press-to-shrink button style |
| `ios/Folio/Presentation/Components/ShimmerView.swift` | Skeleton placeholder for loading cards |
| `ios/Folio/Presentation/Components/ProcessingProgressBar.swift` | Thin animated progress line for processing articles |
| `ios/Folio/Presentation/Components/ReadingProgressBar.swift` | Reading progress line for ReaderView |

### Modified Files

| File | Changes |
|------|---------|
| `ios/Folio/Presentation/Components/ToastView.swift` | Bottom position, material background, new animation |
| `ios/Folio/Presentation/Home/ArticleCardView.swift` | Font weight read/unread, color hierarchy, unread glow, skeleton, progress bar |
| `ios/Folio/Presentation/Home/HomeArticleRow.swift` | Haptics, deletion transition |
| `ios/Folio/Presentation/Home/HomeView.swift` | Search transition animation, haptics on save/delete/refresh |
| `ios/Folio/Presentation/Home/HomeSearchResultsView.swift` | Ink appearance, settle animations |
| `ios/Folio/Presentation/Home/UnifiedInputBar.swift` | ScaleButtonStyle on send button |
| `ios/Folio/Presentation/Home/EmptyStateView.swift` | Settle animation, clipboard button ink + haptic |
| `ios/Folio/Presentation/Reader/ReaderView.swift` | Ink entrance sequence, spacing adjustments, progress bar |
| `ios/Folio/Presentation/Settings/SettingsView.swift` | Logout haptic, numericText transition |
| `ios/ShareExtension/CompactShareView.swift` | Success haptic (if file exists) |

> **Note:** `ReaderViewModel.swift` already has `readingProgress` tracking — verified, no changes needed.
> **Note:** `Haptics.swift` intentionally not created — all haptics use inline `.sensoryFeedback()` per spec revision.

---

## Task 1: Motion Constants & ScaleButtonStyle

**Files:**
- Create: `ios/Folio/Presentation/Components/Motion.swift`
- Create: `ios/Folio/Presentation/Components/ScaleButtonStyle.swift`

- [ ] **Step 1: Create Motion.swift**

```swift
// ios/Folio/Presentation/Components/Motion.swift
import SwiftUI

enum Motion {
    /// Settle: elements land with weight, near-zero bounce
    static let settle = Animation.spring(duration: 0.4, bounce: 0.05)

    /// Quick: immediate button/state feedback
    static let quick = Animation.spring(duration: 0.25, bounce: 0.0)

    /// Ink: content appears as if printed — fast easeOut
    static let ink = Animation.easeOut(duration: 0.15)

    /// Exit: elements leave quietly
    static let exit = Animation.easeIn(duration: 0.2)

    /// Slow: progress bars, processing state
    static let slow = Animation.linear(duration: 2.0)

    /// Returns nil (instant) when Reduce Motion is enabled; otherwise the given animation.
    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? .none : animation
    }
}
```

- [ ] **Step 2: Create ScaleButtonStyle.swift**

```swift
// ios/Folio/Presentation/Components/ScaleButtonStyle.swift
import SwiftUI

/// Button style that scales down on press (0.85) and settles back on release.
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .animation(configuration.isPressed ? Motion.quick : Motion.settle, value: configuration.isPressed)
    }
}
```

- [ ] **Step 3: Regenerate Xcode project and build**

Run: `cd ios && xcodegen generate && cd .. && xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -3`

Expected: Build Succeeded (ignore version warning)

- [ ] **Step 4: Commit**

```
git add ios/Folio/Presentation/Components/Motion.swift ios/Folio/Presentation/Components/ScaleButtonStyle.swift ios/Folio.xcodeproj
git commit -m "feat(ios): add Motion animation constants and ScaleButtonStyle"
```

---

## Task 2: ShimmerView & ProcessingProgressBar

**Files:**
- Create: `ios/Folio/Presentation/Components/ShimmerView.swift`
- Create: `ios/Folio/Presentation/Components/ProcessingProgressBar.swift`

- [ ] **Step 1: Create ShimmerView.swift**

Skeleton placeholder with slow-breathing opacity (0.4 ↔ 0.7, 2s cycle). Not a shimmer gradient — a quiet, still breathing.

```swift
// ios/Folio/Presentation/Components/ShimmerView.swift
import SwiftUI

/// Skeleton placeholder for article cards while content is loading.
/// Displays static gray blocks with a slow breathing opacity animation.
struct ShimmerView: View {
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            VStack(alignment: .leading, spacing: Spacing.xs) {
                // Title placeholder — 70% of card width
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.folio.separator)
                    .frame(width: w * 0.7, height: 14)

                // Summary placeholder — 90% of card width
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.folio.separator)
                    .frame(width: w * 0.9, height: 12)

                // Meta placeholder — 40% of card width
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.folio.separator)
                    .frame(width: w * 0.4, height: 10)
            }
        }
        .frame(height: 50) // approximate height of title+summary+meta
        .opacity(isAnimating ? 0.7 : 0.4)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
            value: isAnimating
        )
        .onAppear { isAnimating = true }
        .padding(.vertical, Spacing.sm)
    }
}
```

- [ ] **Step 2: Create ProcessingProgressBar.swift**

Thin line that sweeps left-to-right in 3s cycles. Used at the bottom of article cards during processing.

```swift
// ios/Folio/Presentation/Components/ProcessingProgressBar.swift
import SwiftUI

/// A thin animated progress line shown at the bottom of processing article cards.
struct ProcessingProgressBar: View {
    var color: Color = Color.folio.accent.opacity(0.4)
    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 0.75)
                .fill(color)
                .frame(width: geometry.size.width * progress, height: 1.5)
        }
        .frame(height: 1.5)
        .onAppear {
            if reduceMotion {
                progress = 1.0
            } else {
                withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                    progress = 1.0
                }
            }
        }
    }
}
```

- [ ] **Step 3: Regenerate Xcode project and build**

Run: `cd ios && xcodegen generate && cd .. && xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -3`

- [ ] **Step 4: Commit**

```
git add ios/Folio/Presentation/Components/ShimmerView.swift ios/Folio/Presentation/Components/ProcessingProgressBar.swift
git commit -m "feat(ios): add ShimmerView skeleton and ProcessingProgressBar components"
```

---

## Task 3: Toast Redesign

**Files:**
- Modify: `ios/Folio/Presentation/Components/ToastView.swift` (full rewrite)
- Modify: `ios/Folio/Presentation/Home/HomeView.swift:91` (toast modifier position)

- [ ] **Step 1: Read current ToastView.swift**

Read the file to confirm current structure before rewriting.

- [ ] **Step 2: Rewrite ToastView.swift**

Changes: bottom position, `.ultraThinMaterial` background, `Typography.body` font, `Motion.settle` entrance from bottom, 2.5s duration.

```swift
// ios/Folio/Presentation/Components/ToastView.swift
import SwiftUI

struct ToastView: View {
    let message: String
    var icon: String?

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(Color.folio.textPrimary)
            }
            Text(message)
                .font(Typography.body)
                .foregroundStyle(Color.folio.textPrimary)
                .lineLimit(2)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    }
}

struct ToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    var icon: String?
    var duration: TimeInterval = 2.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isPresented {
                    ToastView(message: message, icon: icon)
                        .padding(.horizontal, Spacing.md)
                        .padding(.bottom, Spacing.xs)
                        .transition(
                            .asymmetric(
                                insertion: .opacity
                                    .combined(with: .offset(y: 8))
                                    .combined(with: .scale(scale: 0.96)),
                                removal: .opacity
                                    .combined(with: .offset(y: 4))
                            )
                        )
                        .onTapGesture { dismiss() }
                        .task {
                            try? await Task.sleep(for: .seconds(duration))
                            dismiss()
                        }
                }
            }
            .animation(
                isPresented
                    ? Motion.resolved(Motion.settle, reduceMotion: reduceMotion) ?? .default
                    : Motion.resolved(Motion.exit, reduceMotion: reduceMotion) ?? .default,
                value: isPresented
            )
    }

    private func dismiss() {
        guard isPresented else { return }
        isPresented = false
    }
}

extension View {
    func toast(isPresented: Binding<Bool>, message: String, icon: String? = nil, duration: TimeInterval = 2.5) -> some View {
        modifier(ToastModifier(isPresented: isPresented, message: message, icon: icon, duration: duration))
    }
}
```

- [ ] **Step 3: Update HomeView toast position**

The toast modifier now renders at `.bottom` via overlay. The `.toast()` call in `HomeView.swift:91` needs to be moved **above** the `.safeAreaInset(edge: .bottom)` so the toast appears above the input bar. Check if the current position is correct — if `.toast()` is called after `.safeAreaInset()`, the overlay will be inside the safe area inset, which is correct (above the input bar).

Verify by reading `HomeView.swift` and confirming the modifier order. If toast is after safeAreaInset, it's already correct. If not, move it.

- [ ] **Step 4: Build and verify**

Run: `xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -3`

- [ ] **Step 5: Commit**

```
git add ios/Folio/Presentation/Components/ToastView.swift ios/Folio/Presentation/Home/HomeView.swift
git commit -m "feat(ios): redesign Toast to bottom position with material background"
```

---

## Task 4: ArticleCardView Visual Hierarchy

**Files:**
- Modify: `ios/Folio/Presentation/Home/ArticleCardView.swift`

This is the most impactful visual change — three-tier information hierarchy with font weight distinguishing read/unread.

- [ ] **Step 1: Read current ArticleCardView.swift**

Confirm current line numbers for body, title Text, summary Text, sourceLine, statusIcon, and unread dot.

- [ ] **Step 2: Update title font weight for read/unread distinction**

In the body (around line 29-32), change the title `Text`:

```swift
// Before (line 29-32):
Text(article.displayTitle)
    .font(Typography.listTitle)
    .foregroundStyle(isFailed ? Color.folio.textSecondary : Color.folio.textPrimary)
    .lineLimit(2)

// After:
Text(article.displayTitle)
    .font(Typography.listTitle)
    .fontWeight(isUnread ? .semibold : .regular)
    .foregroundStyle(isFailed ? Color.folio.textSecondary : (isUnread ? Color.folio.textPrimary : Color.folio.textSecondary))
    .lineLimit(2)
```

- [ ] **Step 3: Lower summary color to textTertiary**

In the summary section (around line 35-41):

```swift
// Before:
.foregroundStyle(Color.folio.textSecondary)

// After:
.foregroundStyle(Color.folio.textTertiary)
```

- [ ] **Step 4: Lower meta info line color**

In the sourceLine section, change the text colors for source name, category, and time from `Color.folio.textTertiary` to `Color.folio.textTertiary.opacity(0.8)`.

- [ ] **Step 5: Add glow to unread dot**

At the unread Circle (around line 19-25):

```swift
// Before:
Circle()
    .fill(Color.folio.unread)
    .frame(width: 8, height: 8)
    .padding(.top, 6)
    .accessibilityLabel(Text(String(localized: "status.unread", defaultValue: "Unread")))

// After:
Circle()
    .fill(Color.folio.unread)
    .frame(width: 8, height: 8)
    .shadow(color: Color.folio.unread.opacity(0.3), radius: 2, x: 0, y: 0)
    .padding(.top, 6)
    .accessibilityLabel(Text(String(localized: "status.unread", defaultValue: "Unread")))
```

- [ ] **Step 6: Replace processing status icon with ProcessingProgressBar**

In the statusIcon (around line 144-171), replace the `.processing` case and add `.clientReady` progress bar. Also add the progress bar to the bottom of the card body.

In the card body VStack (after sourceLine, around line 44-46), add:

```swift
// After sourceLine
if article.status == .processing {
    ProcessingProgressBar()
        .padding(.top, Spacing.xxs)
} else if article.status == .clientReady {
    ProcessingProgressBar(color: Color.folio.success.opacity(0.3))
        .padding(.top, Spacing.xxs)
}
```

In statusIcon `@ViewBuilder`, update the `.processing` case to `EmptyView()` (progress bar replaces the icon):

```swift
case .processing:
    EmptyView()  // replaced by ProcessingProgressBar in card body
```

Keep `.clientReady`, `.failed`, and `.pending` cases unchanged.

- [ ] **Step 7: Integrate ShimmerView for pending articles without content**

In the card body, add a conditional at the top of the outer HStack. When the article has no title and no content yet, show the skeleton instead of the normal layout:

```swift
var body: some View {
    if article.status == .pending && article.title == nil && article.markdownContent == nil && article.sourceType != .manual {
        ShimmerView()
    } else {
        HStack(alignment: .top, spacing: Spacing.xs) {
            // ... existing card layout ...
        }
        .padding(.vertical, Spacing.sm)
    }
}
```

- [ ] **Step 8: Build and verify**

Run: `xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -3`

- [ ] **Step 9: Commit**

```
git add ios/Folio/Presentation/Home/ArticleCardView.swift
git commit -m "feat(ios): rework ArticleCardView — visual hierarchy, skeleton, progress bar"
```

---

## Task 5: HomeArticleRow Haptics

**Files:**
- Modify: `ios/Folio/Presentation/Home/HomeArticleRow.swift`

- [ ] **Step 1: Read current HomeArticleRow.swift**

Confirm line numbers for body, swipe actions, contextMenuContent.

- [ ] **Step 2: Add haptics and deletion transition**

Add `.sensoryFeedback()` modifier for favorite toggle (`.selection` per spec, not `.impact`):

```swift
// At the end of body, after .contextMenu:
.sensoryFeedback(.selection, trigger: article.isFavorite)
```

Note: SwiftUI's `.sensoryFeedback` triggers when the observed value changes. Delete haptic is handled at the HomeView level (in handleArticleAction).

Add deletion transition to the NavigationLink:

```swift
// On the NavigationLink (or the outermost view in body):
.transition(.asymmetric(
    insertion: .identity,
    removal: .opacity.combined(with: .move(edge: .trailing))
))
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -3`

- [ ] **Step 4: Commit**

```
git add ios/Folio/Presentation/Home/HomeArticleRow.swift
git commit -m "feat(ios): add haptic feedback to article row interactions"
```

---

## Task 6: HomeView Haptics & Search Transition

**Files:**
- Modify: `ios/Folio/Presentation/Home/HomeView.swift`

- [ ] **Step 1: Read current HomeView.swift**

Confirm line numbers for: body Group (conditional rendering), saveURL, saveManualContent, handleArticleAction, showToast, the onChange(of: searchText) handler.

- [ ] **Step 2: Add search ↔ list transition animation**

In the body Group (around line 25-36), add `.transition(.opacity)` to **all three** branches:

```swift
Group {
    if isSearching, let svm = searchViewModel {
        HomeSearchResultsView(searchViewModel: svm, searchText: $searchText)
            .transition(.opacity)
    } else if viewModel?.articles.isEmpty ?? true {
        EmptyStateView(onPasteURL: { url in
            saveURL(url.absoluteString)
        })
        .transition(.opacity)
    } else {
        articleList
            .transition(.opacity)
    }
}
```

All three branches need the transition so the cross-fade works bidirectionally.
```

And in the `onChange(of: searchText)` handler, wrap the state change:

```swift
.onChange(of: searchText) { _, newValue in
    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
    withAnimation(Motion.quick) {
        isSearching = !trimmed.isEmpty
    }
    if trimmed.isEmpty {
        viewModel?.fetchArticles()
    } else {
        searchViewModel?.searchText = trimmed
    }
}
```

- [ ] **Step 3: Add haptics to save actions**

In `saveURL` method, after successful save (around the `showToast` call), add:
No explicit haptic call needed here — the toast modifier doesn't trigger haptic (per spec). But the `.sensoryFeedback(.success)` should fire on successful save. Add a trigger state:

Add a `@State private var saveSucceeded = false` and a `@State private var saveFailed = false` to the state declarations, then add to the body:

```swift
.sensoryFeedback(.success, trigger: saveSucceeded)
.sensoryFeedback(.error, trigger: saveFailed)
```

Then in `saveURL`, after successful save: `saveSucceeded.toggle()`
In the catch blocks: `saveFailed.toggle()`
Same pattern for `saveManualContent`.

- [ ] **Step 4: Add haptic to delete confirmation**

In `handleArticleAction`, the `.delete` case sets `showDeleteConfirmation = true`. Add a haptic trigger:

Add `@State private var deleteConfirmTrigger = false` and:

```swift
.sensoryFeedback(.impact(.medium), trigger: deleteConfirmTrigger)
```

In handleArticleAction `.delete` case: `deleteConfirmTrigger.toggle()`

- [ ] **Step 5: Add haptic to copy link**

In `handleArticleAction`, the `.copyLink` case copies to clipboard. Add:

```swift
case .copyLink(let urlString):
    UIPasteboard.general.string = urlString
    saveSucceeded.toggle()  // reuse success trigger for copy feedback
    showToast(...)
```

- [ ] **Step 5b: Add pull-to-refresh haptic**

In `articleList`, on the `.refreshable` modifier, the haptic fires when refresh starts. Add a trigger state:

Add `@State private var refreshTrigger = false` and:

```swift
.sensoryFeedback(.impact(.light), trigger: refreshTrigger)
```

In the `.refreshable` closure, add `refreshTrigger.toggle()` at the start.

- [ ] **Step 6: Build and verify**

Run: `xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -3`

- [ ] **Step 7: Commit**

```
git add ios/Folio/Presentation/Home/HomeView.swift
git commit -m "feat(ios): add search transition animation and haptic feedback to HomeView"
```

---

## Task 7: EmptyStateView & SearchResultsView Animations

**Files:**
- Modify: `ios/Folio/Presentation/Home/EmptyStateView.swift`
- Modify: `ios/Folio/Presentation/Home/HomeSearchResultsView.swift`

- [ ] **Step 1: Read current EmptyStateView.swift**

Confirm current animation implementation (should have offset + opacity on appear).

- [ ] **Step 2: Update EmptyStateView to use Motion constants**

Replace the current animation with Motion.settle:

```swift
// Find the existing animation (likely .easeOut(duration: 0.3))
// Replace with:
.animation(Motion.resolved(Motion.settle, reduceMotion: reduceMotion) ?? .default, value: appeared)
```

Add `@Environment(\.accessibilityReduceMotion) private var reduceMotion` to the view.

Ensure the initial offset is `12pt` (spec says 12, current might be 8 — increase if needed).

Also add ink animation and haptic to the clipboard paste button:
- The "Paste link" button should appear with `Motion.ink` transition
- Add `.sensoryFeedback(.selection, trigger: clipboardHasURL)` where `clipboardHasURL` is the state that triggers the button appearance

- [ ] **Step 3: Update HomeSearchResultsView animations**

Read current file, then:

a) Add `@Environment(\.accessibilityReduceMotion) private var reduceMotion` to the view.

b) In `emptyState` — update the AI answer expansion:

```swift
// Find: withAnimation { showAIAnswer = true }
// Replace with:
withAnimation(Motion.settle) { showAIAnswer = true }
```

c) The `emptyState` itself should have a settle entrance. Add state tracking:

```swift
@State private var appeared = false

// In emptyState body, wrap the VStack:
.opacity(appeared ? 1 : 0)
.offset(y: appeared ? 0 : 12)
.onAppear {
    withAnimation(Motion.resolved(Motion.settle, reduceMotion: reduceMotion) ?? .default) {
        appeared = true
    }
}
```

- [ ] **Step 4: Build and verify**

Run: `xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -3`

- [ ] **Step 5: Commit**

```
git add ios/Folio/Presentation/Home/EmptyStateView.swift ios/Folio/Presentation/Home/HomeSearchResultsView.swift
git commit -m "feat(ios): apply Motion.settle animations to empty and search states"
```

---

## Task 8: UnifiedInputBar ScaleButtonStyle

**Files:**
- Modify: `ios/Folio/Presentation/Home/UnifiedInputBar.swift`

- [ ] **Step 1: Read current UnifiedInputBar.swift**

Confirm send button location (around line 22-30).

- [ ] **Step 2: Apply ScaleButtonStyle to send button**

```swift
// Find the Button(action: send) block
// Add after .accessibilityLabel:
.buttonStyle(ScaleButtonStyle())
```

Also update the send button transition to use Motion.settle:

```swift
// Find: .transition(.scale.combined(with: .opacity))
// Keep as is — the transition type is correct
// Find: .animation(.easeInOut(duration: 0.15), value: text.isEmpty)
// Replace with:
.animation(Motion.settle, value: text.isEmpty)
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -3`

- [ ] **Step 4: Commit**

```
git add ios/Folio/Presentation/Home/UnifiedInputBar.swift
git commit -m "feat(ios): apply ScaleButtonStyle and Motion.settle to input bar send button"
```

---

## Task 9: ReadingProgressBar & ReaderView Spacing

**Files:**
- Create: `ios/Folio/Presentation/Components/ReadingProgressBar.swift`
- Modify: `ios/Folio/Presentation/Reader/ReaderView.swift`

- [ ] **Step 1: Create ReadingProgressBar.swift**

```swift
// ios/Folio/Presentation/Components/ReadingProgressBar.swift
import SwiftUI

/// A thin progress line shown below the navigation bar in the reader.
struct ReadingProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.folio.accent.opacity(progress >= 1.0 ? 0.5 : 0.3))
                .frame(width: geometry.size.width * min(max(progress, 0), 1.0))
                .animation(Motion.quick, value: progress)
        }
        .frame(height: 1.5)
    }
}
```

- [ ] **Step 2: Regenerate Xcode project**

Run: `cd ios && xcodegen generate`

- [ ] **Step 3: Read current ReaderView.swift**

Confirm line numbers for: title section (around line 100-106), meta info padding (around line 108-114), content area, summary expand animation.

- [ ] **Step 4: Add ReadingProgressBar to ReaderView**

Add the progress bar at the top of the reader content, below the navigation bar. In the `readerContent` method, add as the first element inside the ScrollView's VStack:

```swift
// At top of the VStack inside ScrollView, before the title:
ReadingProgressBar(progress: viewModel.readingProgress)
```

Or alternatively, as a `.safeAreaInset(edge: .top)` or `.overlay(alignment: .top)` on the ScrollView, so it doesn't scroll with content. Overlay is better:

```swift
// On the ScrollView, add:
.overlay(alignment: .top) {
    ReadingProgressBar(progress: viewModel.readingProgress)
}
```

- [ ] **Step 5: Adjust ReaderView spacing for breathing room**

In the `readerContent` method:

a) Title-to-meta spacing: find the padding after title (around line 108-114, likely `.padding(.top, Spacing.xs)`), change to `.padding(.top, Spacing.lg)` (24pt).

b) Meta-to-divider spacing: find the divider section (around line 123-124), ensure there's `Spacing.xl` (32pt) of total padding between meta info bottom and the divider, with `Spacing.md` (16pt) above and below the divider.

c) Bottom padding: the current VStack has `Spacer(minLength: Spacing.xl)` (32pt) at the bottom. Replace it with `.padding(.bottom, 80)` on the VStack itself for more generous breathing room.

- [ ] **Step 6: Build and verify**

Run: `xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -3`

- [ ] **Step 7: Commit**

```
git add ios/Folio/Presentation/Components/ReadingProgressBar.swift ios/Folio/Presentation/Reader/ReaderView.swift
git commit -m "feat(ios): add reading progress bar and improve reader spacing"
```

---

## Task 10: ReaderView Ink Entrance Sequence

**Files:**
- Modify: `ios/Folio/Presentation/Reader/ReaderView.swift`

- [ ] **Step 1: Read current ReaderView.swift readerContent method**

Confirm the three sections: title, meta info, content body.

- [ ] **Step 2: Add ink entrance state variables**

In `ReaderView`, add state for the three-stage ink effect:

```swift
@State private var titleVisible = false
@State private var metaVisible = false
@State private var contentVisible = false
@Environment(\.accessibilityReduceMotion) private var reduceMotion
```

- [ ] **Step 3: Apply opacity to each section**

In `readerContent`, wrap each section with opacity:

a) Title block: `.opacity(titleVisible ? 1 : 0)`
b) Meta info block: `.opacity(metaVisible ? 1 : 0)`
c) Content body (everything after divider): `.opacity(contentVisible ? 1 : 0)`

- [ ] **Step 4: Add the ink sequence trigger**

Add a `.task` modifier to the `readerContent` view (or the outermost container) that fires the sequence:

```swift
.task {
    if reduceMotion {
        titleVisible = true
        metaVisible = true
        contentVisible = true
        return
    }
    // Title inks at 150ms
    try? await Task.sleep(for: .milliseconds(150))
    withAnimation(Motion.ink) { titleVisible = true }
    // Meta inks at 250ms
    try? await Task.sleep(for: .milliseconds(100))
    withAnimation(Motion.ink) { metaVisible = true }
    // Content inks at 350ms
    try? await Task.sleep(for: .milliseconds(100))
    withAnimation(Motion.ink) { contentVisible = true }
}
```

- [ ] **Step 5: Update AI summary expand/collapse animation**

Find the summary expand animation (around line 191-220 in `aiSummarySection`):

```swift
// Find the withAnimation for summaryExpanded toggle
// Replace with:
withAnimation(Motion.settle) { summaryExpanded.toggle() }
```

For the chevron rotation:

```swift
// Find the chevron image
// Add: .rotationEffect(.degrees(summaryExpanded ? 180 : 0))
// With: .animation(Motion.quick, value: summaryExpanded)
```

- [ ] **Step 6: Build and verify**

Run: `xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -3`

- [ ] **Step 7: Commit**

```
git add ios/Folio/Presentation/Reader/ReaderView.swift
git commit -m "feat(ios): add ink entrance sequence and settle animation to reader"
```

---

## Task 11: SettingsView & Share Extension Haptics

**Files:**
- Modify: `ios/Folio/Presentation/Settings/SettingsView.swift`
- Modify: `ios/ShareExtension/ShareViewController.swift` (or `CompactShareView.swift` — check which file handles share success)

- [ ] **Step 1: Read SettingsView.swift**

Find the logout button and the monthly usage display.

- [ ] **Step 2: Add logout haptic**

On the logout button action, add a haptic trigger:

```swift
.sensoryFeedback(.impact(.medium), trigger: logoutTrigger)
```

Add `@State private var logoutTrigger = false` and toggle it when logout is confirmed.

- [ ] **Step 3: Add numericText transition to usage count**

Find the monthly usage count display (e.g., "12 / 30") and add:

```swift
Text("\(currentCount)")
    .contentTransition(.numericText)
```

- [ ] **Step 4: Add Share Extension success haptic**

Read the Share Extension view file(s) in `ios/ShareExtension/`. Find where the success state is displayed. Add:

```swift
.sensoryFeedback(.success, trigger: saveCompleted)
```

Where `saveCompleted` is a Bool that becomes true when the article is saved.

Note: Share Extension has 120MB memory limit — `.sensoryFeedback()` is lightweight and safe.

- [ ] **Step 5: Build and verify**

Run: `xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -3`

- [ ] **Step 6: Commit**

```
git add ios/Folio/Presentation/Settings/SettingsView.swift ios/ShareExtension/
git commit -m "feat(ios): add haptics to Settings logout and Share Extension success"
```

---

## Task 12: Final Xcodegen, Build, & Verification

**Files:**
- No code changes — verification only

- [ ] **Step 1: Regenerate Xcode project**

Run: `cd ios && xcodegen generate`

This ensures all new files (Motion.swift, ScaleButtonStyle.swift, ShimmerView.swift, ProcessingProgressBar.swift, ReadingProgressBar.swift) are properly included.

- [ ] **Step 2: Full build**

Run: `xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -5`

Expected: Build Succeeded

- [ ] **Step 3: Run existing tests**

Run: `xcodebuild test -project ios/Folio.xcodeproj -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -10`

Expected: All tests pass (these are model/logic tests; UI changes shouldn't break them)

- [ ] **Step 4: Verify file list matches spec**

Confirm all 5 new files exist:
- `ios/Folio/Presentation/Components/Motion.swift`
- `ios/Folio/Presentation/Components/ScaleButtonStyle.swift`
- `ios/Folio/Presentation/Components/ShimmerView.swift`
- `ios/Folio/Presentation/Components/ProcessingProgressBar.swift`
- `ios/Folio/Presentation/Components/ReadingProgressBar.swift`

Confirm all 8 modified files have changes:
- `ToastView.swift` — bottom + material
- `ArticleCardView.swift` — visual hierarchy
- `HomeArticleRow.swift` — haptics
- `HomeView.swift` — search transition + haptics
- `HomeSearchResultsView.swift` — settle/ink
- `UnifiedInputBar.swift` — ScaleButtonStyle
- `EmptyStateView.swift` — Motion.settle
- `ReaderView.swift` — ink sequence + spacing + progress bar

- [ ] **Step 5: Final commit if any xcodegen changes**

```
git add ios/Folio.xcodeproj
git commit -m "chore(ios): regenerate Xcode project with new components"
```

---

## Verification Checklist (from spec section 14)

After all tasks complete, verify against spec acceptance criteria:

### Haptics
- [ ] Save URL/content → `.success` haptic
- [ ] Toggle favorite → `.selection` haptic (via isFavorite trigger)
- [ ] Delete confirmation → `.impact(.medium)` haptic
- [ ] Operation failure → `.error` haptic
- [ ] Pull-to-refresh → `.impact(.light)` haptic
- [ ] Copy link → `.success` haptic
- [ ] Settings logout → `.impact(.medium)` haptic
- [ ] Share Extension save → `.success` haptic
- [ ] Silent scenes (scroll, navigation, toast appear) → no haptic

### Animations
- [ ] Processing article → bottom progress line sweeps
- [ ] processing → ready → progress completes + new content inks in
- [ ] Reader entry → title/meta/content ink sequence (350ms total)
- [ ] Toast → bottom float-up with material background
- [ ] Search results → opacity ink appearance
- [ ] Empty state → settle (offset + opacity)
- [ ] Send button → scale 0.85 on press

### Visual
- [ ] Unread title = semibold, read title = regular
- [ ] Unread dot has subtle glow
- [ ] Summary text noticeably lighter than title
- [ ] Meta info line is the quietest layer
- [ ] Reader has generous spacing between title/meta/content
- [ ] Reading progress bar visible at top of reader

### Accessibility
- [ ] All animations respect Reduce Motion setting
- [ ] Dynamic Type still works correctly
- [ ] VoiceOver labels unchanged
