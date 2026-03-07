# Readability Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace custom content extraction heuristics in `@vakra-dev/reader` with Mozilla Readability for universal main-content extraction.

**Architecture:** Engine fetches raw HTML -> basic DOM cleaning (scripts/styles/ads/lazy-images) -> Readability extracts main content -> supermarkdown converts to Markdown. Site adapters are deleted entirely.

**Tech Stack:** `@mozilla/readability`, `linkedom` (already a dependency), TypeScript, vitest

**All file paths are relative to `/Users/mac/github/reader`.**

---

### Task 1: Install @mozilla/readability

**Files:**
- Modify: `package.json`

**Step 1: Install the dependency**

Run:
```bash
cd /Users/mac/github/reader && /opt/homebrew/bin/npm install @mozilla/readability
```

**Step 2: Install type definitions**

`@mozilla/readability` ships its own types, but verify:

Run:
```bash
cd /Users/mac/github/reader && node -e "const r = require('@mozilla/readability'); console.log('OK:', typeof r.Readability)"
```
Expected: `OK: function`

**Step 3: Commit**

```bash
cd /Users/mac/github/reader && git add package.json package-lock.json && git commit -m "feat: add @mozilla/readability dependency"
```

---

### Task 2: Delete site-adapters directory

**Files:**
- Delete: `src/site-adapters/twitter.ts`
- Delete: `src/site-adapters/wechat.ts`
- Delete: `src/site-adapters/weibo.ts`
- Delete: `src/site-adapters/index.ts`
- Delete: `src/site-adapters/types.ts`
- Delete: `src/site-adapters/index.test.ts`

**Step 1: Delete the directory**

Run:
```bash
cd /Users/mac/github/reader && rm -rf src/site-adapters
```

**Step 2: Remove exports from `src/index.ts`**

Remove these two lines from `src/index.ts`:
```typescript
export { getAdapter } from "./site-adapters/index";
export type { SiteAdapter } from "./site-adapters/index";
```

And remove the comment block `// Site adapter exports` above them.

**Step 3: Verify no other imports remain**

Run:
```bash
cd /Users/mac/github/reader && grep -r "site-adapters\|getAdapter\|SiteAdapter" src/ --include="*.ts"
```
Expected: Only hits in `src/scraper.ts` and `src/utils/content-cleaner.ts` (will be cleaned in Tasks 3-4).

**Step 4: Commit**

```bash
cd /Users/mac/github/reader && git add -A && git commit -m "refactor: delete site-adapters directory and exports"
```

---

### Task 3: Simplify content-cleaner.ts

**Files:**
- Modify: `src/utils/content-cleaner.ts`
- Modify: `src/utils/content-cleaner.test.ts`

**Step 1: Simplify `content-cleaner.ts`**

Remove the following from `src/utils/content-cleaner.ts`:

1. Remove `import type { SiteAdapter }` (line 2)
2. From `CleaningOptions` interface, remove: `siteAdapter` field, `onlyMainContent` field, `includeTags` field, `excludeTags` field. Keep only: `removeAds`, `removeBase64Images`
3. Delete these constants: `NAVIGATION_SELECTORS`, `FORCE_INCLUDE_SELECTORS`
4. Delete these functions: `getLinkDensity`, `getContentScore`, `looksLikeNavigation`, `removeWithProtection`, `findMainContent`
5. In `cleanHtml` function body, remove:
   - Layer 1.5 (site adapter preClean hook)
   - Layer 1.6 (site adapter removeSelectors)
   - Layer 3 (excludeTags)
   - Layer 4 (onlyMainContent / findMainContent / navigation removal)
   - Layer 5 (includeTags whitelist)
6. Update the file header comment to reflect the simplified layers:
   - 0: Preserve JS-rendered code blocks
   - 1: Remove scripts, styles, hidden elements, overlays
   - 2: Remove ads (if enabled)
   - 3: Cleanup (lazy images, base64, comments, relative URLs)

The `cleanHtml` function should now be approximately:

```typescript
export function cleanHtml(html: string, baseUrl: string, options: CleaningOptions = {}): string {
  const { removeAds = true, removeBase64Images = true } = options;
  const { document } = parseHTML(html);

  // Layer 0: Preserve JS-rendered code blocks
  preserveJSRenderedCodeBlocks(document);

  // Layer 1: Always remove scripts, styles, hidden elements, overlays
  removeElements(document, ALWAYS_REMOVE_SELECTORS);
  removeElements(document, OVERLAY_SELECTORS);

  // Layer 2: Remove ads (if enabled)
  if (removeAds) {
    removeElements(document, AD_SELECTORS);
  }

  // Layer 3: Cleanup
  promoteLazyImages(document);
  if (removeBase64Images) {
    removeBase64ImagesFromDocument(document);
  }

  // Remove HTML comments
  const walker = document.createTreeWalker(document, 128);
  const comments: Node[] = [];
  while (walker.nextNode()) {
    comments.push(walker.currentNode);
  }
  comments.forEach((comment) => comment.parentNode?.removeChild(comment));

  convertRelativeUrls(document, baseUrl);

  return document.documentElement?.outerHTML || html;
}
```

**Step 2: Update `content-cleaner.test.ts`**

The existing tests call `cleanHtml` which now does basic cleaning only (no main content extraction). The tests that wrap content in `<article>` will still pass because `cleanHtml` no longer removes anything beyond scripts/styles/ads/hidden. Update assertions if any test relied on navigation being stripped.

Review each test — the mermaid tests should all still pass since they test Layer 0 which is untouched. The "general" tests (removes scripts/styles, removes hidden elements) should also pass.

