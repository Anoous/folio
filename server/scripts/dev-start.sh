#!/usr/bin/env bash
# Folio 本地开发一键启动脚本
# 用法: ./scripts/dev-start.sh
# 停止: Ctrl+C（自动清理所有子进程）
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
READER_PKG_DIR="$(cd "$ROOT_DIR/../../reader" 2>/dev/null && pwd || echo "")"
PIDS=()

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }
step() { echo -e "\n${CYAN}===> $*${NC}"; }

# ── 工具函数 ──────────────────────────────────────────────────

# 杀掉进程树（先杀子进程，再杀父进程）
kill_tree() {
    local pid=$1
    # 递归杀掉所有子进程
    local children
    children=$(pgrep -P "$pid" 2>/dev/null || true)
    for child in $children; do
        kill_tree "$child"
    done
    kill "$pid" 2>/dev/null || true
}

# 清理占用指定端口的进程
kill_port() {
    local port=$1
    local pids
    pids=$(lsof -ti :"$port" 2>/dev/null || true)
    if [ -n "$pids" ]; then
        warn "端口 $port 被占用 (PID: $pids)，正在终止..."
        for pid in $pids; do
            kill "$pid" 2>/dev/null || true
        done
        sleep 1
        # 强制杀掉仍存活的进程
        pids=$(lsof -ti :"$port" 2>/dev/null || true)
        for pid in $pids; do
            kill -9 "$pid" 2>/dev/null || true
        done
    fi
}

# ── Ctrl+C 清理 ──────────────────────────────────────────────
cleanup() {
    echo ""
    step "正在停止所有服务..."
    for pid in "${PIDS[@]}"; do
        kill_tree "$pid"
    done
    # 等待所有子进程退出
    for pid in "${PIDS[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    # 确保端口已释放
    for port in 3000 8000 8080; do
        local remaining
        remaining=$(lsof -ti :"$port" 2>/dev/null || true)
        if [ -n "$remaining" ]; then
            warn "端口 $port 仍被占用，强制终止..."
            kill -9 $remaining 2>/dev/null || true
        fi
    done
    log "所有后台服务已停止"
    echo -e "${YELLOW}提示: Docker 容器仍在运行，如需停止:${NC}"
    echo "  cd $ROOT_DIR && docker compose -f docker-compose.dev.yml down"
    echo "  加 -v 可清除数据: docker compose -f docker-compose.dev.yml down -v"
}
trap cleanup EXIT

# ── 前置检查 ──────────────────────────────────────────────────
step "检查前置条件"

command -v docker >/dev/null || err "缺少 docker，请先安装 Docker Desktop"
command -v node >/dev/null   || err "缺少 node，请先安装 Node.js 18+"
command -v python3 >/dev/null || err "缺少 python3，请先安装 Python 3.10+"
command -v go >/dev/null     || err "缺少 go，请先安装 Go 1.24+"

# Go 版本检查
GO_VER=$(go version | grep -oE 'go[0-9]+\.[0-9]+' | head -1 | sed 's/go//')
GO_MAJOR=$(echo "$GO_VER" | cut -d. -f1)
GO_MINOR=$(echo "$GO_VER" | cut -d. -f2)
if (( GO_MAJOR < 1 || (GO_MAJOR == 1 && GO_MINOR < 24) )); then
    warn "Go 版本 $GO_VER < 1.24，尝试自动切换..."
    if command -v gvm >/dev/null; then
        # 检查是否已安装 go1.24.0
        if ! gvm list 2>/dev/null | grep -q "go1.24"; then
            step "安装 Go 1.24.0（首次需要几分钟）"
            gvm install go1.24.0 -B || err "gvm install go1.24.0 失败，请手动安装"
        fi
        eval "$(SHELL=/bin/bash gvm 'use' go1.24.0)" 2>/dev/null || gvm use go1.24.0
        log "已切换到 $(go version)"
    else
        err "Go $GO_VER 太旧且未安装 gvm。请手动安装 Go 1.24+: https://go.dev/dl/"
    fi
fi

log "docker $(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
log "node $(node --version)"
log "python3 $(python3 --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
log "go $(go version | grep -oE 'go[0-9]+\.[0-9]+\.[0-9]*')"

# ── 1. Docker 基础设施 ───────────────────────────────────────
step "1/5 启动 PostgreSQL + Redis"

cd "$ROOT_DIR"
docker compose -f docker-compose.dev.yml up -d

