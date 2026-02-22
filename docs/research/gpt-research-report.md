# Deep Research: Open-source iOS Read‑it‑later / Web Clipper Apps for Folio

## Scope, selection criteria, and research method

Folio is positioned as a local‑first iOS “collect → auto organize → full‑text search” knowledge collector, with an iOS Share Extension as the primary capture entry and a server-side pipeline for readability extraction + AI tagging/summarization (single call). This research focuses on open-source iOS implementations that can inform four modules you called out: **content extraction**, **Share Extension under tight memory**, **reader rendering**, and **local storage + search**.

Discovery and validation were done by reviewing repository metadata and READMEs on entity["company","GitHub","code hosting platform"] (stars/licensing/structure), plus project docs and issues where necessary. All “stars” are point-in-time observations (Feb 22, 2026) and will drift over time. citeturn5view5turn6view0turn12view1turn16view0

The screening lens closely mirrors your stated bar:
- iOS client exists and is “native” in the sense of Swift/SwiftUI targets (explicitly excluding React Native/Flutter where verified).
- Meaningful scope: either high community usage (stars) or substantial code volume (multiple targets/modules/commits).
- Has at least **some** notion of “content extraction” (either full readability extraction, or “link preview / reader mode / offline article text”), not just a plain URL list.
- Recent activity (≤2 years) unless it is structurally valuable (and then clearly flagged as “legacy/archived”).

## Project landscape and screened shortlist

The table below combines (a) projects that *meet most of Folio-relevant constraints* and (b) “near-miss but instructive” projects (e.g., very strong product surface area but React Native, or older but uniquely aligned with web‑to‑Markdown clipping).

| Project | Repo (code) | Stars | License | Last active signal | Tech stack snapshot | One‑line positioning |
|---|---|---:|---|---|---|---|
| Omnivore | `https://github.com/omnivore-app/omnivore` citeturn5view5 | 15.9k citeturn5view5 | AGPL‑3.0 citeturn5view5turn22view2 | Commits on **2026‑01‑04** citeturn8view0 | Full open-source stack; server includes a “content-fetch” flow and a “puppeteer-parse” service for saving pages citeturn22view2 | Full self-hosted read‑it‑later platform; native iOS app + offline support citeturn22view2 |
| wallabag iOS | `https://github.com/wallabag/ios-app` citeturn6view0 | 205 citeturn6view0 | MIT citeturn22view1 | Commits on **2026‑02‑20** citeturn9view0 | Swift codebase with offline reading; companion app to wallabag server citeturn22view1 | Native iOS companion for a self-hosted extractor; read offline citeturn22view1turn26search3 |
| Readeck iOS | `https://github.com/ilyas-hallak/readeck-ios` citeturn6view2turn22view0 | 28 citeturn6view2 | MIT citeturn6view2turn22view0 | Commits on **2025‑12‑01** citeturn9view2 | Native iOS client for a Readeck server; includes Share Extension and offline queueing when server is down citeturn22view0 | “Client-first” UX for a self-hosted read-it-later backend citeturn22view0 |
| YABA | `https://github.com/Subfly/YABA` citeturn12view1turn21view1 | 205 citeturn12view1 | AGPL‑3.0 citeturn12view1turn21view1 | Commits on **2026‑02‑21** citeturn13view1 | SwiftUI + SwiftData on Apple platforms; multiple extensions (Share/Keyboard/Widgets), “Reader Mode”, “full-text search”, Spotlight integration citeturn21view1 | Offline-first, privacy-first bookmark manager with tight Apple-platform integration citeturn21view1 |
| CrossX (crosspoint-app) | `https://github.com/jtvargas/crosspoint-app` citeturn6view3turn23view0 | 14 citeturn6view3 | MIT citeturn6view3turn23view0 | Commits on **2026‑02‑21** citeturn9view3 | SwiftUI app + iOS Share Extension; “dual content extraction” via SwiftSoup heuristic + Readability.js fallback; SwiftData for queue tracking citeturn23view0 | A pragmatic “URL → extracted text → portable format” pipeline that runs even inside the Share Extension citeturn23view0 |
| Hipstapaper | `https://github.com/jeffreybergier/Hipstapaper` citeturn6view1turn22view3 | 91 citeturn6view1 | MIT citeturn6view1turn22view3 | Commits on **2026‑01‑23** citeturn9view1 | SwiftUI + Core Data + NSPersistentCloudKitContainer; Share Extension saves URL + title + screenshot citeturn22view3 | A compact, modern “reading list” reference for Share Extension + iCloud sync citeturn22view3 |
| Bookmarks (InSeven) | `https://github.com/inseven/bookmarks` citeturn12view0turn11view0 | 39 citeturn12view0 | MIT citeturn12view0turn11view0 | **Archived 2025‑04‑02** citeturn12view0 | Swift-heavy repo; Pinboard client for iOS/macOS citeturn11view0turn12view0 | Worth scanning for “two-platform native app” patterns, but inactive citeturn12view0 |
| Pinpin | `https://github.com/cassardp/Pinpin` citeturn12view2turn11view4 | 2 citeturn12view2 | MIT citeturn12view2 | Commits on **2026‑02‑11** citeturn15view0 | SwiftUI + SwiftData + CloudKit; MVVM + Services; Share Extension; offline-first citeturn11view4turn12view2 | Not read‑it‑later, but a clean “local-first + SwiftData + CloudKit” reference citeturn11view4 |
| Karakeep (formerly Hoarder) | `https://github.com/karakeep-app/karakeep` citeturn16view0turn19search6 | 23.6k citeturn16view0 | AGPL‑3.0 citeturn16view0 | Mobile releases “Latest **2026‑01‑25**” citeturn19search12 | Mobile app uses Expo/React Native (not SwiftUI) citeturn19search6turn19search2turn19search3 | Feature-rich reference for AI tagging + archival, but excluded for Folio’s “native SwiftUI only” constraint citeturn16view0turn19search6 |
| Scrapmd (legacy but aligned) | `https://github.com/scrapmd/scrapmd` citeturn11view3turn10search11 | 15 citeturn11view3 | MIT citeturn11view3 | Commits on **2020‑06‑23** citeturn15view1 | Markdown “webpage scrapbook”; described as clipping content into iCloud Drive in Markdown with embedded images citeturn10search11turn11view3 | Old, but conceptually close to Folio’s “web → Markdown” pipeline citeturn10search11turn15view1 |

