# Readability Integration Design

## Problem

Local Reader (`@vakra-dev/reader`) uses hand-written heuristics (`findMainContent` + content scoring + site adapters) to extract main content from web pages. This approach fails on JS-heavy SPAs and non-standard page structures (e.g., Twitter Articles). Maintaining per-site adapters doesn't scale.

## Solution

Replace the custom content extraction with Mozilla's `@mozilla/readability` — the same algorithm behind Firefox Reader Mode, battle-tested across millions of web pages.

## Scope

All changes are in the reader library (`/Users/mac/github/reader`). Zero changes to folio's reader-service or server code.

## Data Flow

```
Engine HTML
  |-> extractMetadata(raw HTML)          -> websiteMetadata
  |-> cleanContent(basic cleaning)       -> cleanedHtml
  |     Kept: Layer 0/1/2/6 (script/style/ads/lazy-img/base64/url)
  |     Removed: findMainContent, content scoring, navigation removal, site adapter hooks
  |-> Readability.parse(cleanedHtml)     -> article
       | article.content (clean HTML)
       | article.title (fallback title)
       | article.excerpt (fallback description)
           |
     excludeTags/includeTags filter (if provided)
           |
     htmlToMarkdown -> final markdown
```

Readability returns null -> fall back to cleaned HTML directly (same as current behavior without findMainContent).

## Changes

### 1. New dependency
- `npm install @mozilla/readability` in reader's package.json

### 2. Delete `src/site-adapters/` directory
- twitter.ts, wechat.ts, weibo.ts, index.ts, types.ts, index.test.ts

### 3. `src/index.ts`
- Remove `getAdapter` / `SiteAdapter` exports

### 4. `src/utils/content-cleaner.ts`
- Remove: `findMainContent`, `getContentScore`, `getLinkDensity`, `looksLikeNavigation`, `removeWithProtection`, `NAVIGATION_SELECTORS`, `FORCE_INCLUDE_SELECTORS`
- Remove from `CleaningOptions`: `siteAdapter`
- Keep: `onlyMainContent` (now controls whether Readability runs), `includeTags`, `excludeTags`
- Keep: Layer 0 (code block preservation), Layer 1 (script/style/hidden), Layer 2 (ads), Layer 6 (lazy images, base64, relative URLs)
- Simplify: Layer 3 (excludeTags) and Layer 5 (includeTags) remain but run after Readability in scraper.ts, not in cleanContent

### 5. `src/scraper.ts`
- Remove `getAdapter` import and all `siteAdapter` usage
- After `cleanContent` (basic cleaning), run Readability on the result
- Use Readability's `article.content` as the HTML for markdown conversion
- Use Readability's `article.title` as fallback when `extractMetadata` returns null title
- Apply `excludeTags`/`includeTags` on Readability output if provided
- Readability needs a cloned DOM (it modifies in-place); use linkedom's `parseHTML`

### 6. Public API
- `ScrapeOptions.onlyMainContent`: semantics change from custom heuristics to Readability (non-breaking for callers)
- `ScrapeOptions.includeTags` / `excludeTags`: still work, applied after Readability
- `getAdapter` / `SiteAdapter` exports removed (breaking, but internal implementation detail)

### 7. Tests
- Delete `src/site-adapters/index.test.ts`
- Update `src/utils/content-cleaner.test.ts` if it exists (remove findMainContent tests)
