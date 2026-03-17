#!/usr/bin/env bash
# deploy-local.sh — Build and run the full Folio stack locally via Docker Compose
# Usage: cd server && ./scripts/deploy-local.sh [up|down|rebuild|logs|status]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
READER_LIB_DIR="$(cd "$SERVER_DIR/../../reader" 2>/dev/null && pwd || echo "")"
COMPOSE_FILE="$SERVER_DIR/docker-compose.local.yml"
ENV_FILE="$SERVER_DIR/.env"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── Ensure .env ──────────────────────────────────────────────────────
ensure_env() {
  if [ ! -f "$ENV_FILE" ]; then
    info "Creating .env from template..."
    cp "$SERVER_DIR/.env.example" "$ENV_FILE"
  fi

  # Ensure DB_PASSWORD exists
  if ! grep -q '^DB_PASSWORD=' "$ENV_FILE"; then
    echo "DB_PASSWORD=folio" >> "$ENV_FILE"
    info "Added DB_PASSWORD=folio to .env"
  fi

  # Ensure JWT_SECRET exists and is ≥32 chars
  if ! grep -q '^JWT_SECRET=' "$ENV_FILE" || \
     [ "$(grep '^JWT_SECRET=' "$ENV_FILE" | cut -d= -f2- | wc -c)" -lt 33 ]; then
    local jwt_secret
    jwt_secret="$(openssl rand -base64 48 | tr -d '\n')"
    # Remove old entry if present
    sed -i '' '/^JWT_SECRET=/d' "$ENV_FILE" 2>/dev/null || sed -i '/^JWT_SECRET=/d' "$ENV_FILE"
    echo "JWT_SECRET=$jwt_secret" >> "$ENV_FILE"
    info "Generated JWT_SECRET (64 chars)"
  fi

  # Check DEEPSEEK_API_KEY
  local dk_key
  dk_key="$(grep '^DEEPSEEK_API_KEY=' "$ENV_FILE" | cut -d= -f2-)"
  if [ -z "$dk_key" ]; then
    warn "DEEPSEEK_API_KEY is empty — AI service will start but analysis calls will fail"
    warn "Set it in $ENV_FILE if you have one"
  fi
}

# ── Bundle @vakra-dev/reader ─────────────────────────────────────────
bundle_reader() {
  local reader_svc="$SERVER_DIR/reader-service"
  local tarball="$reader_svc/reader-local.tgz"

  if [ -z "$READER_LIB_DIR" ] || [ ! -d "$READER_LIB_DIR" ]; then
    error "Reader library not found at /Users/mac/github/reader"
    error "Clone it or update READER_LIB_DIR in this script"
    exit 1
  fi

  # Build reader if dist/ is missing
  if [ ! -f "$READER_LIB_DIR/dist/index.js" ]; then
    info "Building @vakra-dev/reader..."
    (cd "$READER_LIB_DIR" && npm run build)
  fi

  # Pack reader library as tarball
  info "Packing @vakra-dev/reader..."
  (cd "$READER_LIB_DIR" && npm pack --pack-destination "$reader_svc" 2>/dev/null)

  # Rename to stable name (npm pack creates vakra-dev-reader-X.Y.Z.tgz)
  local packed
  packed="$(ls -t "$reader_svc"/vakra-dev-reader-*.tgz 2>/dev/null | head -1)"
  if [ -n "$packed" ] && [ "$packed" != "$tarball" ]; then
    mv "$packed" "$tarball"
  fi

  if [ ! -f "$tarball" ]; then
    error "Failed to create reader tarball"
    exit 1
  fi

  # Patch package.json to use local tarball (for Docker build)
  info "Patching reader-service/package.json for Docker build..."
  cd "$reader_svc"
  if grep -q '"file:../../../reader"' package.json; then
    sed -i '' 's|"file:../../../reader"|"file:./reader-local.tgz"|' package.json 2>/dev/null || \
    sed -i 's|"file:../../../reader"|"file:./reader-local.tgz"|' package.json
  fi

  # Remove package-lock.json — it references the old file: path and causes npm install to fail
  if [ -f package-lock.json ]; then
    mv package-lock.json package-lock.json.bak
    info "Backed up package-lock.json (incompatible with tarball path)"
  fi
  cd "$SERVER_DIR"

  info "Reader library bundled OK"
}

# ── Restore package.json after build ─────────────────────────────────
restore_reader_pkg() {
  local reader_svc="$SERVER_DIR/reader-service"
  cd "$reader_svc"
  if grep -q '"file:./reader-local.tgz"' package.json; then
    sed -i '' 's|"file:./reader-local.tgz"|"file:../../../reader"|' package.json 2>/dev/null || \
    sed -i 's|"file:./reader-local.tgz"|"file:../../../reader"|' package.json
    info "Restored reader-service/package.json"
  fi
  if [ -f package-lock.json.bak ]; then
    mv package-lock.json.bak package-lock.json
    info "Restored reader-service/package-lock.json"
  fi
  cd "$SERVER_DIR"
}

# ── Cleanup on exit ──────────────────────────────────────────────────
cleanup() {
  restore_reader_pkg
}

# ── Commands ─────────────────────────────────────────────────────────
cmd_up() {
  ensure_env
  bundle_reader
  trap cleanup EXIT

  info "Building and starting Folio stack..."
  cd "$SERVER_DIR"
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up --build -d

  cleanup

  info ""
  info "=== Folio local stack is running ==="
  info "  API:      http://localhost:8080"
  info "  Health:   http://localhost:8080/health"
  info "  Dev Login: POST http://localhost:8080/api/v1/auth/dev"
  info ""
  info "Logs:   ./scripts/deploy-local.sh logs"
  info "Stop:   ./scripts/deploy-local.sh down"
}

cmd_down() {
  info "Stopping Folio stack..."
  cd "$SERVER_DIR"
  docker compose -f "$COMPOSE_FILE" down
  info "Stack stopped"
}

cmd_rebuild() {
  info "Rebuilding Folio stack (no cache)..."
  ensure_env
  bundle_reader
  trap cleanup EXIT

  cd "$SERVER_DIR"
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up --build --force-recreate -d

  cleanup
  info "Stack rebuilt and running"
}

cmd_logs() {
  cd "$SERVER_DIR"
  docker compose -f "$COMPOSE_FILE" logs -f --tail=100
}

cmd_status() {
  cd "$SERVER_DIR"
  docker compose -f "$COMPOSE_FILE" ps
}

# ── Stop dev stack if running (port conflicts) ───────────────────────
check_port_conflicts() {
  if docker compose -f "$SERVER_DIR/docker-compose.dev.yml" ps --status running 2>/dev/null | grep -q "postgres"; then
    warn "Dev stack (docker-compose.dev.yml) is running on overlapping ports"
    warn "Stopping dev stack first..."
    docker compose -f "$SERVER_DIR/docker-compose.dev.yml" down
  fi
}

# ── Main ─────────────────────────────────────────────────────────────
CMD="${1:-up}"

case "$CMD" in
  up)
    check_port_conflicts
    cmd_up
    ;;
  down)
    cmd_down
    ;;
  rebuild)
    check_port_conflicts
    cmd_rebuild
    ;;
  logs)
    cmd_logs
    ;;
  status)
    cmd_status
    ;;
  *)
    echo "Usage: $0 [up|down|rebuild|logs|status]"
    echo ""
    echo "  up       Build and start the full stack (default)"
    echo "  down     Stop and remove containers"
    echo "  rebuild  Force rebuild all images and restart"
    echo "  logs     Tail container logs"
    echo "  status   Show container status"
    exit 1
    ;;
esac
