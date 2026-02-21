#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Folio E2E Test Runner
#
# Runs Postgres + Redis in Docker, then starts API / Reader / AI locally.
#
# Usage:
#   ./scripts/run_e2e.sh              # full test suite
#   ./scripts/run_e2e.sh --smoke      # smoke tests only
#   ./scripts/run_e2e.sh --no-docker  # skip docker; services already running
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
READER_DIR="$SERVER_DIR/reader-service"
AI_DIR="$SERVER_DIR/ai-service"

cd "$SERVER_DIR"

SMOKE_ONLY=false
USE_DOCKER=true
BASE_URL="http://localhost:18080"
READER_URL="http://localhost:13000"
AI_URL="http://localhost:18000"
EXTRA_ARGS=()

# ---------- parse flags ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --smoke)     SMOKE_ONLY=true; shift ;;
    --no-docker) USE_DOCKER=false; shift ;;
    --base-url)  BASE_URL="$2"; shift 2 ;;
    --base-url=*) BASE_URL="${1#*=}"; shift ;;
    *)           EXTRA_ARGS+=("$1"); shift ;;
  esac
done

E2E_DIR="tests/e2e"
REPORT_DIR="${E2E_DIR}/reports"
COMPOSE_FILE="docker-compose.test.yml"

# PID tracking for cleanup
PIDS=()

# ---------- colours ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[e2e]${NC} $*"; }
warn()  { echo -e "${YELLOW}[e2e]${NC} $*"; }
error() { echo -e "${RED}[e2e]${NC} $*"; }

# ---------- cleanup ----------
cleanup() {
  info "Cleaning up ..."
  for pid in "${PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
  if $USE_DOCKER; then
    docker compose -f "$COMPOSE_FILE" down -v --remove-orphans 2>/dev/null || true
  fi
}
trap cleanup EXIT

# ---------- docker (postgres + redis only) ----------
start_docker() {
  info "Starting Postgres + Redis in Docker ..."
  docker compose -f "$COMPOSE_FILE" down -v --remove-orphans 2>/dev/null || true
  docker compose -f "$COMPOSE_FILE" up -d --wait 2>&1 | tail -5
  info "Postgres + Redis ready."
}

# ---------- wait for a URL to respond ----------
wait_for() {
  local url="$1" label="$2" max="${3:-60}"
  local i=0
  while ! curl -sf "$url" > /dev/null 2>&1; do
    i=$((i + 1))
    if [[ $i -ge $max ]]; then
      error "$label did not become healthy at $url within ${max}s"
      exit 1
    fi
    sleep 1
  done
  info "$label is healthy."
}

# ---------- start reader service locally ----------
start_reader() {
  info "Installing reader-service dependencies ..."
  (cd "$READER_DIR" && npm install --silent 2>&1 | tail -3)

  info "Starting reader-service on port 13000 ..."
  (cd "$READER_DIR" && PORT=13000 npx tsx src/index.ts 2>&1 | sed 's/^/  [reader] /') &
  PIDS+=($!)
  wait_for "$READER_URL/health" "Reader service" 30
}

# ---------- start AI service locally ----------
start_ai() {
  info "Installing AI service dependencies ..."
  pip install -q -r "$AI_DIR/requirements.txt"

  info "Starting AI service on port 18000 ..."
  (cd "$AI_DIR" && \
    REDIS_URL="redis://localhost:16379" \
    python3 -m uvicorn app.main:app --host 127.0.0.1 --port 18000 --log-level warning \
  ) 2>&1 | sed 's/^/  [ai] /' &
  PIDS+=($!)
  wait_for "$AI_URL/health" "AI service" 30
}

# ---------- build & start Go API server locally ----------
start_api() {
  info "Building Go API server ..."
  (cd "$SERVER_DIR" && go build -o /tmp/folio-e2e-server ./cmd/server)

  info "Starting API server on port 18080 ..."
  DATABASE_URL="postgresql://folio:folio_test@localhost:15432/folio_test" \
  REDIS_ADDR="localhost:16379" \
  READER_URL="$READER_URL" \
  AI_SERVICE_URL="$AI_URL" \
  JWT_SECRET="e2e-test-secret-key-not-for-production" \
  DEV_MODE="true" \
  PORT="18080" \
  /tmp/folio-e2e-server 2>&1 | sed 's/^/  [api] /' &
  PIDS+=($!)
  wait_for "$BASE_URL/health" "API server" 30
}

# ---------- python venv ----------
ensure_venv() {
  if [[ ! -d "${E2E_DIR}/.venv" ]]; then
    info "Creating Python virtual environment ..."
    python3 -m venv "${E2E_DIR}/.venv"
  fi
  # shellcheck disable=SC1091
  source "${E2E_DIR}/.venv/bin/activate"
  pip install -q -r "${E2E_DIR}/requirements.txt"
}

# ---------- main ----------
mkdir -p "$REPORT_DIR"
ensure_venv

# Load .env if present (for secrets like DEEPSEEK_API_KEY)
if [[ -f "$SERVER_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$SERVER_DIR/.env"
  set +a
fi

# Clear proxy env vars — all services connect to localhost
unset ALL_PROXY HTTPS_PROXY HTTP_PROXY all_proxy https_proxy http_proxy 2>/dev/null || true

if $USE_DOCKER; then
  # Kill leftover processes on test ports
  for p in 13000 18000 18080; do
    lsof -ti :"$p" 2>/dev/null | xargs kill 2>/dev/null || true
  done
  sleep 1
  start_docker
  start_reader
  start_ai
  start_api
fi

# Build pytest args
PYTEST_ARGS=(
  "${E2E_DIR}"
  "--base-url=${BASE_URL}"
  "--reader-url=${READER_URL}"
  "--ai-url=${AI_URL}"
  "--html=${REPORT_DIR}/e2e-report.html"
  "--self-contained-html"
  "--junitxml=${REPORT_DIR}/e2e-results.xml"
  "-v"
)

if $SMOKE_ONLY; then
  PYTEST_ARGS+=("-m" "smoke")
fi

if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
  PYTEST_ARGS+=("${EXTRA_ARGS[@]}")
fi

info "Running E2E tests ..."
echo ""

if python -m pytest "${PYTEST_ARGS[@]}"; then
  echo ""
  info "All tests passed!"
  info "HTML report: ${REPORT_DIR}/e2e-report.html"
  info "JUnit XML:   ${REPORT_DIR}/e2e-results.xml"
else
  echo ""
  error "Some tests failed. See report: ${REPORT_DIR}/e2e-report.html"
  exit 1
fi
