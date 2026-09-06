#!/usr/bin/env bash
# Folio 本地开发一键启动脚本（全容器模式）
# 用法: ./scripts/dev-start.sh
# 停止: Ctrl+C
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.local.yml"
ENV_FILE="$ROOT_DIR/.env"

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

# ── Ctrl+C 清理 ──────────────────────────────────────────────
cleanup() {
    echo ""
    step "正在停止所有容器..."
    cd "$ROOT_DIR"
    docker compose -f "$COMPOSE_FILE" down --remove-orphans 2>/dev/null || true
    log "所有容器已停止"
}
trap cleanup EXIT

# ── 前置检查 ──────────────────────────────────────────────────
step "检查前置条件"

command -v docker >/dev/null || err "缺少 docker，请先安装 Docker Desktop"
log "docker $(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"

# ── 1. 确保 .env ─────────────────────────────────────────────
step "1/4 检查环境配置"

# 委托 deploy-local.sh 的 ensure_env 逻辑
if [ ! -f "$ENV_FILE" ]; then
    log "从模板创建 .env..."
    cp "$ROOT_DIR/.env.example" "$ENV_FILE"
fi

if ! grep -q '^DB_PASSWORD=' "$ENV_FILE"; then
    echo "DB_PASSWORD=folio" >> "$ENV_FILE"
    log "添加 DB_PASSWORD=folio"
fi

if ! grep -q '^JWT_SECRET=' "$ENV_FILE" || \
   [ "$(grep '^JWT_SECRET=' "$ENV_FILE" | cut -d= -f2- | wc -c)" -lt 33 ]; then
    jwt_secret="$(openssl rand -base64 48 | tr -d '\n')"
    sed -i '' '/^JWT_SECRET=/d' "$ENV_FILE" 2>/dev/null || sed -i '/^JWT_SECRET=/d' "$ENV_FILE"
    echo "JWT_SECRET=$jwt_secret" >> "$ENV_FILE"
    log "生成 JWT_SECRET"
fi

dk_key="$(grep '^DEEPSEEK_API_KEY=' "$ENV_FILE" | cut -d= -f2- || true)"
if [ -z "$dk_key" ]; then
    warn "DEEPSEEK_API_KEY 为空 — 将使用 mock AI（无真实分析）"
else
    log "DEEPSEEK_API_KEY 已配置"
fi

# ── 2. 停掉可能冲突的旧栈 ────────────────────────────────────
step "2/4 清理旧进程和容器"

# 停掉 dev 模式的 docker-compose（端口冲突）
if docker compose -f "$ROOT_DIR/docker-compose.dev.yml" ps --status running 2>/dev/null | grep -q "postgres"; then
    warn "dev 栈仍在运行，停止中..."
    docker compose -f "$ROOT_DIR/docker-compose.dev.yml" down 2>/dev/null || true
fi

# 停掉端口 8080 上的本地进程
local_pid=$(lsof -ti :8080 2>/dev/null || true)
if [ -n "$local_pid" ]; then
    warn "端口 8080 被占用 (PID: $local_pid)，正在终止..."
    kill $local_pid 2>/dev/null || true
    sleep 1
fi

# ── 3. 构建并启动全栈容器 ────────────────────────────────────
step "3/4 构建并启动容器"

cd "$ROOT_DIR"

# 打包 reader 本地依赖
READER_LIB_DIR="$(cd "$ROOT_DIR/../../reader" 2>/dev/null && pwd || echo "")"
if [ -z "$READER_LIB_DIR" ] || [ ! -d "$READER_LIB_DIR" ]; then
    err "@vakra-dev/reader 不存在。请确保 ~/github/reader 目录存在"
fi

if [ ! -f "$READER_LIB_DIR/dist/index.js" ]; then
    log "构建 @vakra-dev/reader..."
    (cd "$READER_LIB_DIR" && /opt/homebrew/bin/npm run build)
fi

log "打包 @vakra-dev/reader..."
(cd "$READER_LIB_DIR" && npm pack --pack-destination "$ROOT_DIR/reader-service" 2>/dev/null)
packed="$(ls -t "$ROOT_DIR/reader-service"/vakra-dev-reader-*.tgz 2>/dev/null | head -1)"
if [ -n "$packed" ]; then
    mv "$packed" "$ROOT_DIR/reader-service/reader-local.tgz"
fi

# 临时修改 package.json 用 tarball
cd "$ROOT_DIR/reader-service"
pkg_patched=false
if grep -q '"file:../../../reader"' package.json; then
    sed -i '' 's|"file:../../../reader"|"file:./reader-local.tgz"|' package.json 2>/dev/null || \
    sed -i 's|"file:../../../reader"|"file:./reader-local.tgz"|' package.json
    pkg_patched=true
fi
if [ -f package-lock.json ]; then
    mv package-lock.json package-lock.json.bak
fi
cd "$ROOT_DIR"

# 构建并启动
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up --build -d

# 恢复 package.json
cd "$ROOT_DIR/reader-service"
if [ "$pkg_patched" = true ]; then
    sed -i '' 's|"file:./reader-local.tgz"|"file:../../../reader"|' package.json 2>/dev/null || \
    sed -i 's|"file:./reader-local.tgz"|"file:../../../reader"|' package.json
fi
if [ -f package-lock.json.bak ]; then
    mv package-lock.json.bak package-lock.json
fi
cd "$ROOT_DIR"

# 等待 API 就绪
echo -n "  等待 API Server"
for i in $(seq 1 60); do
    if curl -s http://localhost:8080/health 2>/dev/null | grep -q ok; then
        echo ""
        log "API Server 就绪"
        break
    fi
    echo -n "."
    sleep 1
    if [ "$i" -eq 60 ]; then
        echo ""
        err "API Server 启动超时"
    fi
done

# ── 4. 打开 Xcode ────────────────────────────────────────────
step "4/4 打开 Xcode 项目"

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
echo -e "${GREEN}  所有服务已启动！（容器模式）${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo ""
echo "  API Server   http://localhost:8080  (容器)"
echo "  Reader       容器内 :3000"
echo "  PostgreSQL   容器内 :5432"
echo "  Redis        容器内 :6379"
echo ""
echo "  查看日志:  docker compose -f docker-compose.local.yml logs -f"
echo "  查看状态:  docker compose -f docker-compose.local.yml ps"
echo ""
echo "  iOS 测试步骤:"
echo "    1. Xcode 中选择 iPhone 模拟器，Cmd+R 运行"
echo "    2. App 启动后点击 Dev Login"
echo "    3. 开始测试：提交文章、浏览、搜索..."
echo ""
echo -e "  ${YELLOW}按 Ctrl+C 停止所有容器${NC}"
echo ""

# 保持前台，跟踪容器日志
docker compose -f "$COMPOSE_FILE" logs -f
