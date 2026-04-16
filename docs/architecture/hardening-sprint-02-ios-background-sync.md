# Hardening Sprint 02

更新时间：2026-04-15

## 目标

补齐 iOS 分享扩展到后台同步的真正闭环，让“分享后不打开主 App”也有机会完成云端提交。

本轮只解决后台同步链路，不扩展新产品能力。

## 当前问题

之前的实现存在三个根本缺口：

1. `OfflineQueueManager.registerBackgroundTask()` 只注册，不执行同步。
2. 主 App 没有稳定的后台任务调度入口，分享扩展写入后仍依赖前台 `scenePhase == .active` 才触发同步。
3. 主 App `Info.plist` 缺少 `BGTaskSchedulerPermittedIdentifiers` 和 `UIBackgroundModes = processing`，系统会直接拒绝后台任务注册。

## 设计

### 1. 抽离可测试的后台同步协调器

新增 `BackgroundSyncCoordinator`，职责只做三件事：

- 判断本地是否有 `pending` / `clientReady` 文章
- 判断当前是否具备登录态（本轮以 keychain token 是否存在为准）
- 在满足条件时冷启动 `ModelContainer` 和 `SyncService`，执行一次 `incrementalSync()`

这样后台任务逻辑不再依赖 UI 生命周期，也不依赖已存在的 `SyncService` 实例。

### 2. 后台任务处理器只负责系统接线

`OfflineQueueManager` 保留网络状态与 pending 计数职责，同时补上：

- 可替换的 `backgroundTaskSubmitter`，用于单元测试
- 可替换的 `backgroundSyncAction`，用于把系统 BGTask 和纯同步逻辑解耦
- 真实的 `BGProcessingTask` handler：
  - 被系统唤醒后执行后台同步
  - 完成后调用 `setTaskCompleted(success:)`
  - 立即重新提交下一次后台任务，保持链路持续可用

### 3. 统一共享容器初始化

将 App Group `ModelContainer` 的构建统一收口到 `DataManager.createSharedContainer()`，由：

- `FolioApp`
- `ShareViewController`
- `BackgroundSyncCoordinator`

共同复用，避免多处复制配置时逐渐漂移。

### 4. 系统前置条件补齐

主 App `Info.plist` 必须声明：

- `BGTaskSchedulerPermittedIdentifiers = com.folio.article-processing`
- `UIBackgroundModes = processing`

否则后台任务不会真正生效。

## 验收标准

- 后台任务注册不再被系统拒绝
- 有 pending/clientReady 本地条目且存在登录态时，后台任务可执行 `incrementalSync`
- 无登录态或无待同步条目时，后台执行器会快速跳过
- 相关单测通过

## 剩余边界

- iOS 后台调度仍由系统决定，不保证“立即上传”
- 如果用户强杀主 App，系统可能延迟甚至不再调度后台任务
- 本轮没有补 Share Extension 侧的搜索索引刷新、订阅补偿重试、失败重试语义修正

这意味着本轮完成后，产品会从“必须回前台才同步”提升到“具备真实后台补偿能力”，但还不是完全实时系统。