image_group{"layout":"carousel","aspect_ratio":"16:9","query":["Omnivore iOS app screenshots","wallabag iOS app screenshots","Readeck iOS app screenshots","YABA Yet Another Bookmark App screenshots","CrossX Send To X4 app screenshots"],"num_per_query":1}

Top-5 for deep architecture comparison (closest to Folio’s constraints and learning goals): **Omnivore**, **wallabag iOS**, **Readeck iOS**, **YABA**, **CrossX**. citeturn22view2turn22view1turn22view0turn21view1turn23view0

## Deep dives on top candidates

### Omnivore

**Content extraction approach**  
Omnivore explicitly uses **Mozilla Readability** to make pages easier to read. entity["organization","Mozilla","open source organization"] is name‑checked in the “Shoutouts” section. citeturn22view2 Beyond “readability,” Omnivore’s self-hosted architecture includes a **content fetching microservice**, and saving pages in local dev requires the **puppeteer‑parse** service (Chromium-based), which strongly signals a server-side approach that can handle JS-heavy pages via headless browsing. citeturn22view2 This is directly relevant to Folio’s current server-side Node “reader to Markdown” pipeline: Omnivore demonstrates the “separate parse service” pattern for pages that readability-only extraction can’t reliably parse.

**Share Extension strategy**  
Omnivore’s README emphasizes a native iOS app and browser extensions, but does not document an iOS Share Extension architecture in the lines available. citeturn22view2 Net: Omnivore is most valuable to Folio as a **reference architecture for server extraction + offline-capable client**, not primarily as a Share Extension memory-optimization case study.

**Local storage, offline mode, and search**  
Omnivore claims “offline support” and “automatically saves your place in long articles.” citeturn22view2 It is not explicit (in the surfaced sources) about which on-device store / index is used, so treat it as a *product capability reference*, not an implementation-ready blueprint for SwiftData/FTS5.

**Reader implementation**  
Product-level reader features include highlights/notes, PDF support, and iOS-only text-to-speech. citeturn22view2 The PDF path is notable because many read-it-later tools rely on web views; Omnivore explicitly credits PDF.js for open-source PDF functionality—but that likely applies to web. citeturn22view2

