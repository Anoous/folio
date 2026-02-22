# Folio 本地部署指南

## 一键启动

```bash
cd /Users/mac/github/folio/server
./scripts/dev-start.sh
```

脚本会自动完成以下全部步骤：

1. 检查 Docker / Node / Python / Go 是否已安装
2. Go 版本不够时自动通过 gvm 安装并切换到 1.24
3. 启动 PostgreSQL + Redis（Docker）并等待就绪
4. 构建 reader 本地依赖（如果 `dist/` 不存在）
5. 启动 Reader Service（:3000）
6. 安装 fastapi/uvicorn（如果没装）并启动 Mock AI Service（:8000）
7. 启动 Go API Server（:8080，DEV_MODE=true）
8. 打开 Xcode 项目

全部就绪后在终端会看到：

```
════════════════════════════════════════════════════
  所有服务已启动！
════════════════════════════════════════════════════

  API Server   http://localhost:8080
  Reader       http://localhost:3000
  Mock AI      http://localhost:8000
  PostgreSQL   localhost:5432  (folio/folio)
  Redis        localhost:6380
```

---

## iOS 模拟器测试

1. Xcode 中选择 **Folio** scheme + **iPhone 16 Pro**（或任意 iOS 17+ 模拟器）
2. `Cmd + R` 运行
3. App 启动后进入 Onboarding 页面，点击 **「Dev Login」** 按钮登录（DEBUG 专用，无需 Apple ID）
4. 登录成功后进入主页，开始测试

### 测试清单

| # | 功能 | 操作 | 预期 |
|---|------|------|------|
| 1 | 提交文章 | 点 + 按钮，输入 `https://go.dev/blog/go1.24`，提交 | 状态 pending → processing → ready |
| 2 | 文章列表 | 返回 Home 页 | 显示文章标题、分类、标签 |
| 3 | 阅读详情 | 点击文章 | Markdown 渲染内容 |
| 4 | 分类筛选 | 切换分类标签 | 列表过滤 |
| 5 | 搜索 | 进入搜索页输入关键词 | 返回匹配结果 |
| 6 | 收藏 | 文章详情页点收藏 | 标记成功 |
| 7 | 删除 | 删除文章 | 从列表消失 |

### Share Extension 测试

1. 模拟器中打开 Safari，浏览任意网页
2. 点 Share → 找到 Folio → 确认保存

---

## 用命令行快速验证后端

不想开模拟器，直接在终端测 API：

```bash
# 登录
TOKEN=$(curl -s -X POST http://localhost:8080/api/v1/auth/dev | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# 查看分类
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/categories | python3 -m json.tool

# 提交文章
curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"url":"https://go.dev/blog/go1.24"}' \
  http://localhost:8080/api/v1/articles | python3 -m json.tool

# 等后台处理完，查看文章列表
sleep 5
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/articles | python3 -m json.tool

# 搜索
curl -s -H "Authorization: Bearer $TOKEN" "http://localhost:8080/api/v1/articles/search?q=go" | python3 -m json.tool
```

---

## 停止服务

- 在脚本终端按 **Ctrl+C** → 自动停止 Reader / AI / Go Server
- Docker 容器仍保留运行，如需停止：

```bash
cd /Users/mac/github/folio/server
docker compose -f docker-compose.dev.yml down      # 保留数据
docker compose -f docker-compose.dev.yml down -v    # 清除数据
```

---

## 架构

```
iOS Simulator (Folio App)
    │  DEBUG 模式自动连接 localhost:8080
    ▼
Go API Server (:8080)   ← DEV_MODE=true，开启 /auth/dev 端点
    ├── PostgreSQL (:5432)   ← Docker，自动建表
    ├── Redis (:6380)        ← Docker，Worker 任务队列
    ├── Reader Service (:3000) ← 网页抓取 → Markdown
    └── Mock AI Service (:8000) ← 确定性分类/标签/摘要
```
