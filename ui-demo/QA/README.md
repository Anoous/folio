# UI 验收记录

- 参考设计：`../../designs/chatgpt-ui-prototype-2026-07-26/`
- 运行设备：iPhone 15 Pro Simulator
- 逻辑尺寸：393 × 852 pt
- 系统：iOS 26.5
- 状态栏时间：9:41
- 数据来源：全部为本地 Mock 数据
- 交互验证：7 条 XCUITest，覆盖默认登录/提问流程、洞察/原文本页双向切换与单层返回、资料库筛选、15 篇文章逐篇打开，以及 Liquid Glass 收藏 Dock 的 URL 输入、发送、成功反馈和新行插入

`Screenshots/01-welcome.png` 至 `Screenshots/10-settings.png` 分别对应 10 张参考设计。

`Motion/liquid-toolbar-demo.mp4` 保留早期“＋”展开菜单的动效基线；当前单层变形收藏 Dock 以最新 XCUITest 和 Simulator 实机截图为准，视频待重新录制。

`Motion/article-inline-switch.mp4` 记录文章顶部保持不动、正文从洞察连续切换到原文。
