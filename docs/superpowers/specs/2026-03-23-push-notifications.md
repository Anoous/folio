# 推送通知 — Design Spec

> 日期：2026-03-23
> 状态：Approved
> 范围：APNs 远程推送 + 智能 Echo 调度

---

## 概述

后端智能调度推送：每小时检查哪些用户有到期 Echo 卡片且今天未回顾，选择具体卡片的 question 作为推送内容。APNs HTTP/2 远程推送，个性化内容。

## 架构

```
iOS 启动 → 注册 APNs → 上报 device token → POST /devices
                                                    ↓
Backend Cron (每小时) → 查询到期 Echo + 今日未回顾的用户
                                                    ↓
选择最早到期的 Echo 卡片 → "✦ {question}"
                                                    ↓
APNs HTTP/2 → 用户设备
                                                    ↓
用户点击 → 打开 App → Home Feed
```

## 后端

### 1. 设备注册 API

#### POST /api/v1/devices

**请求：**
```json
{ "token": "abc123...", "platform": "ios" }
```

**逻辑：** UPSERT — 同一 user_id + token 只保留一条，更新 updated_at。

**权限：** auth

### 2. DB 迁移 010

```sql
CREATE TABLE devices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    platform VARCHAR(10) NOT NULL DEFAULT 'ios',
    last_push_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, token)
);
CREATE INDEX idx_devices_user ON devices (user_id);
```

### 3. APNs Client

**文件：** `server/internal/client/apns.go`

- HTTP/2 client 直连 `api.push.apple.com` (production) / `api.sandbox.push.apple.com` (sandbox)
- Token-based auth：用 .p8 key 生成 JWT（和 StoreKit 共用 App Store Connect API key）
- `SendPush(deviceToken, title, body, badge string) error`
- Payload：`{"aps": {"alert": {"title": "Folio", "body": "✦ 还记得..."}, "sound": "default", "badge": 1}}`

### 4. Push Worker（Cron 任务）

**文件：** `server/internal/worker/push.go`

使用 asynq 的 cron 调度：每小时执行。

**逻辑：**
1. 查询所有有到期 Echo 卡片的用户：
   ```sql
   SELECT DISTINCT ec.user_id FROM echo_cards ec
   WHERE ec.next_review_at <= NOW()
   AND NOT EXISTS (
       SELECT 1 FROM echo_reviews er
       WHERE er.user_id = ec.user_id
       AND er.reviewed_at >= CURRENT_DATE
   )
   ```
2. 排除今天已推送过的：`devices.last_push_at >= CURRENT_DATE`
3. 对每个用户：选最早到期的 Echo 卡片的 question
4. 获取用户的 device tokens
5. 发送 APNs 推送：`"✦ {question}"`
6. 更新 `devices.last_push_at = NOW()`

每天每用户最多推 1 次。

### 5. 环境变量

```
APNS_KEY_ID=            # App Store Connect API Key ID
APNS_TEAM_ID=           # Apple Developer Team ID
APNS_KEY_PATH=          # Path to .p8 key file
APNS_SANDBOX=true       # true for dev, false for production
```

### 6. 文件结构

```
server/internal/
├── client/apns.go          # APNs HTTP/2 client
├── worker/push.go          # Cron push scheduler
├── repository/device.go    # devices table CRUD
├── api/handler/device.go   # POST /devices handler
└── domain/device.go        # Device struct
```

## iOS 端

### 1. 权限请求时机

**不在 onboarding 请求。** 在用户完成首次 Echo 交互后触发：

```swift
// In EchoCardView, after user taps "记得" or "忘了":
if !hasRequestedNotifications {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
        if granted {
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }
    hasRequestedNotifications = true // @AppStorage
}
```

### 2. Device Token 上报

**AppDelegate.swift：**
```swift
func application(_ app: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
    let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()
    Task { try? await APIClient.shared.registerDevice(token: tokenString) }
}
```

每次启动检查并更新（token 可能变化）。

### 3. DTO

```swift
struct RegisterDeviceRequest: Codable {
    let token: String
    let platform: String
}

func registerDevice(token: String) async throws {
    let body = RegisterDeviceRequest(token: token, platform: "ios")
    let _: StatusResponse = try await request(method: "POST", path: "/api/v1/devices", body: body)
}
```

### 4. 通知点击

点击通知 → 打开 App → 正常进入 Home。Echo 卡片已在 Feed 中，不需要 deep link。

### 5. Badge 清除

App 进入前台时清除 badge：
```swift
UIApplication.shared.applicationIconBadgeNumber = 0
```

## 不做

- Rich Notification（自定义通知 UI）
- 用户活跃时间学习（固定逻辑，每天最多 1 次）
- 通知偏好设置
- 静默推送
- Android 支持
