# UI 验收记录

- 参考设计：`../../designs/chatgpt-ui-prototype-2026-07-26/`
- 运行设备：iPhone 15 Pro Simulator
- 逻辑尺寸：393 × 852 pt
- 系统：iOS 26.5
- 状态栏时间：9:41
- 数据来源：全部为本地 Mock 数据
- 自动验证：3 条单元测试与 16 条 XCUITest，覆盖首次保存、接收/处理/失败/重试状态、离线恢复、筛选、分页、删除/撤销、15 篇文章逐篇打开、邮箱登录、设备退出与会话恢复

`Screenshots/01-welcome.png` 至 `Screenshots/10-settings.png` 分别对应 10 张参考设计。

`Motion/liquid-toolbar-demo.mp4` 保留早期“＋”展开菜单的动效基线；当前单层变形收藏 Dock 以最新 XCUITest 和 Simulator 实机截图为准，视频待重新录制。

`Motion/article-inline-switch.mp4` 记录文章顶部保持不动、正文从洞察连续切换到原文。

`Motion/article-ai-ask-interaction.mp4` 记录文章内 AI 输入框随阅读手势隐藏与恢复、示例提问以及回答插入正文的完整过程。

`Motion/reliable-capture-foundations.mp4` 记录冷启动登录、空资料库、首次收藏、服务端已接收反馈，以及正文处理完成的完整闭环。
