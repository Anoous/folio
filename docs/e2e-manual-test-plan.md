# Folio 端到端手动测试计划

## 测试环境与工具

### 启动环境
```bash
cd server && ./scripts/dev-start.sh   # Go API :8080 + Reader :3000 + Mock AI :8000 + PG + Redis
```

### Claude Code 测试工具链

| 能力 | 命令 |
|------|------|
| 看 iOS 屏幕 | `xcrun simctl io booted screenshot` → Read 图片 |
| 操作 iOS | Appium + XCUITest driver (`http://localhost:4723`) |
| iOS 日志 | `xcrun simctl spawn booted log stream --level debug --predicate 'subsystem == "com.folio.app"'` |
| Go 后端日志 | `grep -aE 'level=' /tmp/folio-dev.log` |
| 数据库查询 | `docker exec $(docker ps --filter "publish=5432" -q) psql -U folio -d folio -c "SQL"` |
| Redis 查看 | `docker exec $(docker ps --filter "publish=6380" -q) redis-cli` |
| 编译安装 iOS | `xcodebuild build` → `xcrun simctl install` → `xcrun simctl terminate/launch` |

### Appium 连接模板
```python
from appium import webdriver
from appium.options.ios import XCUITestOptions

options = XCUITestOptions()
options.platform_name = "iOS"
options.device_name = "iPhone 17 Pro"
options.udid = "<booted simulator udid>"
options.bundle_id = "com.folio.app"
options.no_reset = True
options.set_capability("appium:automationName", "XCUITest")
options.set_capability("appium:usePreinstalledApp", True)

driver = webdriver.Remote("http://localhost:4723", options=options)
```

---

## 测试用例

### T1: 认证流程

#### T1.1 Dev Login
- **操作**: 冷启动 app → 点击 "Dev Login"
- **预期**: 跳转首页，显示 "Dev User"
- **验证**: iOS 日志 `[auth] dev login succeeded`，Go 日志 `dev login succeeded`
- **截图**: 登录前 + 登录后

#### T1.2 Token 持久化
- **操作**: 登录后杀掉 app → 重启 app
- **预期**: 自动恢复登录态，不显示登录页
- **验证**: iOS 日志 `[auth] existing auth validated`

#### T1.3 Sign Out
- **操作**: 设置页 → Sign Out
- **预期**: 回到未登录态
- **验证**: iOS 日志 `[auth] user signed out`

#### T1.4 Token 过期刷新
- **操作**: 修改 access token TTL 为极短时间，等过期后操作
- **预期**: 自动 refresh，操作不中断
- **验证**: iOS 日志 `401 unauthorized, attempting refresh` → `token refresh succeeded`

---

### T2: 文章提交（从 app 内）

#### T2.1 正常提交
- **操作**: 首页 "+" → 输入 URL（如 `https://go.dev/blog/using-go-modules`）→ 提交
- **预期**: 文章出现在列表，状态 pending → processing → ready
- **验证**:
  - iOS 日志: `[data] article saved` → `[network] processing N pending` → `[sync] article submitted` → `[sync] task done`
  - Go 日志: `article submitted` → `crawl task completed` → `ai task completed`
  - 截图: 提交后卡片状态变化

#### T2.2 重复 URL 提交
- **操作**: 再次提交同一 URL
- **预期**: 提示 "已收藏" 或 duplicate
- **验证**: Go 日志 `duplicate URL rejected`

#### T2.3 配额超限
- **操作**: 将用户 monthly_quota 设为 1，已用 1 次后再提交
- **预期**: 提示 quota exceeded
- **验证**: Go 日志 `quota exceeded`，iOS 日志 `[sync] quota exceeded`

---

### T3: Share Extension

#### T3.1 从 Safari 分享
- **操作**: 模拟器打开 Safari → 访问网页 → 分享 → 选 Folio
- **预期**: Share Sheet 显示保存成功，回到 app 看到新文章
- **验证**: iOS 日志 `[data] share: article saved` → `[data] extraction started`

#### T3.2 分享重复 URL
- **操作**: 分享已收藏过的 URL
- **预期**: Share Sheet 显示 "已收藏"
- **验证**: iOS 日志 `[data] share: duplicate URL`

#### T3.3 分享后客户端提取
- **操作**: 分享一个标准博客 URL
- **预期**: Share Sheet 显示 extracting → extracted
- **验证**: iOS 日志 `[data] extraction started` → `extraction: HTML fetched` → `extraction completed`

---

### T4: 文章处理流水线（后端）

#### T4.1 Reader 抓取 → AI 分析 → 完成
- **操作**: 提交一篇新文章，等待处理完成
- **验证**:
  - Go 日志完整链路: `article submitted` → `crawl task completed` → `ai task completed`
  - 数据库: `SELECT status, category_id, summary FROM articles WHERE url = '...'`
  - App 拉到最新数据: 有分类、标签、摘要

#### T4.2 Reader 失败降级到客户端内容
- **操作**: 提交一个 Reader 无法抓取的 URL（如内网地址），但客户端已提取内容
- **验证**: Go 日志 `using client-provided content, skipping Reader`

