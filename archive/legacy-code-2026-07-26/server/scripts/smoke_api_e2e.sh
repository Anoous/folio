#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-2}"
POLL_MAX_SECONDS="${POLL_MAX_SECONDS:-90}"
TEST_URL="${TEST_URL:-https://example.com/?folio_smoke=$(date +%s)}"

# JWT secret must match the running server
JWT_SECRET="${JWT_SECRET:-dev-jwt-secret-change-in-production}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 2
  fi
}

require_cmd curl
require_cmd jq
require_cmd python3

echo "[1/7] health"
curl -fsS "$BASE_URL/health" | jq -e '.status == "ok"' >/dev/null

echo "[2/7] generate test user + token"
# Create a test user in the database and generate a JWT
SMOKE_USER_ID="$(python3 -c "import uuid; print(uuid.uuid4())")"

# Insert user via docker exec (psql is not installed on host)
PG_CONTAINER="$(docker ps --filter "publish=5432" -q 2>/dev/null || true)"
if [[ -n "$PG_CONTAINER" ]]; then
  docker exec "$PG_CONTAINER" psql -U folio -d folio -c \
    "INSERT INTO users (id, apple_id, email, nickname) VALUES ('$SMOKE_USER_ID', 'smoke-test-user', 'smoke@folio.test', 'Smoke') ON CONFLICT (apple_id) DO UPDATE SET id = users.id RETURNING id" \
    -t -A 2>/dev/null | head -1 | read SMOKE_USER_ID || true
fi

ACCESS_TOKEN="$(python3 -c "
import json, hmac, hashlib, base64, time
header = base64.urlsafe_b64encode(json.dumps({'alg':'HS256','typ':'JWT'}).encode()).rstrip(b'=').decode()
now = int(time.time())
payload = base64.urlsafe_b64encode(json.dumps({'uid': '$SMOKE_USER_ID', 'type':'access','iss':'folio','iat':now,'exp':now+7200}).encode()).rstrip(b'=').decode()
msg = f'{header}.{payload}'.encode()
sig = base64.urlsafe_b64encode(hmac.new('$JWT_SECRET'.encode(), msg, hashlib.sha256).digest()).rstrip(b'=').decode()
print(f'{header}.{payload}.{sig}')
")"
if [[ -z "$ACCESS_TOKEN" ]]; then
  echo "token generation failed" >&2
  exit 1
fi

auth_header=("Authorization: Bearer $ACCESS_TOKEN")

echo "[3/7] list endpoints (must return array data)"
for path in \
  "/api/v1/categories" \
  "/api/v1/tags" \
  "/api/v1/articles?status=ready&page=1&per_page=20" \
  "/api/v1/articles/search?q=unlikely_query_zzzzz&page=1&per_page=20"
do
  body="$(curl -fsS "$BASE_URL$path" -H "${auth_header[0]}")"
  echo "$body" | jq -e '.data | type == "array"' >/dev/null
  echo "$body" | jq -e '.pagination.page >= 1 and .pagination.per_page >= 0 and .pagination.total >= 0' >/dev/null
done

echo "[4/7] submit article"
SUBMIT_BODY="$(jq -n --arg url "$TEST_URL" '{url:$url}')"
SUBMIT_JSON="$(curl -fsS -X POST "$BASE_URL/api/v1/articles" -H "${auth_header[0]}" -H "Content-Type: application/json" -d "$SUBMIT_BODY")"
ARTICLE_ID="$(echo "$SUBMIT_JSON" | jq -r '.article_id')"
TASK_ID="$(echo "$SUBMIT_JSON" | jq -r '.task_id')"
if [[ -z "$ARTICLE_ID" || "$ARTICLE_ID" == "null" || -z "$TASK_ID" || "$TASK_ID" == "null" ]]; then
  echo "submit failed: $SUBMIT_JSON" >&2
  exit 1
fi
echo "article_id=$ARTICLE_ID task_id=$TASK_ID"

echo "[5/7] poll task"
deadline=$((SECONDS + POLL_MAX_SECONDS))
last_status=""
task_json="{}"
while (( SECONDS < deadline )); do
  task_json="$(curl -fsS "$BASE_URL/api/v1/tasks/$TASK_ID" -H "${auth_header[0]}")"
  status="$(echo "$task_json" | jq -r '.status')"

  if [[ "$status" != "$last_status" ]]; then
    echo "task_status=$status"
    last_status="$status"
  fi

  case "$status" in
    done)
      break
      ;;
    failed)
      echo "task failed: $(echo "$task_json" | jq -r '.error_message // "unknown error"')" >&2
      exit 1
      ;;
  esac

  sleep "$POLL_INTERVAL_SECONDS"
done

if [[ "$(echo "$task_json" | jq -r '.status')" != "done" ]]; then
  echo "task timeout after ${POLL_MAX_SECONDS}s, last status: $(echo "$task_json" | jq -r '.status')" >&2
  exit 1
fi

echo "[6/7] fetch article detail"
ARTICLE_JSON="$(curl -fsS "$BASE_URL/api/v1/articles/$ARTICLE_ID" -H "${auth_header[0]}")"
echo "$ARTICLE_JSON" | jq -e --arg id "$ARTICLE_ID" '.id == $id' >/dev/null

echo "[7/7] done"
echo "smoke e2e passed"