**Sync + network layer**  
Omnivore has an API service, uses PostgreSQL in its self-host stack, and calls out generated GraphQL queries on iOS via “Swift GraphQL.” citeturn22view2 This is useful for Folio if you ever consider a typed API layer (GraphQL or codegen REST clients) for sync consistency.

**Engineering practices**  
It’s a large monorepo with many services; the iOS app is just one part of a bigger system. citeturn22view2turn7view0 Active maintenance exists through at least early 2026. citeturn8view0

### wallabag iOS

**Content extraction approach**  
wallabag (server) positions itself as a web application that “extracts content so that you won’t be distracted.” citeturn26search3 The iOS repository explicitly frames itself as a companion app to the wallabag server. citeturn22view1 In practical terms, wallabag’s “extraction” is **server-side**, and the iOS app’s job is offline caching + reading UX.

**Share Extension strategy**  
The wallabag iOS ecosystem depends heavily on an iOS Share Extension in real usage; a long-standing wallabag ecosystem issue explicitly calls the iOS app’s Share Extension “essential,” and current iOS-app issues include items like “Fix broken share extension animation,” strongly indicating the Share Extension is a maintained surface area. citeturn26search24turn26search15 (This can be valuable to Folio specifically because Share Extensions are the highest-friction part of capture UX.)

**Local storage + offline reading**  
The iOS app README is explicit: the app “lets you read your wallabag links offline.” citeturn22view1 The internal persistence technology is not declared in the README excerpt, so you would still need to inspect code if you want to mirror its caching strategy.

**Reader implementation**  
No rendering stack is documented in the surfaced sources. Because wallabag exists to read extracted text, the likely trade-offs are similar to Folio’s: choose between WebView-based HTML rendering or native text rendering.

**Sync + auth**  
wallabag’s official iOS setup documentation instructs users to configure the app with a wallabag address and then provide a **client ID and client secret** generated via “API Clients Management.” citeturn26search21 This indicates an OAuth-style client credential onboarding flow (or at least OAuth client configuration) and is a useful reference if Folio ever introduces user-hosted backends or multi-tenant auth.

**Engineering practices**  
The repo is actively updated as of Feb 2026. citeturn9view0turn6view0 That matters because Share Extensions can regress across iOS releases; recent activity suggests some adaptation to newer platform behaviors.

### Readeck iOS

**Content extraction approach**  
The app is explicitly “a native iOS client for readeck bookmark management,” implying extraction happens on the Readeck server. citeturn22view0 The iOS app’s differentiator is a client optimized for reading, progress, and offline robustness.

**Share Extension strategy**  
Readeck iOS documents its Share Extension flow end-to-end: share a webpage, select “readeck,” optionally edit title, and save. citeturn22view0 This is a direct parallel to Folio’s Share Extension “write URL immediately, process async” model.

**Offline-first behavior**  
A key implementation idea is stated plainly in the features list: “Save bookmarks when server is unavailable and sync when reconnected.” citeturn22view0 That is almost exactly Folio’s “local-first capture + async backend” pattern, except Readeck’s “backend” is the user’s own server rather than Folio’s service.

**Local storage + search + data model**  
Readeck iOS lists “Search functionality,” “Support for reading progress,” as well as “Article View with Reading Time and Word Count.” citeturn22view0 Even without code-level detail, this indicates a model that likely includes: Bookmark/Article, ReadingProgress, plus view-layer computed fields (word count/reading time). The important “pattern to borrow” is that search + progress remain “core” even in a client that is fundamentally a sync mirror.

**Reader implementation**  
The UI feature set includes font customization and an article view with reading metrics. citeturn22view0 Those are exactly the kind of “reader polish” knobs Folio can benchmark against.

**Engineering practices**  
The repo contains iOS and UI test targets by directory naming on the root listing, and it uses fastlane (per folder naming), suggesting some CI/release automation. citeturn7view3turn22view0 Recent maintenance through late 2025 is present. citeturn9view2

### YABA