# 等待 PostgreSQL 就绪
echo -n "  等待 PostgreSQL"
for i in $(seq 1 30); do
    if docker compose -f docker-compose.dev.yml exec -T postgres pg_isready -q 2>/dev/null; then
        echo ""
        log "PostgreSQL 就绪 (localhost:5432)"
        break
    fi
    echo -n "."
    sleep 1
    if [ "$i" -eq 30 ]; then
        echo ""
        err "PostgreSQL 启动超时"
    fi
done

# 等待 Redis 就绪
for i in $(seq 1 15); do
    if docker compose -f docker-compose.dev.yml exec -T redis redis-cli ping 2>/dev/null | grep -q PONG; then
        log "Redis 就绪 (localhost:6380)"
        break
    fi
    sleep 1
    if [ "$i" -eq 15 ]; then err "Redis 启动超时"; fi
done

# ── 清理残留进程 ───────────────────────────────────────────────
for port in 3000 8000 8080; do
    kill_port "$port"
done

# ── 2. Reader 本地依赖 ───────────────────────────────────────
step "2/5 启动 Reader Service (:3000)"

if [ -z "$READER_PKG_DIR" ]; then
    err "@vakra-dev/reader 本地包不存在。请确保 $(cd "$ROOT_DIR/../.." && pwd)/reader 目录存在"
fi

# 确保 reader 包已构建
if [ ! -d "$READER_PKG_DIR/dist" ]; then
    warn "reader 包未构建，正在构建..."
    (cd "$READER_PKG_DIR" && npm install && npm run build)
fi

cd "$ROOT_DIR/reader-service"
npm install --silent 2>/dev/null
npm run dev &
PIDS+=($!)

# 等待 Reader 就绪
for i in $(seq 1 30); do
    if curl -s http://localhost:3000/health 2>/dev/null | grep -q ok; then
        log "Reader Service 就绪"
        break
    fi
    sleep 1
    if [ "$i" -eq 30 ]; then err "Reader Service 启动超时"; fi
done

# ── 3. Mock AI Service ────────────────────────────────────────
step "3/5 启动 Mock AI Service (:8000)"

cd "$ROOT_DIR"

# 确保 fastapi/uvicorn 已安装
python3 -c "import fastapi, uvicorn" 2>/dev/null || {
    warn "安装 fastapi + uvicorn..."
    python3 -m pip install -q fastapi uvicorn pydantic
}

python3 scripts/mock_ai_service.py &
PIDS+=($!)

for i in $(seq 1 15); do
    if curl -s http://localhost:8000/health 2>/dev/null | grep -q ok; then
        log "Mock AI Service 就绪"
        break
    fi
    sleep 1
    if [ "$i" -eq 15 ]; then err "Mock AI Service 启动超时"; fi
done

# ── 4. Go API Server ─────────────────────────────────────────
step "4/5 启动 Go API Server (:8080)"

cd "$ROOT_DIR"

export DATABASE_URL="postgresql://folio:folio@localhost:5432/folio"
export REDIS_ADDR="localhost:6380"
export JWT_SECRET="dev-jwt-secret-change-in-production"
export READER_URL="http://localhost:3000"
export AI_SERVICE_URL="http://localhost:8000"
export DEV_MODE="true"
export PORT="8080"

go run ./cmd/server &
PIDS+=($!)

for i in $(seq 1 30); do
    if curl -s http://localhost:8080/health 2>/dev/null | grep -q ok; then
        log "Go API Server 就绪"
        break
    fi
    sleep 1
    if [ "$i" -eq 30 ]; then err "Go API Server 启动超时"; fi
done

# ── 5. 打开 Xcode ────────────────────────────────────────────
step "5/5 打开 Xcode 项目"

XCPROJ="$ROOT_DIR/../ios/Folio.xcodeproj"
if [ -d "$XCPROJ" ]; then
    open "$XCPROJ"
    log "Xcode 已打开"
else
    warn "Folio.xcodeproj 不存在，跳过。如需生成: cd ios && xcodegen generate"
fi

# ── 完成 ──────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  所有服务已启动！${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo ""
echo "  API Server   http://localhost:8080"
echo "  Reader       http://localhost:3000"
echo "  Mock AI      http://localhost:8000"
echo "  PostgreSQL   localhost:5432  (folio/folio)"
echo "  Redis        localhost:6380"
echo ""
echo "  iOS 测试步骤:"
echo "    1. Xcode 中选择 iPhone 模拟器，Cmd+R 运行"
echo "    2. App 启动后点击 「Dev Login」按钮登录"
echo "    3. 开始测试：提交文章、浏览、搜索..."
echo ""
echo -e "  ${YELLOW}按 Ctrl+C 停止所有服务${NC}"
echo ""

# 保持前台，等待 Ctrl+C
wait