#### T4.3 缓存命中
- **操作**: 用户 A 提交过的 URL，用户 B 再提交
- **验证**: Go 日志 `crawl task completed via cache hit`

---

### T5: 首页列表

#### T5.1 文章列表展示
- **操作**: 首页查看文章列表
- **验证截图**:
  - 标题是否有意义（不是 "微博正文 - 微博" 这种）
  - 摘要是否干净（不含 markdown 语法、原始链接）
  - 时间显示正确
  - 标签显示正确
  - 分类筛选 chip 可点击

#### T5.2 分类筛选
- **操作**: 点击分类 chip（技术 / 其他 / All）
- **预期**: 列表过滤正确
- **截图**: 每个分类的列表

#### T5.3 下拉刷新
- **操作**: 下拉触发刷新
- **预期**: 从服务端拉取最新数据
- **验证**: iOS 日志 `[sync] starting full sync`

#### T5.4 文章状态展示
- **操作**: 观察不同状态的文章卡片
- **截图**: pending / processing / clientReady / ready / failed 各状态的卡片样式

#### T5.5 失败重试
- **操作**: 对 failed 文章点击 "Retry"
- **预期**: 状态变回 pending → processing
- **验证**: iOS 日志 `[sync] retryArticle`

---

### T6: 阅读页

#### T6.1 正常阅读
- **操作**: 点击一篇 ready 文章进入阅读页
- **验证截图**:
  - 标题排版
  - AI 摘要区域
  - 正文 markdown 渲染（标题层级、粗体、链接、代码块、引用、列表、图片、表格）
  - 阅读进度百分比

#### T6.2 滚动阅读进度
- **操作**: 滚动到页面底部
- **预期**: 底部进度条从 0% → 100%

#### T6.3 不同内容源渲染质量
- **操作**: 分别查看以下来源的文章
  - 标准英文博客
  - 微博
  - 微信公众号（如果有）
  - Twitter/X
- **截图**: 每种来源的阅读页效果
- **关注**: 标题质量、内容完整度、图片显示、排版噪音

#### T6.4 阅读偏好设置
- **操作**: 更多菜单 → Reading Preferences → 调整字号/行距/字体/主题
- **截图**: 调整前后对比

#### T6.5 收藏/归档/删除
- **操作**: 在阅读页通过更多菜单执行收藏、归档、删除
- **预期**: 操作成功，Toast 提示，返回列表后状态更新

#### T6.6 无内容状态
- **操作**: 点击一篇 processing 中的文章
- **预期**: 显示 "AI is still analyzing" 提示
- **截图**: 无内容状态页面

#### T6.7 Open Original
- **操作**: 底部工具栏点 "Original" 或更多菜单 "Open Original"
- **预期**: WebView 打开原始页面

---

### T7: 搜索

#### T7.1 关键词搜索
- **操作**: 首页搜索框输入关键词
- **预期**: 实时显示匹配结果（200ms 防抖）
- **验证**: 结果数量、高亮标题、摘要片段

#### T7.2 中文搜索
- **操作**: 搜索中文关键词
- **预期**: 正确匹配中文内容

#### T7.3 空结果
- **操作**: 搜索一个不存在的词
- **预期**: 显示空状态
- **截图**: 空搜索结果页

#### T7.4 搜索历史
- **操作**: 搜索后清空输入框 → 查看历史记录
- **预期**: 显示最近搜索词

#### T7.5 索引重建
- **验证**: iOS 日志 `[data] search index rebuilt: N articles`

---

### T8: 离线与网络恢复

#### T8.1 离线保存
- **操作**: 断网 → 分享一个 URL
- **预期**: 本地保存成功，状态 pending
- **验证**: iOS 日志 `[data] article saved`，无网络错误

#### T8.2 网络恢复自动同步
- **操作**: 恢复网络
- **预期**: 自动提交 pending 文章
- **验证**: iOS 日志 `[network] network status changed: available` → `processing N pending article(s)`

---

### T9: 设置页

#### T9.1 用户信息显示
- **操作**: 点击设置齿轮
- **截图**: 用户名、邮箱、订阅等级、配额进度

#### T9.2 配额显示
- **验证**: Articles saved X / Y 与数据库一致

---

### T10: Onboarding

#### T10.1 首次启动引导
- **操作**: 清除 app 数据 → 冷启动
- **预期**: 显示 4 页引导 + 权限页
- **截图**: 每一页引导页

---

## 测试执行方式

每个用例按以下流程执行：

1. **准备**: 确保环境就绪（后端运行、app 已安装最新版）
2. **操作**: 通过 Appium 执行点击/滑动/输入
3. **截图**: 操作前后各截一张
4. **日志**: 同时抓取 iOS 和 Go 日志
5. **数据库**: 必要时查询验证数据状态
6. **记录**: 将结果（截图 + 日志 + 发现的问题）写入测试报告

## 输出物

测试完成后生成：

1. **测试报告** (`docs/e2e-test-report.md`)
   - 每个用例的通过/失败状态
   - 截图证据
   - 关键日志摘录

2. **问题清单** (`docs/issues-and-improvements.md`)
   - Bug 列表（含复现步骤）
   - UI/UX 优化建议（含截图对比）
   - 内容质量问题（各来源的抓取效果）
   - 性能观察
