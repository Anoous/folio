# StoreKit 订阅 — Design Spec

> 日期：2026-03-23
> 状态：Approved
> 范围：StoreKit 2 订阅购买 + 服务端验证

---

## 概述

实现真实的 App Store 订阅购买流程。iOS 端使用 StoreKit 2，购买成功后发送 transaction 到后端验证，后端调用 Apple Server API 确认并更新用户订阅状态。支持 Apple Server Notifications V2 自动处理续费/退款/过期。

## 产品配置

| 产品 ID | 类型 | 价格 | 试用 |
|---------|------|------|------|
| `com.folio.app.pro.yearly` | Auto-Renewable Subscription | ¥98/年 ($12.99) | 7 天免费 |
| `com.folio.app.pro.monthly` | Auto-Renewable Subscription | ¥12/月 ($1.49) | 无 |

Subscription Group: `Folio Pro`

## iOS 端

### 1. SubscriptionManager

**文件：** `ios/Folio/Data/Subscription/SubscriptionManager.swift`

```swift
@Observable
class SubscriptionManager {
    var products: [Product] = []
    var purchasedProductIDs: Set<String> = []
    var isPro: Bool { !purchasedProductIDs.isEmpty }
    var isLoading = false
    var errorMessage: String?

    private let productIDs = [
        "com.folio.app.pro.yearly",
        "com.folio.app.pro.monthly"
    ]
}
```

**方法：**
- `fetchProducts()` — `Product.products(for: productIDs)`，启动时调用
- `purchase(_ product: Product)` — `product.purchase()` → 获取 Transaction → `verifyWithServer(transactionID)` → 更新 `purchasedProductIDs`
- `checkEntitlements()` — 遍历 `Transaction.currentEntitlements`，更新 `purchasedProductIDs`
- `listenForTransactions()` — `Transaction.updates` async sequence，后台监听交易变化
- `restorePurchases()` — `AppStore.sync()`
- `verifyWithServer(_ transactionID: UInt64)` — 调用 `POST /subscription/verify` 发送 transaction ID

**错误处理：**
- 用户取消 → 静默
- 购买失败 → `errorMessage = "购买失败，请重试"`
- 验证失败 → 本地仍标记为 Pro（StoreKit 2 本地验证兜底），下次启动重试服务端验证

### 2. Settings 升级页改造

**修改：** `ios/Folio/Presentation/Settings/SettingsView.swift`

当前"升级 Pro — ¥98/年"按钮是 mock alert。改为：
- 从 `SubscriptionManager.products` 获取真实价格（`product.displayPrice`）
- 年订阅按钮："升级 Pro — {年价格}"
- 月订阅文字："或 {月价格}/月 · 随时取消"
- 点击 → `subscriptionManager.purchase(product)`
- 购买中显示 ProgressView
- "恢复购买"按钮 → `subscriptionManager.restorePurchases()`

### 3. 环境注入

在 `FolioApp.swift` 中创建 `SubscriptionManager` 实例，注入为环境对象。启动时调用 `fetchProducts()` + `checkEntitlements()` + `listenForTransactions()`。

### 4. Pro 状态同步

购买成功/恢复后：
- 更新 `AuthViewModel` 的用户订阅状态
- 刷新 UserDefaults 中的 `isProUser` flag（SharedDataManager 用）
- 后端已通过 `/subscription/verify` 更新了 `users.subscription`

## 后端

### 1. POST /subscription/verify（改造现有）

**请求：**
```json
{
  "transaction_id": "2000000123456789",
  "original_transaction_id": "2000000123456789",
  "product_id": "com.folio.app.pro.yearly"
}
```

**逻辑：**
1. 调用 Apple App Store Server API: `GET /inApps/v1/transactions/{transactionId}`
2. 验证 JWS 签名（使用 Apple Root CA）
3. 确认 `bundleId` 匹配、`productId` 正确、`expiresDate` 在未来
4. 更新 `users.subscription = "pro"` + `subscription_expires_at = expiresDate`
5. 返回 `{ "subscription": "pro", "expires_at": "..." }`

**Apple Server API 认证：**
- 需要 App Store Connect API Key（p8 文件）
- 环境变量：`APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_API_KEY_PATH`
- 生成 JWT token 签署 API 请求

### 2. POST /webhook/apple（新端点）

**路由：** `POST /api/v1/webhook/apple`（公开，无 auth，Apple 签名验证）

**处理事件：**
- `DID_RENEW` → 更新 `subscription_expires_at`
- `EXPIRED` → `subscription = "free"`, `subscription_expires_at = NULL`
- `DID_FAIL_TO_RENEW` → 标记（暂不降级，等过期）
- `REFUND` → `subscription = "free"`
- `REVOKE` → `subscription = "free"`

**验证：**
- 解析 JWS (`signedPayload`)
- 用 Apple Root CA 证书验证签名
- 提取 `notificationType` + `transactionInfo`

### 3. 文件结构

```
server/internal/
├── client/apple.go         # Apple Server API client (JWT auth + transaction verification)
├── service/subscription.go # 验证逻辑 + webhook 处理
├── api/handler/subscription.go # 改造现有 + webhook handler
```

### 4. 环境变量（新增）

```
APPLE_API_KEY_ID=           # App Store Connect API Key ID
APPLE_API_ISSUER_ID=        # Issuer ID from App Store Connect
APPLE_API_KEY_PATH=         # Path to .p8 key file
APPLE_BUNDLE_ID=com.7WSH9CR7KS.folio.app  # 已有
```

### 5. 定时检查（可选）

Cron job 每日检查 `subscription_expires_at < NOW()` 的用户，降级为 free。作为 webhook 的兜底。

## DB 变更

无新 migration。`users` 表已有 `subscription` 和 `subscription_expires_at` 字段。

## 不做

- 促销优惠码
- 家庭共享
- Introductory offers（除 7 天试用外）
- 自定义 paywall 页面（复用 Settings 对比表）
- 订阅管理页面（跳转到 App Store 系统页）