**Content extraction approach**  
YABA claims “Link Previews: Automatic metadata extraction” and “Reader Mode: Distraction-free reading.” citeturn21view1 Importantly, YABA is positioned as “offline first” and “privacy first,” with all data staying on device—so its extraction (at least for previews/reader mode) is almost certainly **client-side** rather than relying on a server. citeturn21view1 For Folio’s first research question (“can we do partial extraction on-device to reduce latency?”), YABA is a strong reference point because it frames extraction as a local capability.

**Share Extension strategy**  
YABA makes extensions a first-class architectural unit: the project structure enumerates a Share Extension plus other system integrations (widgets, keyboard extension, etc.). citeturn21view1 This matters for Folio because it implies careful separation of “core domain” from “extension entry points”—a practical modularization pressure that often improves overall code quality.

**Local storage + search**  
YABA explicitly uses SwiftData for persistence and claims a “full-text search with filters.” citeturn21view1 It also calls out Spotlight integration on iOS. citeturn21view1 The combined pattern is: **local database search for in-app query** + **Spotlight for OS-level “jump-in” navigation**, which Folio could adopt alongside SQLite FTS5.

**Sync**  
The most distinctive claim is “server-less sync” using “peer-to-peer data synchronization across devices without servers.” citeturn21view1 Even if Folio does not adopt P2P sync, the *problem decomposition* is instructive: write everything locally first; treat sync as a layer that can be swapped (server-based, CloudKit-based, or P2P).

**Engineering practices**  
YABA documents an “MV architecture” and observer/reactive state management, and calls out Swift Concurrency. citeturn21view1 It is also actively updated (Feb 2026). citeturn13view1turn12view1

### CrossX (crosspoint-app)

CrossX is not a classic “read-it-later library,” but from an engineering angle it is one of the strongest references for Folio’s **two** hardest problems: “on-device extraction feasibility” and “how much work can you safely do inside the Share Extension.”

**Content extraction approach**  
CrossX documents a layered extraction pipeline: a “fast SwiftSoup heuristic extraction” path, with “automatic Readability.js fallback for complex pages,” and even special-case extraction for Twitter/X threads. citeturn23view0 This is an unusually concrete, production-style blueprint for a *hybrid extractor*:
- Try a fast DOM + heuristics approach first.
- If it fails, run Readability.js.
- If the source is a special domain / format, route to a specialized extractor. citeturn23view0

This maps cleanly to Folio’s interest in “client partial extraction”: you can implement a **fast path** locally (for perceived performance), while keeping your current server extractor as the **quality backstop**.

**Share Extension strategy**  
CrossX states it runs the “complete fetch → extract → build → send” flow **in the Share Extension**. citeturn23view0 That is the polar opposite of the minimal “save URL only” approach—and therefore extremely useful as a stress-test reference for what can be done (and how to design it safely):
- It supports “fallback to local save” when the destination isn’t reachable. citeturn23view0  
- It maintains an offline queue and persists queued items across app restarts; the queue is “stored in Application Support with SwiftData tracking.” citeturn23view0  

Even if Folio never runs full extraction in the extension, CrossX shows how to design an **extension-capable pipeline** with persistence and retry semantics.

**Local storage + search**  
CrossX uses SwiftData (for queue tracking) and also claims full-text search across “activity events.” citeturn23view0

**Reader implementation**  
CrossX’s output is EPUB rather than an in-app reader view, but it importantly shows a clean boundary: extraction produces sanitized text content, and rendering/consumption is an independent concern. citeturn23view0 This boundary is also useful for Folio (store extracted “content AST / Markdown” separate from rendering).

**Engineering practices**  
It is actively maintained (Feb 2026). citeturn9view3turn6view3 It targets very new Apple platform versions (iOS 26+ per README), so Folio would reuse patterns rather than code. citeturn23view0

## Folio gap analysis and best-practice patterns

### Feature alignment matrix

