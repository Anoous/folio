# Launch Essentials: StoreKit Subscription + Push Notifications

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement real App Store subscription purchase (StoreKit 2) with server-side verification, and APNs remote push notifications with smart Echo scheduling.

**Architecture:** iOS: StoreKit 2 for purchases, APNs for push. Backend: Apple Server API for receipt verification, Apple Server Notifications V2 webhook for lifecycle events, asynq cron for daily push scheduling.

**Tech Stack:** Swift 5.9 / StoreKit 2 / UserNotifications / iOS 17.0 | Go 1.24 / Apple Server API / APNs HTTP/2 / asynq cron

**Specs:**
- `docs/superpowers/specs/2026-03-23-storekit-subscription.md`
- `docs/superpowers/specs/2026-03-23-push-notifications.md`

---

## File Map

### Part A: StoreKit Subscription

**Backend (new/modify):**
- `server/internal/client/apple.go` — Apple Server API client (JWT auth + transaction verification)
- `server/internal/service/subscription.go` — verification logic + webhook processing
- `server/internal/api/handler/subscription.go` — rewrite existing stub + add webhook
- `server/internal/api/router.go` — add webhook route
- `server/cmd/server/main.go` — wire dependencies
- `server/internal/config/config.go` — add Apple API env vars

**iOS (new/modify):**
- `ios/Folio/Data/Subscription/SubscriptionManager.swift` — StoreKit 2 manager
- `ios/Folio/Presentation/Settings/SettingsView.swift` — real purchase buttons
- `ios/Folio/App/FolioApp.swift` — inject SubscriptionManager

### Part B: Push Notifications

**Backend (new):**
- `server/internal/client/apns.go` — APNs HTTP/2 push client
- `server/internal/domain/device.go` — Device struct
- `server/internal/repository/device.go` — devices CRUD
- `server/internal/api/handler/device.go` — POST /devices
- `server/internal/worker/push.go` — cron push scheduler
- `server/migrations/010_devices.up.sql` — devices table
- `server/migrations/010_devices.down.sql`

**iOS (modify):**
- `ios/Folio/App/AppDelegate.swift` — APNs registration
- `ios/Folio/Data/Network/Network.swift` — registerDevice DTO + method
- `ios/Folio/Presentation/Home/EchoCardView.swift` — request notification permission after first review

---

## Part A: StoreKit Subscription

### Task 1: Backend — Apple Server API Client + Config

**Files:**
- Create: `server/internal/client/apple.go`
- Modify: `server/internal/config/config.go`

- [ ] **Step 1: Add Apple API config**

In `config.go`, add fields:
```go
AppleAPIKeyID    string // env: APPLE_API_KEY_ID
AppleAPIIssuerID string // env: APPLE_API_ISSUER_ID
AppleAPIKeyPath  string // env: APPLE_API_KEY_PATH
```

- [ ] **Step 2: Create client/apple.go**

```go
type AppleClient struct {
    keyID    string
    issuerID string
    key      *ecdsa.PrivateKey  // parsed from .p8
    bundleID string
    sandbox  bool
    httpClient *http.Client
}

func NewAppleClient(keyID, issuerID, keyPath, bundleID string, sandbox bool) (*AppleClient, error)
```

Methods:
- `generateJWT() (string, error)` — ES256 JWT for Apple Server API, 20min expiry
- `VerifyTransaction(ctx, transactionID string) (*TransactionInfo, error)` — GET `/inApps/v1/transactions/{id}`, parse JWS response, return transaction details
- `ParseNotificationPayload(signedPayload string) (*NotificationPayload, error)` — parse Apple webhook JWS

TransactionInfo struct:
```go
type TransactionInfo struct {
    TransactionID         string
    OriginalTransactionID string
    ProductID             string
    BundleID              string
    ExpiresDate           *time.Time
    RevocationDate        *time.Time
}
```

If `APPLE_API_KEY_PATH` is empty → create a mock client that always returns success (for dev/testing).

- [ ] **Step 3: Build and commit**

---

### Task 2: Backend — Subscription Service + Webhook

**Files:**
- Create: `server/internal/service/subscription.go`
- Modify: `server/internal/api/handler/subscription.go` (rewrite stub)
- Modify: `server/internal/api/router.go`
- Modify: `server/cmd/server/main.go`

- [ ] **Step 1: Create service/subscription.go**

```go
type SubscriptionService struct {
    appleClient *client.AppleClient
    userRepo    *repository.UserRepo
}
```

Methods:
- `VerifyAndActivate(ctx, userID, transactionID string) error` — call appleClient.VerifyTransaction → validate bundleID + productID + expiresDate → update user subscription to "pro" + subscription_expires_at
- `HandleWebhookEvent(ctx, signedPayload string) error` — parse payload → switch on notificationType: DID_RENEW → extend expiry, EXPIRED/REFUND/REVOKE → downgrade to free

- [ ] **Step 2: Rewrite handler/subscription.go**

