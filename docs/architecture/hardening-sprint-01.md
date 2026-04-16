# Hardening Sprint 01

更新时间：2026-04-15

## 目标

本轮只做生产级加固，不扩功能。优先解决三类问题：

1. `reader-service` 的 SSRF 防护不足。
2. API 限流在反向代理场景下错误识别客户端来源。
3. 默认测试入口 `go test ./...` 依赖外网真实站点，不稳定。

## 范围

### 1. Reader 抓取安全

当前 `reader-service` 仅对原始 URL 做字符串级黑名单判断，存在以下风险：

- 域名解析后落到私网、环回、链路本地、ULA IPv6。
- 首跳 URL 合法，但 30x 重定向到内部地址。
- 未来维护时缺少独立、可测试的安全策略模块。

本轮目标：

- 将 URL 校验拆到独立安全模块。
- 在发起抓取前对目标 URL 做如下校验：
  - 仅允许 `http/https`
  - 拒绝本地 hostname 与 `.local`
  - 拒绝直接私网/保留网段 IP
  - 对 hostname 做 DNS 解析，并拒绝解析结果中的私网/保留地址
- 增加抓取前重定向预检：
  - 手动跟踪有限跳数的 `Location`
  - 每一跳都重复 URL 与 DNS 校验
  - 将最终安全 URL 传给 reader client

非目标：

- 不在本轮引入专用 egress proxy / sandbox 网络隔离。
- 不改动外部 `@vakra-dev/reader` 库本身。

### 2. API 限流来源识别

当前限流直接读取 `RemoteAddr`。在 Caddy/Nginx/Cloudflare Tunnel 后面时，所有请求可能共享一个代理 IP，导致：

- 多用户串桶
- 限流失真
- 运维上难以解释

本轮目标：

- 抽出客户端来源识别函数。
- 只在“可信代理”前提下解析 `X-Forwarded-For` / `X-Real-IP`。
- 默认策略：
  - 公网直连：只信 `RemoteAddr`
  - 代理来源是 loopback / RFC1918 / ULA：可信代理头
- 限流测试覆盖：
  - 公网来源时忽略伪造头
  - 可信代理来源时按真实客户端 IP 限流

非目标：

- 不在本轮引入 Redis 分布式限流。
- 不实现按用户 ID / device ID 的业务限流。

### 3. 测试稳定性

当前 `server/internal/client/jina_integration_test.go` 默认参与 `go test ./...`，直接访问真实外网站点，导致测试受第三方站点行为影响。

本轮目标：

- 将外网依赖测试移出默认测试入口。
- 默认 `go test ./...` 必须稳定通过。
- 保留显式运行方式，用于人工验证第三方抓取能力。

建议方式：

- 为该文件增加 `integration` build tag。
- 文档中标明运行命令：
  - `go test -tags=integration ./internal/client -run TestJina...`

## 实施顺序

1. 先写 reader-service 安全测试，覆盖 DNS 后私网地址、IPv6 私网、重定向到私网。
2. 实现安全模块与抓取前预检，跑 Node 测试。
3. 先写 Go 限流测试，覆盖可信/不可信代理。
4. 实现代理感知客户端来源识别，跑 Go 测试。
5. 将外网集成测试移出默认入口，恢复 `go test ./...` 稳定。
6. 汇总结果与剩余风险。

## 验收标准

### Reader 安全

- `reader-service` 测试覆盖并通过：
  - 解析后 `127.0.0.1`
  - 解析后 `10.0.0.0/8`
  - 解析后 `fc00::/7`、`fe80::/10`
  - 首跳外网，重定向到私网
  - 合法外网 URL 仍可通过

### API 限流

- Go 单测覆盖并通过：
  - 公网来源 + 伪造 `X-Forwarded-For` 不应绕过限流
  - 可信代理来源 + 不同 `X-Forwarded-For` 应视为不同客户端
  - 可信代理来源 + 相同客户端 IP 应命中同一限流桶

### 测试入口

- `cd server && go test ./...` 通过
- `cd server/reader-service && npm test` 通过

## 剩余风险

本轮完成后，抓取链路仍然不是“零风险 SSRF”：

- 外部 reader 库内部如果自行发起额外跳转或二次请求，我们无法完全拦截。
- 要做到更强隔离，后续仍需要网络层 egress policy / sandbox / 专用代理。

但完成本轮后，系统会从“字符串黑名单”提升到“可测试的 URL + DNS + redirect 预检”，足够解决当前最明显的生产风险。