| Capability | Folio today (from your spec) | Omnivore | wallabag iOS | Readeck iOS | YABA | CrossX | Best-practice synthesis for Folio |
|---|---|---|---|---|---|---|---|
| Content extraction | Server-side Node → Markdown | Uses Mozilla Readability; has puppeteer-parse service for saving pages citeturn22view2 | Server extracts “content so you won’t be distracted” citeturn26search3 | Server-based (client for Readeck) citeturn22view0 | Local “link previews” + “reader mode” citeturn21view1 | Local hybrid: SwiftSoup fast path + Readability.js fallback citeturn23view0 | Adopt **hybrid extraction**: local fast path for speed, server fallback for quality / JS-heavy pages (pattern proven by CrossX + Omnivore). citeturn23view0turn22view2 |
| Share Extension | URL written locally; async backend | Not documented in surfaced sources | Share extension is a maintained surface area (issues) citeturn26search15 | Explicit Share Extension flow citeturn22view0 | Share extension as first-class “Apple Platform Implementation” module citeturn21view1 | Full pipeline in extension incl. offline queue citeturn23view0 | Keep Folio’s “thin extension” default, but optionally add a **configurable ‘fast preview’ path** (title + excerpt + hero image) if within budget. |
| Offline-first capture | Local write first, backend async | Offline support citeturn22view2 | Offline reading citeturn22view1 | Queue when server unavailable, sync later citeturn22view0 | Offline first + “sync when connected” (P2P) citeturn21view1 | Offline queue + persistence citeturn23view0 | Folio is already aligned; the main opportunity is to strengthen “retry/queue semantics” and “user feedback” (queue count, last error). |
| Reader polish | SwiftUI Markdown rendering | Rich feature set inc. highlights, TTS, reading position citeturn22view2 | Offline reading UX (details not surfaced) citeturn22view1 | Font customization + reading metrics + progress citeturn22view0 | Reader mode + platform-native UX citeturn21view1 | Not in-app reader; outputs EPUB citeturn23view0 | Benchmark against Readeck/YABA for **font/theme/progress knobs** and against Omnivore for **annotations + TTS** where relevant. citeturn22view0turn21view1turn22view2 |
| Local storage + search | SwiftData + SQLite FTS5 | Not specified | Not specified | Search + progress (impl not specified) citeturn22view0 | SwiftData + claimed full-text search + Spotlight citeturn21view1 | SwiftData tracking + search over activity events citeturn23view0 | Your design (FTS5) remains a strong default; add **Spotlight indexing** as a complement (pattern: YABA). citeturn21view1 |
| AI tagging/summarization | Server-side single call | Not covered in sourced lines | Not covered | Not covered | Not covered | Not covered | Folio’s differentiator: keep the “single call” design; consider local “cheap classifier” only if latency is a critical UX issue. |

### Patterns that repeatedly emerge

**Hybrid extraction beats “all-or-nothing”**  
The sharpest practical blueprint is CrossX’s explicit “SwiftSoup fast extraction + Readability.js fallback.” citeturn23view0 Omnivore complements this with a separate Chromium/puppeteer-based parse service, which is the “quality backstop” for complex sites. citeturn22view2 For Folio, these two taken together motivate a pragmatic architecture:

- **Fast path (device, cheap):** title, byline, excerpt, main text if easy.  
- **Reliable path (server, slower):** full Markdown conversion, images, handling JS-rendering and paywalls where possible.  

If you want to explore client-side extraction, the ecosystem now has multiple Swift-friendly readability options:
- A WKWebView-integrated wrapper around Firefox Reader / mozilla/readability (swift-readability). citeturn4search1  
- A Swift port of Readability.js using SwiftSoup (SwiftReadability). citeturn4search9  
- Other “reader mode” implementations like Reeeed. citeturn4search5  
- Preview/text extraction utilities like ReadabilityKit. citeturn4search32  

**Share Extensions should usually be “thin,” because the OS will kill them aggressively**  
Apple explicitly warns that extension memory limits are “significantly lower” and the system may terminate extensions aggressively. citeturn24search20 Multiple field reports show Share Extensions commonly hitting an EXC_RESOURCE memory ceiling around **120 MB** (device-dependent), including Stack Overflow reproductions and other references. entity["organization","Stack Overflow","programmer q&a site"] citeturn24search1turn24search7turn24search4

This has very concrete engineering implications for Folio:
- Avoid decoding large media into UIImage in the extension; prefer passing file URLs / streaming instead (documented as a well-known mitigation). citeturn24search5turn24search2  
- Prefer “write minimal record to App Group” + background processing in the main app (Apple’s guidance + common practice). citeturn24search20turn24search8  
- CrossX shows that “heavy extension” can work, but it is a higher-risk path: it runs the full pipeline in the extension and therefore must also design for offline persistence and failures. citeturn23view0  