Replace the 501 stub:

**HandleVerify** (POST /api/v1/subscription/verify):
- Parse body: `{"transaction_id": "...", "product_id": "..."}`
- Call service.VerifyAndActivate
- Return updated user subscription info

**HandleWebhook** (POST /api/v1/webhook/apple):
- Public endpoint (no JWT auth — Apple calls this)
- Parse body: `{"signedPayload": "..."}`
- Call service.HandleWebhookEvent
- Return 200 OK

- [ ] **Step 3: Add webhook route**

In router.go, OUTSIDE the JWT-protected group (public):
```go
r.Post("/api/v1/webhook/apple", deps.SubscriptionHandler.HandleWebhook)
```

- [ ] **Step 4: Wire in main.go**

```go
appleClient, _ := client.NewAppleClient(cfg.AppleAPIKeyID, cfg.AppleAPIIssuerID, cfg.AppleAPIKeyPath, cfg.AppleBundleID, isDev)
subscriptionService := service.NewSubscriptionService(appleClient, userRepo)
subscriptionHandler := handler.NewSubscriptionHandler(subscriptionService)
```

- [ ] **Step 5: Build and commit**

---

### Task 3: iOS — SubscriptionManager + Settings Integration

**Files:**
- Create: `ios/Folio/Data/Subscription/SubscriptionManager.swift`
- Modify: `ios/Folio/Presentation/Settings/SettingsView.swift`
- Modify: `ios/Folio/App/FolioApp.swift`
- Modify: `ios/Folio/Data/Network/Network.swift`

- [ ] **Step 1: Create SubscriptionManager**

```swift
import StoreKit

@Observable
@MainActor
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

    var yearlyProduct: Product? { products.first { $0.id.contains("yearly") } }
    var monthlyProduct: Product? { products.first { $0.id.contains("monthly") } }

    func fetchProducts() async { ... }
    func purchase(_ product: Product) async { ... }
    func checkEntitlements() async { ... }
    func restorePurchases() async { ... }
    func listenForTransactions() -> Task<Void, Never> { ... }

    private func verifyWithServer(_ transactionID: UInt64) async { ... }
}
```

Key flows:
- `purchase()`: `product.purchase()` → on `.success(let verification)` → extract transaction → `verifyWithServer(transaction.id)` → add to `purchasedProductIDs`
- `checkEntitlements()`: iterate `Transaction.currentEntitlements` → collect active subscriptions
- `listenForTransactions()`: `Transaction.updates` async for → verify new transactions
- `verifyWithServer()`: call `APIClient.shared.verifySubscription(transactionID:)`

- [ ] **Step 2: Add verify API method to Network.swift**

```swift
struct VerifySubscriptionRequest: Codable {
    let transactionId: String
    let productId: String
}

struct VerifySubscriptionResponse: Codable {
    let subscription: String
    let expiresAt: Date?
}

func verifySubscription(transactionID: UInt64, productID: String) async throws -> VerifySubscriptionResponse {
    let body = VerifySubscriptionRequest(transactionId: String(transactionID), productId: productID)
    return try await request(method: "POST", path: "/api/v1/subscription/verify", body: body)
}
```

- [ ] **Step 3: Update SettingsView**

Replace mock upgrade button with real StoreKit purchase:
- Show `subscriptionManager.yearlyProduct?.displayPrice` instead of hardcoded "¥98"
- Tap → `subscriptionManager.purchase(product)`
- Show ProgressView during purchase
- "恢复购买" → `subscriptionManager.restorePurchases()`
- After purchase success → refresh `authViewModel` user data

- [ ] **Step 4: Inject in FolioApp.swift**

```swift
@State private var subscriptionManager = SubscriptionManager()

// In body, add to environment:
.environment(subscriptionManager)

// On appear:
.task {
    await subscriptionManager.fetchProducts()
    await subscriptionManager.checkEntitlements()
    _ = subscriptionManager.listenForTransactions()
}
```

- [ ] **Step 5: xcodegen + build + commit**

---

## Part B: Push Notifications

### Task 4: Backend — Devices Table + API

**Files:**
- Create: `server/migrations/010_devices.up.sql`
- Create: `server/migrations/010_devices.down.sql`
- Create: `server/internal/domain/device.go`
- Create: `server/internal/repository/device.go`
- Create: `server/internal/api/handler/device.go`
- Modify: `server/internal/api/router.go`
- Modify: `server/cmd/server/main.go`

- [ ] **Step 1: Create migration 010**

```sql
-- 010_devices.up.sql
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

-- 010_devices.down.sql
DROP TABLE IF EXISTS devices;
```

Apply to dev DB.

- [ ] **Step 2: Create domain + repo + handler**

Standard CRUD pattern. Handler: POST /api/v1/devices — UPSERT (on conflict update updated_at).

- [ ] **Step 3: Register route + wire**

Protected group: `r.Post("/devices", deps.DeviceHandler.HandleRegister)`

