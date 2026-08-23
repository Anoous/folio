# Folio UI Demo

这是基于 `designs/chatgpt-ui-prototype-2026-07-26/` 最终 10 张高保真稿实现的独立 SwiftUI 原型。

## 运行

```bash
cd ui-demo
xcodegen generate
open FolioUIDemo.xcodeproj
```

默认从欢迎页进入，首次登录会进入空资料库并引导完成第一条收藏；通过 `-demoScreen library` 直接启动时保留完整样例库用于逐屏验收。所有页面使用 Mock 数据并可点击浏览，登录、Liquid Glass 底部工具栏、快速收藏、文章状态、原文/洞察、证据、提问建议、来源、筛选、删除撤销、设备会话和返回按钮均已连接到统一状态。

实现采用纯 SwiftUI（iOS 26 / Swift 6.2），不包含后端、网络请求或第三方运行时依赖。中文编辑字体为 Noto Serif SC，授权文件位于 `FolioUIDemo/Resources/Licenses/`；引导插画和头像是为本原型生成的本地资源。

## P0 功能状态

- [x] 分享或输入链接收藏网页（原有功能，保持现有交互）
- [x] 正文阅读模式（原有功能，保持原文/洞察切换和阅读外观）
- [x] 原文高亮（本次完成：选择正文后可直接高亮）
- [x] 轻量笔记（本次完成：支持文章笔记和高亮笔记）
- [x] 高亮与笔记搜索（本次完成：从资料库搜索并回到对应文章段落）
- [x] 同步状态与最小导出（本次完成：展示注释同步状态，并通过系统分享导出 Markdown）
- [x] 当前文章 AI 解读（原有功能，保留洞察与文内提问）

以上是 UI Demo 的完成状态。注释同步目前使用本地 Mock 状态演示，尚未接入真实账号、云端存储或跨设备同步。

录屏验收已知问题：iOS 26 中文键盘编辑高亮笔记后，当前需要先点“完成”关闭面板，再重新打开，才能顺畅触达底部 Markdown 导出；数据与导出闭环正常，收键盘路径仍待优化。

## 动效与交互

- 底部导航使用 `GlassEffectContainer`、`glassEffectID` 和 matched glass transition；当前 Tab 是短胶囊，未选中项与“＋”保持等大的圆形比例。
- “＋”会在原位置吸收导航并连续变形成 URL 发送框；发送时原地展示“正在收藏 / 已收藏”，随后收回为紧凑 Dock，不增加第二层底栏或跳转成功页。
- 收藏状态机覆盖已接收、等待处理、处理中、完成和失败；重复 URL 不创建第二份内容，离线、容量不足与请求超时不会误报成功。
- 资料库支持下拉刷新、状态筛选、分批加载、左滑删除与 5 秒撤销；失败或部分完成的内容可从左侧操作重试。
- 设置页的“可靠性演示”可切换离线、容量已满、下次保存超时和下次处理失败，用于稳定复现恢复路径。
- 邮箱登录包含验证码步骤；退出登录保留云端资料，设备会话可以单独撤销，账号删除会先说明范围和 7 天撤销期。
- 资料库卡片使用 matched navigation transition 展开为文章详情页，默认显示原文，返回时沿原路径收回。
- 文章阅读外观支持四种柔和背景色与三种字体即时切换，并统一覆盖原文、洞察和证据内容；思源宋体随 App 打包并保留 SIL OFL 1.1 许可证，系统黑体和系统圆体直接使用 iOS 系统字体。
- 原文/洞察属于同一个文章详情页：默认原文在左，洞察作为增强层在右；顶部信息保持原位，仅正文以 12pt 位移加交叉淡化切换，证据面板支持半屏与全屏拖拽。
- 按压反馈、选择触觉和 Reduce Motion / Reduce Transparency 已统一处理。

## 逐屏验收入口

可向 App 传入 `-demoScreen` 启动参数。参数只决定初始页面，启动后仍可正常跳转和交互：

```text
welcome
library
reader
insight
evidence
ask-home
ask-answer
ask-insufficient
share-success
settings
```

例如：

```bash
xcrun simctl launch booted com.folio.uidemo -demoScreen insight
```

## 交互测试

```bash
xcodebuild test \
  -project FolioUIDemo.xcodeproj \
  -scheme FolioUIDemo \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

单元测试覆盖收藏幂等、失败不入库、删除撤销和重新登录恢复。UI 测试覆盖冷启动首次收藏、离线恢复、处理失败重试、资料库筛选/分页/删除撤销、高亮与笔记搜索、原生选词笔记、同步状态与 Markdown 导出，以及既有的文章问答、阅读外观和导航流程。

## 验收截图

`QA/Screenshots/` 保存了 iPhone 15 Pro（393 × 852 pt）上的 10 个逐屏运行截图，文件名与设计稿编号一一对应。

`QA/Motion/liquid-toolbar-demo.mp4` 是 8 秒交互验收录屏，覆盖 Liquid Glass 工具栏比例、Tab 空间切换与快速收藏展开。

`QA/Motion/article-inline-switch.mp4` 是洞察切换到原文的本页过渡验收录屏。

`QA/Motion/highlight-note-search-export.mp4` 是高亮与笔记闭环录屏，覆盖资料库搜索、打开原文、原生选词、添加高亮笔记、同步状态和 Markdown 系统分享。