**Local database search + OS-level search is a compelling combo**  
Folio’s SQLite FTS5 is well-suited for offline full-text search (controllable ranking, tokenization, indexing), while YABA’s explicit “Spotlight integration” indicates value in complementing in-app search with OS-level entry points. citeturn21view1 Practically: FTS5 remains the internal truth; Spotlight becomes the “quick jump” layer for the most recent / most important items.

### Concrete “borrowable” implementations and migration effort

Because several repositories’ directory listings could not be fully expanded via the available web snapshots, the “paths” below are given at a **module/directory level** (still actionable for code archaeology), and are backed by each project’s own documented structure.

- **CrossX: hybrid extraction pipeline (SwiftSoup → Readability.js fallback)**  
  Source: `crosspoint-app` README describes the dual extraction pipeline and its fallback logic. citeturn23view0  
  Solves: “client-side partial extraction” feasibility and design (fast path + fallback).  
  Migration to Folio: **Medium** (you’d implement extraction into your Share Extension *or* main app background task, and maintain parity with your server Markdown format).

- **CrossX: Share Extension that can run “full pipeline” with offline queue + SwiftData tracking**  
  Source: README describes running full pipeline in extension and persisting queued EPUBs in Application Support with SwiftData tracking. citeturn23view0  
  Solves: “how to design extension-capable processing with resilience.”  
  Migration to Folio: **Medium → Large** (Folio’s content format is Markdown + images, and iOS 17 target may impose different constraints than CrossX’s iOS 26+ target). citeturn23view0

- **Readeck iOS: offline capture queue when server is unreachable**  
  Source: feature list states saving bookmarks while server unavailable and syncing later; also documents Share Extension. citeturn22view0  
  Solves: “offline-first capture with clear reconnection semantics.”  
  Migration to Folio: **Small** (high conceptual overlap with your existing “write URL locally, async backend” design).

- **YABA: multi-extension architecture (Share/Widgets/Keyboard) under a single “Darwin platform” implementation**  
  Source: README “Project Structure” enumerates multiple Apple targets/modules and lists the Darwin tech stack (SwiftUI + SwiftData). citeturn21view1  
  Solves: “how to keep the domain model shared while supporting multiple extension entry points.”  
  Migration to Folio: **Medium** (requires refactoring into reusable modules/SPM packages if you haven’t already, but pays off in extension reliability).

- **Hipstapaper: Share Extension capture into Core Data + CloudKit sync**  
  Source: README describes saving via Share Extension, capturing title + screenshot, then persisting via Core Data and syncing via NSPersistentCloudKitContainer. citeturn22view3  
  Solves: “simple capture UX + immediate local persistence + cross-device sync.”  
  Migration to Folio: **Small → Medium** (you don’t need CloudKit, but the “capture minimal metadata immediately” pattern is directly reusable).

## Recommendations and action items

### Technical recommendations by module

**Client-side content extraction (reduce perceived latency without abandoning server quality)**  
A strong direction is a **two-tier extractor**:
- Implement an **on-device “fast preview” extractor** (title/byline/excerpt + “good-enough” article body when possible) using patterns similar to CrossX (SwiftSoup heuristics + fallback). citeturn23view0  
- Keep Folio’s server pipeline for “authoritative Markdown conversion,” especially for JS-rendered pages (Omnivore’s need for a puppeteer-parse service is a strong signal that headless browsing remains necessary for high coverage). citeturn22view2  
- If you need a more “readability-like” extraction on device, evaluate Swift implementations that wrap or port mozilla/readability. citeturn4search1turn4search9turn4search5  

**Share Extension optimization under memory constraint**  
Assume the extension process will be memory constrained and aggressively killed. citeturn24search20turn24search1 Practical guardrails:
- Treat the extension as a **thin intake layer**: persist URL + minimal metadata to the App Group container, return quickly. citeturn24search20turn24search8  
- Avoid loading large resources into memory (especially images). Prefer passing file URLs and streaming uploads/processing where possible. citeturn24search5turn24search2  
- Use CrossX as a “how far can you go” reference, but keep that as an *opt-in* complexity unless Folio has a strong reason to run extraction inside the extension. citeturn23view0  

