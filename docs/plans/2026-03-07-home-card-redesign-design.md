# Home Card Redesign Design

Date: 2026-03-07
Status: Approved

## Design Philosophy

Inspired by Steve Jobs' design principles, reviewed by Apple senior UI designer perspective.

Core belief: **Consistency is quality.** One card type, done perfectly. Every element must earn its place.

The home feed should make users feel **anticipation** — "What interesting things have accumulated for me today?" — not obligation.

## Decision Log

| Decision | Chosen | Rejected | Reason |
|----------|--------|----------|--------|
| Overall approach | B: Breathing list | A: Magazine rhythm, C: AI-aware cards | Consistency > variety. One perfect card > two mediocre card types |
| Hero cards | Deferred | Ship now | `coverImageURL` is nil for most articles. Add when data is ready |
| Tags on card | No | Yes | Tags are retrieval, not scanning. Show in detail/reader view |
| Source color coding | No | Yes | Christmas tree effect. Use favicon instead |
| Source+time position | Bottom | Top | Title is the anchor that stops scrolling. Source is subordinate |
| Persistent heart icon | No | Yes | No Apple first-party app does this. Show only when favorited |
| Separators | Hairline within section | Large whitespace | Apple News uses whitespace, but within date sections hairlines group items cleanly |
| Status indicators | Quiet trailing icons | Remove all / Prominent badges | Users need processing/failed feedback, but it shouldn't dominate |
| Reading progress | Unread dot (Mail convention) | No indicator / Progress bar | 8pt blue dot is universally understood on iOS |
| Category on card | Plain text in source line | Colored pill / Hidden | Zero visual cost, adds scanability |
| Typography | System TextStyles | Custom tracking/sizing | Dynamic Type scales correctly. Don't fight the system |
| Text colors | Semantic tokens | Opacity on primary | Opacity breaks WCAG AA in light mode and is unpredictable in dark mode |
| DailyDigest/Insight cards | Delete | Keep with tint | Features were cut in redesign plan. Don't carry forward mock placeholders |

## Card Spec: Standard Article Card

### Layout

```
[*unread]  Title (max 2 lines)
           Summary (max 2 lines)
           [favicon 20px]  Source . Category . 5h ago    [status icon]  [heart if fav]
```

- Unread dot only shown when `readProgress == 0` and `status == .ready`
- Summary only shown when `article.displaySummary` is non-nil and non-empty
- Category only shown when `article.category` is non-nil
- Status icon only shown for non-ready states
- Heart only shown when `isFavorite == true`

### Typography

| Element | Font | Color |
|---------|------|-------|
| Title | `Typography.listTitle` — `.headline`, semibold (~17pt, scales) | `Color.folio.textPrimary` |
| Summary | `Typography.body` — `.subheadline`, regular (~15pt, scales) | `Color.folio.textSecondary` |
| Source line | `Typography.caption` — `.footnote`, regular (~13pt, scales) | `Color.folio.textTertiary` |
| Source name | `Typography.tag` — `.footnote`, medium (~13pt, scales) | `Color.folio.textTertiary` |

No custom `.tracking()`. Trust the system's optical compensation.

### Spacing

| Gap | Value | Token |
|-----|-------|-------|
| Card padding horizontal | 16pt | `Spacing.md` |
| Card padding vertical | 12pt | `Spacing.sm` |
| Unread dot to title | 8pt | `Spacing.xs` |
| Title to summary | 4pt | `Spacing.xxs` |
| Summary to source line | 8pt | `Spacing.xs` |
| Between cards (same section) | 0.5pt hairline separator, inset 16pt from leading | `Color.folio.separator` |
| Between date sections | 24pt gap | `Spacing.lg` |

### Unread Indicator

- 8pt filled circle, `Color.folio.unread` (blue accent)
- Positioned at leading edge of title, vertically centered to first line
- Shown only when `readProgress == 0` and `status == .ready`
- Disappears once user opens the article

### Favicon

- Size: 20x20pt, corner radius 4pt (`CornerRadius.small`)
- Fallback chain:
  1. `faviconURL` non-nil and loads -> show favicon image
  2. Otherwise -> SF Symbol from `sourceType.iconName` at 13pt in `textTertiary`
- Use Nuke `LazyImage` with 0.2s fade transition
- No first-letter circles (looks like contacts, misleading)

### Status Indicators (trailing edge of source line)

| State | SF Symbol | Size | Color | Animation |
|-------|-----------|------|-------|-----------|
| `processing` | `circle.dashed` | 12pt | `Color.folio.warning` | `.symbolEffect(.variableColor.iterative)` |
| `clientReady` | `doc.richtext` | 12pt | `Color.folio.success` | none |
| `failed` | `exclamationmark.triangle.fill` | 12pt | `Color.folio.error` | none |
| `pendingUpload` | `arrow.up.icloud` | 12pt | `Color.folio.textTertiary` | none |

For failed articles: title dimmed to `textSecondary`, "Retry" added as first context menu item.

### Favorite Indicator

- Shown only when `isFavorite == true`
- `heart.fill`, 12pt, `.pink`, appended after time in source line
- When `isFavorite == false`: nothing shown (swipe + context menu handle toggling)

### Swipe Actions (unchanged)

- Leading (full swipe): Toggle favorite
- Trailing: Delete (destructive, with confirmation)

### Context Menu (one addition)

1. **Retry** (only for failed articles) -- NEW, top position
2. Favorite / Unfavorite
3. Archive / Unarchive
4. Share
5. Copy Link
6. Separator
7. Delete

## Deletions

- `DailyDigestCard.swift` -- feature cut, remove from feed
- `InsightCard.swift` -- feature cut, remove from feed
- Left-side `StatusBadge` dots -- replaced by unread dot + trailing status icons

## Loading States

- **Initial load**: 5 placeholder rows using `.redacted(reason: .placeholder)` on template card
- **Pull-to-refresh**: existing `.refreshable {}`, keep as-is
- **Pagination**: centered `ProgressView()` as last row while loading more
- **End of list**: show nothing (Apple convention)

## Accessibility

- All text uses Dynamic Type `TextStyle` values (no fixed sizes)
- Unread dot: `.accessibilityLabel("Unread")`
- Status icons: accessibility labels per state
- Favorite heart: `.accessibilityLabel("Favorited")`
- Minimum tap target: entire row is NavigationLink (no small inline buttons)
- Bold Text setting: handled by system fonts automatically

## Dark Mode

Use semantic color tokens exclusively. No `.opacity()` on text colors. All color assets already define light/dark pairs with appropriate contrast ratios.

## Files to Modify

1. `ios/Folio/Presentation/Home/ArticleCardView.swift` -- rewrite to new spec
2. `ios/Folio/Presentation/Home/HomeView.swift` -- remove DailyDigest/Insight, simplify article row
3. `ios/Folio/Presentation/Components/StatusBadge.swift` -- simplify to inline trailing icon
4. Delete `ios/Folio/Presentation/Home/DailyDigestCard.swift`
5. Delete `ios/Folio/Presentation/Home/InsightCard.swift`
6. Run `cd ios && xcodegen generate` after file changes

## Future: Hero Cards

When `coverImageURL` is reliably populated for a meaningful percentage of articles:

- Full-width cover image, 16:9 aspect ratio, max 200pt, corner radius 12pt
- Title below image, no summary (image provides visual anchor)
- Data-driven: only when image exists and loads successfully
- Never two hero cards consecutively
- Placeholder: `Color.folio.separator` rectangle with shimmer, fallback to standard card on failure
