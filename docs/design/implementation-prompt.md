# Folio v3.0 实现提示词

> 复制以下内容作为 AI 会话的首条消息，开始实现。

---

## 提示词

你是一位资深 iOS 全栈工程师，同时精通 Go 后端开发。你即将基于完整的 UI 设计原型，实现 Folio v3.0 的全部功能。

### 项目背景

Folio（页集）是一款本地优先的个人知识记忆 iOS App。核心定位：**Folio 记得。然后帮你也记得。**

三个动词：
- **存** — 链接/截图/语音/高亮/手动输入，零摩擦流入。AI 自动阅读、理解、提炼洞察摘要
- **记** — 间隔重复 + 主动回忆（Echo）：Folio 在你快忘时提问，10 秒一次
- **用** — RAG 问答 + 语义搜索 + 知识简报：自然语言提问，综合收藏回答

### 你需要阅读的文件（按顺序）

**必读：设计与交互**
1. `docs/design/prototypes/README.md` — 交互流程总览（从启动到每个分支的完整层次结构）
2. `docs/design/ui-design-brief.md` — UI 设计任务书（设计系统 token、颜色、字体、动画参数）
3. `docs/design/product-vision.md` — 产品愿景
4. `docs/superpowers/specs/2026-03-22-product-vision-redesign.md` — 设计决策 Spec（订阅模型、冷启动策略）

**必读：现有代码**
5. `CLAUDE.md` — 项目技术架构、仓库结构、构建命令、开发环境
6. `ios/project.yml` — XcodeGen 项目定义
7. `ios/Folio/App/FolioApp.swift` — App 入口
8. `ios/Folio/Presentation/Home/HomeView.swift` — 当前 Home 页实现
9. `ios/Folio/Data/Network/Network.swift` — APIClient + DTO
10. `server/internal/api/router.go` — 当前 API 路由
11. `server/internal/domain/` — 领域模型

**参考：设计原型**（HTML 高保真原型，浏览器打开查看交互效果）
- `docs/design/prototypes/01-home-feed.html` — Home Feed 完整体验
- `docs/design/prototypes/02-echo-interaction.html` — Echo 回忆交互
- `docs/design/prototypes/03-search-and-qa.html` — 搜索 + RAG 问答
- `docs/design/prototypes/04-reader-full.html` — Reader 阅读页
- `docs/design/prototypes/05-knowledge-map.html` — 知识地图
- `docs/design/prototypes/06-onboarding.html` — 引导流程
- `docs/design/prototypes/07-settings.html` — 设置页
- `docs/design/prototypes/08-cold-start.html` — 冷启动旅程
- `docs/design/prototypes/09-widget.html` — 锁屏/主屏 Widget
- `docs/design/prototypes/10-transitions.html` — 转场动画

### 实现范围

基于原型和现有代码，按以下优先级实现：

**P0 — 必须实现（MVP 升级）**

| 功能 | iOS 端 | 后端 | 原型参考 |
|------|--------|------|----------|
| Home Feed 升级 | 洞察级摘要（pull quote 样式）、时间分组、Hero 文章、处理状态 | AI prompt 调整返回洞察格式 | 01 |
| Reader 升级 | 洞察摘要折叠区、阅读进度条、更多操作 Sheet | 无 | 04 |
| Onboarding 更新 | 4 页 + 登录 + 开始，文案改为"Folio 记得" | 无 | 06 |
| 订阅重构 | 两层（Free/Pro），砍掉 Pro+ | DB migration: pro_plus → pro | 07 |
| 洞察摘要降级为 Free | 去除 AI 摘要的付费墙 | 取消订阅检查 | 07、08 |

**P1 — 核心差异化**

| 功能 | iOS 端 | 后端 | 原型参考 |
|------|--------|------|----------|
| Echo 主动回忆 | RecallCard SwiftData 模型、Echo 卡片 UI、记得/忘了反馈、间隔重复算法 | Echo 卡片生成 API（基于现有 key_points）| 01、02 |
| 高亮标注 | 长按选中→高亮、SwiftData 存储、高亮列表 | 高亮同步 API | 04 |
| RAG 问答 | 搜索页升级：短查询 + 长问句判断、RAG 回答 UI、来源溯源、跟进对话 | 向量嵌入 + RAG 端点 | 03 |
| 知识地图 | 统计页 UI、主题分布图、Echo 吸收率 | 统计聚合 API | 05 |
| 冷启动策略 | 里程碑检测（1/3/5/10/11 篇）、引导提示、试用期逻辑 | 试用期状态管理 | 08 |

**P2 — 增强体验**

| 功能 | iOS 端 | 后端 | 原型参考 |
|------|--------|------|----------|
| Widget | 锁屏 Widget（小/中）、主屏 Widget（小/中）| Widget 数据端点 | 09 |
| 转场动画 | push 动画、Echo settle/exit、搜索展开、Sheet 弹出 | 无 | 10 |
| 截图收藏 | iOS Vision OCR + Share Extension | OCR 内容入库 | — |
| 语音捕捉 | Speech framework + 快捷指令 | 语音转文字入库 | — |
| 笔记输入 | 搜索框输入非 URL → 保存为知识碎片 | 笔记 CRUD API | 03 |

### 技术约束

**iOS 端**
- Swift 5.9+ / SwiftUI / SwiftData / iOS 17.0+
- 单 NavigationStack，没有 TabView，只有 3 个页面（Home、Reader、Settings）
- 新功能不加新页面，全部融入现有界面
- XcodeGen 管理项目，新增文件后必须 `xcodegen generate`
- 字体：系统字体（SF Pro）用于 UI，霞鹜文楷用于文章标题/洞察/阅读正文（需作为 App 内嵌字体）
- 动画参数严格使用设计系统 Motion tokens

**后端**
- Go 1.24+ / chi v5 / asynq / pgx v5 / PostgreSQL 16
- 现有架构：Handler → Service → Repository → Domain
- AI 分析使用 DeepSeek API，需调整 prompt 返回洞察格式
- 向量嵌入方案待定（端侧 vs 云端），RAG 实现需要技术 spike
- 间隔重复算法待定（SM-2 / FSRS），需要原型验证

**设计规范**
- 暖白背景 `#FAF9F6`，不是冷白 `#FFFFFF`
- 几乎单色调，accent 蓝只出现在最值得注意的地方
- 洞察摘要是 pull quote 样式（衬线斜体 + 左侧竖线），不是普通描述文字
- Echo 卡片居中排版 + 浅灰背景，不是普通列表项
- 大量留白，每个内容有呼吸空间
- 不做清单：不做笔记编辑器、社交功能、RSS、协作、推荐、阅读任务

### 实现策略

1. **先读完所有设计文件**，理解全局交互流程和每个状态
2. **从 P0 开始**，每个功能写完后运行测试
3. **iOS 和后端同步推进**，先定 API 契约再分别实现
4. **每完成一个功能模块**，对照原型检查 UI 一致性
5. **不要过度工程**，先实现核心流程再优化边界情况

### 开始

请先阅读上述所有文件，然后：
1. 输出你对现有代码和设计的理解（确认你读对了）
2. 给出 P0 的实现计划（任务拆解 + 依赖关系 + 建议顺序）
3. 等我确认后开始实现