**Reader quality improvements**  
The strongest reader-product benchmarks among the reviewed iOS clients are:
- Readeck iOS for **font customization + reading metrics + progress** as explicit features. citeturn22view0  
- Omnivore for **highlights/notes and iOS-only text-to-speech** as high-retention reading UX features. citeturn22view2  
- YABA for positioning “reader mode” as a core experience, not an afterthought. citeturn21view1  

For Folio specifically (SwiftUI Markdown rendering today), the key “best-practice” decision is less about a single library and more about defining a stable internal content representation:
- Treat your extracted content (Markdown + structured blocks + image manifests) as the canonical layer.
- Let rendering be swap‑able: SwiftUI-native for speed and consistency, and a WebView/HTML renderer only when you need higher fidelity for complex layouts.

**Local storage and search**  
Folio’s SwiftData + SQLite FTS5 foundation is already competitive for local-first apps. What the open-source landscape suggests adding is:
- OS-level indexing (Spotlight) for fast “jump back in” discovery, following YABA’s explicit Spotlight integration. citeturn21view1  
- A clear separation of “domain store” vs “search index,” so indexing can be rebuilt without data loss.

### Risks and license considerations

- **AGPL code reuse risk:** Omnivore and YABA are AGPL-licensed. If you copy significant source code into Folio, you risk license obligations that may not align with Folio’s distribution goals. Treat them as **pattern references**, or isolate any reuse behind clean-room reimplementation. citeturn22view2turn21view1  
- **Archived/legacy code drift:** Some conceptually aligned projects (e.g., Scrapmd) are inactive for years; they can inspire architecture but may not reflect modern iOS behaviors (Share Extension constraints changed across iOS releases). citeturn15view1turn24search20  
- **Platform version mismatch:** CrossX targets iOS 26+ and uses modern UI affordances; Folio targets iOS 17, so reuse is conceptual rather than direct. citeturn23view0  

### Priority focus for Folio right now

The highest ROI path, based on the comparative landscape, is:

1) **Hybrid content extraction** (device fast preview + server authoritative Markdown)  
Grounded by CrossX’s documented pipeline and Omnivore’s dedicated parse service for saving pages. citeturn23view0turn22view2  

2) **Share Extension resilience and memory discipline**  
Grounded by Apple’s guidance on aggressive termination and field evidence of the ~120MB ceiling; also reinforced by wallabag’s ongoing Share Extension bug/UX work. citeturn24search20turn24search1turn26search15  

3) **Reader polish loop** (progress, font/theme controls, reading metrics)  
Grounded by Readeck’s explicit feature set and Omnivore’s retention-oriented reader features. citeturn22view0turn22view2  

### Action items

- Build a **client-side extraction spike**: implement a fast-path extractor (SwiftSoup heuristics) and benchmark it against your server Markdown on a representative URL corpus; use a readability fallback library only when heuristics fail (CrossX pattern). citeturn23view0turn4search9  
- Add a **“preview-ready state”** to your data model: store title, site name, favicon/hero image URL (or cached image), and a short excerpt immediately after capture—then upgrade to full Markdown asynchronously. (This mirrors the minimal capture approach exemplified by Hipstapaper/Readeck flows.) citeturn22view3turn22view0  
- Run a Share Extension “budget audit”: instrument peak memory when sharing (a) text-only links, (b) heavy pages, (c) pages from apps that attach rich previews. Treat 120MB as an operational ceiling and design to avoid large in-memory blobs. citeturn24search1turn24search5turn24search20  
- Prototype **Spotlight indexing** for recent/high-priority items and compare UX impact against in-app FTS-only search (YABA’s integration suggests user value). citeturn21view1  
- Define a “reader parity checklist” (font/theme/progress/reading time/word count/TTS/annotations) using Readeck + Omnivore as benchmarks, then map which belong to Folio’s differentiation vs “table stakes.” citeturn22view0turn22view2  

Folio’s strategic differentiation (single-call AI classification + local-first library + hybrid server pipeline) remains uncommon among the open-source reference set. The main opportunity is to **pull perceived performance forward** (fast local preview) without compromising your current server-based quality, and to harden the Share Extension capture path so it feels “instant and unbreakable” under real-world constraints. citeturn23view0turn24search20turn24search1