Run:
```bash
cd /Users/mac/github/reader && npx vitest run src/utils/content-cleaner.test.ts
```
Expected: All tests pass.

**Step 3: Commit**

```bash
cd /Users/mac/github/reader && git add src/utils/content-cleaner.ts src/utils/content-cleaner.test.ts && git commit -m "refactor: simplify content-cleaner to basic DOM cleaning only"
```

---

### Task 4: Integrate Readability into scraper.ts

**Files:**
- Modify: `src/scraper.ts`

**Step 1: Replace site adapter logic with Readability**

In `src/scraper.ts`, make these changes:

1. Remove import: `import { getAdapter } from "./site-adapters/index.js";`
2. Add imports:
```typescript
import { Readability } from "@mozilla/readability";
import { parseHTML } from "linkedom";
```

3. In `scrapeSingleUrl` method, replace the section after `cleanContent` call (approximately lines 168-201). The new logic:

```typescript
      // Clean content (basic: scripts, styles, ads, lazy images)
      const cleanedHtml = cleanContent(engineResult.html, engineResult.url, {
        removeAds: this.options.removeAds,
        removeBase64Images: this.options.removeBase64Images,
      });

      // Extract metadata from the original cleaned HTML
      const websiteMetadata = extractMetadata(cleanedHtml, engineResult.url);

      const duration = Date.now() - startTime;

      // Use Readability to extract main content (if enabled)
      let contentHtml = cleanedHtml;
      if (this.options.onlyMainContent !== false) {
        const { document } = parseHTML(cleanedHtml);
        const reader = new Readability(document, { charThreshold: 0 });
        const article = reader.parse();

        if (article?.content) {
          contentHtml = article.content;

          // Use Readability title/excerpt as fallback
          if (!websiteMetadata.title && article.title) {
            websiteMetadata.title = article.title;
          }
          if (!websiteMetadata.description && article.excerpt) {
            websiteMetadata.description = article.excerpt;
          }
        }
        // If Readability returns null, fall back to full cleaned HTML
      }

      // Apply excludeTags/includeTags if provided
      if (
        (this.options.excludeTags?.length ?? 0) > 0 ||
        (this.options.includeTags?.length ?? 0) > 0
      ) {
        const { document: doc } = parseHTML(contentHtml);

        // Remove excluded elements
        if (this.options.excludeTags?.length) {
          for (const selector of this.options.excludeTags) {
            try {
              doc.querySelectorAll(selector).forEach((el: Element) => el.remove());
            } catch { /* invalid selector */ }
          }
        }

        // Keep only included elements
        if (this.options.includeTags?.length) {
          const matched: Element[] = [];
          for (const selector of this.options.includeTags) {
            try {
              doc.querySelectorAll(selector).forEach((el: Element) => {
                matched.push(el.cloneNode(true) as Element);
              });
            } catch { /* invalid selector */ }
          }
          if (matched.length > 0 && doc.body) {
            doc.body.innerHTML = "";
            matched.forEach((el) => doc.body.appendChild(el));
          }
        }

        contentHtml = doc.documentElement?.outerHTML || contentHtml;
      }

      // Convert to requested formats
      const markdown = this.options.formats.includes("markdown")
        ? htmlToMarkdown(contentHtml)
        : undefined;

      const htmlOutput = this.options.formats.includes("html") ? contentHtml : undefined;
```

4. Remove the `excludeSelectors` option from `htmlToMarkdown` call (was `siteAdapter?.markdownExcludeSelectors`).

**Step 2: Verify TypeScript compiles**

Run:
```bash
cd /Users/mac/github/reader && npx tsc --noEmit
```
Expected: No errors.

**Step 3: Run all tests**

Run:
```bash
cd /Users/mac/github/reader && npx vitest run
```
Expected: All tests pass.

**Step 4: Commit**

```bash
cd /Users/mac/github/reader && git add src/scraper.ts && git commit -m "feat: integrate Mozilla Readability for main content extraction"
```

---

### Task 5: Build and test with folio reader-service

**Files:**
- None (integration test only)

**Step 1: Build the reader library**

Run:
```bash
cd /Users/mac/github/reader && /opt/homebrew/bin/npm run build
```
Expected: Build succeeds with `dist/` output.

**Step 2: Reinstall in folio reader-service**

Run:
```bash
cd /Users/mac/github/folio/server/reader-service && rm -rf node_modules/@vakra-dev && /opt/homebrew/bin/npm install
```

**Step 3: Start the reader service and test the Twitter Article**

Start reader service:
```bash
cd /Users/mac/github/folio/server/reader-service && npm run dev
```

Test the original failing URL:
```bash
curl -s -X POST http://localhost:3000/scrape -H 'Content-Type: application/json' -d '{"url": "https://x.com/yanhua1010/status/2029748928091148665"}' | python3 -m json.tool
```

Expected: The response should contain the full article "Claude 终极入门指南：100 小时实测，一篇讲透" content, not just the short quoted tweet about 8 plugins.

**Step 4: Test a few other URLs to verify no regression**

```bash
# Blog post
curl -s -X POST http://localhost:3000/scrape -H 'Content-Type: application/json' -d '{"url": "https://boristane.com/blog/how-i-use-claude-code/"}' | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('markdown','')),'chars')"

# WeChat article (if accessible)
curl -s -X POST http://localhost:3000/scrape -H 'Content-Type: application/json' -d '{"url": "https://mp.weixin.qq.com/s/test"}' | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('markdown','')),'chars')"
```

**Step 5: Commit the reader library changes**

```bash
cd /Users/mac/github/reader && git add -A && git commit -m "chore: build after Readability integration"
```
