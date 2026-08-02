# Folio UI Demo

这是基于 `designs/chatgpt-ui-prototype-2026-07-26/` 最终 10 张高保真稿实现的独立 SwiftUI 原型。

## 运行

```bash
cd ui-demo
xcodegen generate
open FolioUIDemo.xcodeproj
```

默认从欢迎页进入，所有页面使用 Mock 数据并可点击浏览。登录、Liquid Glass 底部工具栏、快速收藏、文章、原文/洞察、证据、提问建议、来源、筛选、设置项和返回按钮均已连接到统一导航状态。

实现采用纯 SwiftUI（iOS 26 / Swift 6.2），不包含后端、网络请求或第三方运行时依赖。中文编辑字体为 Noto Serif SC，授权文件位于 `FolioUIDemo/Resources/Licenses/`；引导插画和头像是为本原型生成的本地资源。

## 动效与交互

- 底部导航使用 `GlassEffectContainer`、`glassEffectID` 和 matched glass transition；当前 Tab 是短胶囊，未选中项与“＋”保持等大的圆形比例。
- “＋”会连续变形成“链接 / 笔记 / 关闭”，再从同一位置缩放进入保存结果页。
- 资料库卡片使用 matched navigation transition 展开为文章详情页，默认显示原文，返回时沿原路径收回。
- 洞察/原文属于同一个文章详情页：顶部信息保持原位，仅正文以 12pt 位移加交叉淡化切换；证据面板支持半屏与全屏拖拽。
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

UI 测试覆盖默认登录与提问流程、文章洞察/原文本页双向切换与单层返回、资料库筛选，以及快速收藏工具栏的展开与完成返回。

## 验收截图

`QA/Screenshots/` 保存了 iPhone 15 Pro（393 × 852 pt）上的 10 个逐屏运行截图，文件名与设计稿编号一一对应。

`QA/Motion/liquid-toolbar-demo.mp4` 是 8 秒交互验收录屏，覆盖 Liquid Glass 工具栏比例、Tab 空间切换与快速收藏展开。

`QA/Motion/article-inline-switch.mp4` 是洞察切换到原文的本页过渡验收录屏。
