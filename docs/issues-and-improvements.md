# Folio E2E 测试 — 问题与改进总结

测试覆盖: 27/33 用例 (82%)，2026-03-06

---

## Bugs

| # | 严重度 | 来源 | 描述 | 根因分析 |
|---|--------|------|------|---------|
| B1 | 中 | T5.1 / T6.3 | 微博文章标题显示 "微博正文 - 微博"，无意义 | Reader 对微博页面的 `<title>` 标签直接使用，未提取正文中的实际标题；微博的 HTML title 就是 "微博正文 - 微博" |
| B2 | 中 | T6.3 | 微博文章摘要含原始 URL（`//s.weibo.com/weibo?q=...`） | AI (Mock) 分析时未清理微博正文中的话题链接和超链接，直接包含在 summary 中 |
| B3 | 低 | T6.3 | 微博正文 markdown 渲染有噪音（多余链接/格式残留） | Reader 抓取微博内容时，话题标签 `#xxx#` 被转为 markdown 链接，`@用户` 也保留了原始 URL |
| B4 | 低 | T7 | 搜索页显示 "搜索 0 篇已同步文章"，但实际有文章可搜索 | 本地 FTS 索引的文章计数与 SwiftData 同步状态不一致，可能是 `syncedArticleCount` 逻辑有误 |

## 功能缺失

| # | 优先级 | 来源 | 描述 |
|---|--------|------|------|
| F1 | 低 | T7.4 | 搜索历史未实现 — 空输入时显示 Popular Tags 而非最近搜索词 |

## 按优先级排序的修复建议

### P0 — 影响内容质量（B1 + B2 + B3 微博三连）

这三个问题根因相同：**微博内容源的抓取和清洗质量差**。

**建议方案**：
1. **Reader 层**：微博页面特殊处理 — 从正文提取标题（取第一句非空文本），而非使用 `<title>`
2. **AI prompt**：在 AI 分析 prompt 中增加指令 "Remove raw URLs, hashtag links, and @mention URLs from the summary"
3. **Markdown 清洗**：在 CrawlHandler 存储前增加 post-processing 步骤，清理微博特有的噪音（`//s.weibo.com` 链接、空话题锚点等）

### P1 — 影响用户感知（B4）

**建议方案**：检查 `SearchViewModel` 中 `syncedArticleCount` 的计算逻辑，确保与本地 FTS 索引实际包含的文章数一致。

### P2 — 体验优化（F1）

**建议方案**：在 `SearchViewModel` 中添加搜索历史存储（UserDefaults 或 SwiftData），空输入时优先显示最近 5 条搜索词，下方仍保留 Popular Tags。

---

## 亮点（测试中表现良好的功能）

- **英文博客全链路**：go.dev / martinfowler.com / joelonsoftware.com 从提交到阅读体验优秀
- **Reader 阅读页**：markdown 渲染质量高，链接可点击，标题层级清晰
- **Reading Preferences**：Font Size / Line Spacing / Theme / Font 完整可用
- **More 菜单**：Favorite / Copy Markdown / Reading Preferences / Archive / Open Original / Delete 齐全
- **搜索**：中英文实时搜索响应快，空结果状态友好
- **设置页**：用户信息、同步状态、配额进度条布局清晰
- **Processing 状态**："AI is still analyzing this article" + "Open Original" 提供了良好的等待体验
- **配额控制**：API 层正确拒绝超限请求