- [ ] **Step 4: Build and commit**

---

### Task 5: Backend — APNs Client + Push Worker

**Files:**
- Create: `server/internal/client/apns.go`
- Create: `server/internal/worker/push.go`
- Modify: `server/internal/config/config.go`
- Modify: `server/internal/worker/server.go`
- Modify: `server/cmd/server/main.go`

- [ ] **Step 1: Add APNs config**

```go
APNSKeyID   string // env: APNS_KEY_ID
APNSTeamID  string // env: APNS_TEAM_ID
APNSKeyPath string // env: APNS_KEY_PATH (same .p8 as Apple API)
APNSSandbox bool   // env: APNS_SANDBOX
```

- [ ] **Step 2: Create client/apns.go**

APNs HTTP/2 client:
- `SendPush(ctx, deviceToken, title, body string) error`
- Uses `golang.org/x/net/http2` or standard `net/http` with HTTP/2
- JWT auth with .p8 key (ES256, same as Apple Server API)
- Endpoint: `api.push.apple.com` (prod) / `api.sandbox.push.apple.com` (dev)

- [ ] **Step 3: Create worker/push.go**

Cron task registered with asynq scheduler (every hour):

```go
func (h *PushHandler) ProcessTask(ctx context.Context, t *asynq.Task) error {
    // 1. Find users with due echo cards AND no reviews today AND not pushed today
    // 2. For each: pick earliest due echo card
    // 3. Send APNs push: "✦ {question}"
    // 4. Update devices.last_push_at
}
```

SQL for eligible users:
```sql
SELECT DISTINCT ec.user_id, ec.question
FROM echo_cards ec
JOIN devices d ON d.user_id = ec.user_id
WHERE ec.next_review_at <= NOW()
AND (d.last_push_at IS NULL OR d.last_push_at < CURRENT_DATE)
AND NOT EXISTS (
    SELECT 1 FROM echo_reviews er
    WHERE er.user_id = ec.user_id AND er.reviewed_at >= CURRENT_DATE
)
ORDER BY ec.next_review_at ASC
```

- [ ] **Step 4: Register cron in server.go / main.go**

Use asynq's `Scheduler` to register hourly cron:
```go
scheduler.Register("@every 1h", asynq.NewTask("push:echo", nil))
```

- [ ] **Step 5: Build and commit**

---

### Task 6: iOS — Push Registration + Echo Permission

**Files:**
- Modify: `ios/Folio/App/AppDelegate.swift`
- Modify: `ios/Folio/Data/Network/Network.swift`
- Modify: `ios/Folio/Presentation/Home/EchoCardView.swift`
- Modify: `ios/Folio/App/FolioApp.swift`

- [ ] **Step 1: Add push registration to AppDelegate**

```swift
func application(_ app: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
    let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()
    Task { try? await APIClient.shared.registerDevice(token: tokenString) }
}

func application(_ app: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    // Silent — push is optional
}
```

- [ ] **Step 2: Add registerDevice to Network.swift**

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

- [ ] **Step 3: Request permission after first Echo review**

In `EchoCardView.swift`, after user taps "记得" or "忘了" and the review callback completes:

```swift
@AppStorage("has_requested_notifications") private var hasRequestedNotifications = false

// After review:
if !hasRequestedNotifications {
    hasRequestedNotifications = true
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
        if granted {
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }
}
```

- [ ] **Step 4: Clear badge on foreground**

In `FolioApp.swift`, on `scenePhase == .active`:
```swift
UIApplication.shared.applicationIconBadgeNumber = 0
```

- [ ] **Step 5: xcodegen + build + commit**

---

### Task 7: End-to-End Test

- [ ] **Step 1: Test subscription flow (StoreKit)**

Note: Real StoreKit testing requires StoreKit Configuration file or Sandbox tester in App Store Connect. For dev, verify:
- SubscriptionManager.fetchProducts() returns 2 products (if StoreKit config file exists) or empty (if not configured yet)
- Settings shows real prices or graceful fallback
- POST /subscription/verify endpoint responds (even if mock Apple client)

- [ ] **Step 2: Test push flow**

- POST /api/v1/devices with a test token → verify DB insert
- Run push worker manually → verify it queries eligible users
- Verify APNs client doesn't crash with sandbox config

- [ ] **Step 3: Test on simulator**

- Install app, navigate to Settings → verify upgrade buttons
- Complete an Echo review → verify notification permission dialog appears
- Verify badge clearing on app foreground

- [ ] **Step 4: Commit any fixes**

---

## Execution Order

```
Task 1 (Apple client + config) → Task 2 (subscription service + webhook)
    → Task 3 (iOS SubscriptionManager + Settings)
        → Task 4 (devices table + API)
            → Task 5 (APNs client + push worker)
                → Task 6 (iOS push registration + Echo permission)
                    → Task 7 (E2E test)
```

Tasks 1-3 (StoreKit) and 4-6 (Push) are independent subsystems but share Apple API key config (Task 1).
