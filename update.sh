#!/usr/bin/env bash
set -euo pipefail

# ===== Настройки =====
DOMAIN="https://n8n.n8n-my-project.ru"
COMPOSE_DIR="/opt/n8n"
COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.yml"
BACKUP_SCRIPT="${COMPOSE_DIR}/backup.sh"
LOG="${COMPOSE_DIR}/update.log"

# Версия по умолчанию (если не передали аргументом)
N8N_TAG_DEFAULT="2.3.5"

# Успешные HTTP-коды (401 ок из-за Basic Auth / сессий)
OK_CODES_REGEX='^(200|301|302|401)$'

# Таймауты curl
CURL_CONNECT_TIMEOUT=5
CURL_MAX_TIME=12

# Ожидание старта (важно: после пересоздания n8n первые секунды может быть 502)
STARTUP_RETRIES=60   # 60 попыток
STARTUP_SLEEP=2      # каждые 2 секунды (итого до ~120 сек)

ts() { date +"%Y-%m-%d %H:%M:%S"; }
log() { echo "[$(ts)] $*" | tee -a "$LOG"; }
fail() { log "ERROR: $*"; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || fail "Command not found: $1"; }

# ===== Версия на апдейт =====
N8N_TAG="${1:-$N8N_TAG_DEFAULT}"

log "=== UPDATE START ==="
log "Target n8n version: ${N8N_TAG}"
log "Domain for health-check: ${DOMAIN}"
log "Compose file: ${COMPOSE_FILE}"

# ===== Checks =====
need_cmd docker
need_cmd curl
need_cmd gawk
need_cmd awk

[ -f "$COMPOSE_FILE" ] || fail "Compose file not found: $COMPOSE_FILE"
[ -x "$BACKUP_SCRIPT" ] || fail "Backup script not found/executable: $BACKUP_SCRIPT"

cd "$COMPOSE_DIR"

docker compose version >/dev/null 2>&1 || fail "docker compose is not available"
COMPOSE="docker compose"

# ===== Определяем режим работы (HTTP или HTTPS) =====
IS_HTTPS=false
if docker ps --format '{{.Names}}' | grep -qx 'caddy' || grep -q "^[[:space:]]*caddy:" "$COMPOSE_FILE"; then
  IS_HTTPS=true
  log "Detected HTTPS mode (Caddy found)"
else
  log "Detected HTTP mode"
fi

# ===== Утилита вывода логов =====
show_logs () {
  log "Last logs (n8n):"
  docker logs --tail=200 n8n | tee -a "$LOG" || true

  if docker ps --format '{{.Names}}' | grep -qx 'caddy'; then
    log "Last logs (caddy):"
    docker logs --tail=200 caddy | tee -a "$LOG" || true
  else
    log "Skip caddy logs: container not found"
  fi
}

# ===== Backup =====
log "Running backup: ${BACKUP_SCRIPT}"
"$BACKUP_SCRIPT" | tee -a "$LOG"

# ===== Update docker-compose.yml (pin tag) =====
log "Updating n8n image tag inside docker-compose.yml"
TMP_FILE="$(mktemp)"

# Меняем image только в блоке сервиса n8n:
gawk -v tag="$N8N_TAG" '
  BEGIN { in_n8n=0 }
  /^[[:space:]]*n8n:[[:space:]]*$/ { in_n8n=1; print; next }
  in_n8n && /^[[:space:]]{2}[A-Za-z0-9_-]+:[[:space:]]*$/ { in_n8n=0; print; next }
  in_n8n && /^[[:space:]]*image:[[:space:]]*/ {
    print "    image: docker.n8n.io/n8nio/n8n:" tag
    next
  }
  { print }
' "$COMPOSE_FILE" > "$TMP_FILE"

grep -q "image: docker\.n8n\.io/n8nio/n8n:${N8N_TAG}" "$TMP_FILE" || {
  rm -f "$TMP_FILE"
  fail "Failed to set n8n image tag in compose. Check service name/indentation."
}

cp -a "$COMPOSE_FILE" "${COMPOSE_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
mv "$TMP_FILE" "$COMPOSE_FILE"

log "Validating compose config"
$COMPOSE config >/dev/null

# ===== HTTPS network sanity (если нужно) =====
if [ "$IS_HTTPS" = true ]; then
  NETWORK_NAME="n8n_network"
  if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    log "Creating network: ${NETWORK_NAME}"
    docker network create "$NETWORK_NAME" || log "Warning: Failed to create network (may already exist)"
  else
    log "Network ${NETWORK_NAME} exists"
  fi
fi

# ===== Pull =====
log "Pull images"
$COMPOSE pull | tee -a "$LOG"

# ===== Recreate =====
# В HTTPS режиме не трогаем caddy без нужды — пересоздаём только n8n.
if [ "$IS_HTTPS" = true ]; then
  log "Recreate n8n only (force recreate, keep caddy running)"
  $COMPOSE up -d --no-deps --force-recreate n8n | tee -a "$LOG"
else
  log "Recreate containers"
  $COMPOSE up -d | tee -a "$LOG"
fi

# ===== Verify network membership (опционально) =====
if [ "$IS_HTTPS" = true ]; then
  NETWORK_NAME="n8n_network"
  log "Verifying containers are in network: ${NETWORK_NAME}"

  if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    N8N_IN_NETWORK=$(docker network inspect "$NETWORK_NAME" --format '{{range .Containers}}{{.Name}} {{end}}' | grep -q "n8n" && echo "yes" || echo "no")
    CADDY_IN_NETWORK=$(docker network inspect "$NETWORK_NAME" --format '{{range .Containers}}{{.Name}} {{end}}' | grep -q "caddy" && echo "yes" || echo "no")

    if [ "$N8N_IN_NETWORK" = "yes" ] && [ "$CADDY_IN_NETWORK" = "yes" ]; then
      log "OK: Both n8n and caddy are in network ${NETWORK_NAME}"
    else
      log "WARNING: Containers may not be in correct network. n8n=${N8N_IN_NETWORK}, caddy=${CADDY_IN_NETWORK}"
      log "Network containers: $(docker network inspect "$NETWORK_NAME" --format '{{range .Containers}}{{.Name}} {{end}}')"
    fi
  else
    log "WARNING: Network ${NETWORK_NAME} does not exist"
  fi
fi

# ===== Health-check with retries =====
log "Health-check (with retries): GET ${DOMAIN}/"

set +e
OK=0
LAST_CODE=""
LAST_RC=""

for i in $(seq 1 "$STARTUP_RETRIES"); do
  HTTP_CODE="$(curl -k -sS -o /dev/null -w "%{http_code}" \
    --connect-timeout "$CURL_CONNECT_TIMEOUT" \
    --max-time "$CURL_MAX_TIME" \
    "${DOMAIN}/")"
  CURL_RC=$?

  LAST_CODE="$HTTP_CODE"
  LAST_RC="$CURL_RC"

  if [ "$CURL_RC" -eq 0 ] && echo "$HTTP_CODE" | grep -Eq "$OK_CODES_REGEX"; then
    OK=1
    break
  fi

  log "Waiting for n8n... attempt ${i}/${STARTUP_RETRIES}, http=${HTTP_CODE}, rc=${CURL_RC}"
  sleep "$STARTUP_SLEEP"
done
set -e

if [ "$OK" -eq 1 ]; then
  log "OK: HTTP ${HTTP_CODE} (health-check passed)"
else
  log "FAIL: after retries http=${LAST_CODE}, rc=${LAST_RC}"
  show_logs
  fail "Health-check failed (bad HTTP code)"
fi

# ===== Extra UI checks (protect from iframe break) =====
if [ "$IS_HTTPS" = true ]; then
  DEMO_URL="${DOMAIN%/}/workflows/demo"
  log "Extra check: ${DEMO_URL} must be reachable and allow SAMEORIGIN iframe"

  set +e
  DEMO_HEADERS="$(curl -k -sS -D - -o /dev/null \
    --connect-timeout "$CURL_CONNECT_TIMEOUT" \
    --max-time "$CURL_MAX_TIME" \
    "$DEMO_URL")"
  DEMO_RC=$?
  set -e

  if [ "$DEMO_RC" -ne 0 ]; then
    log "FAIL: curl headers for ${DEMO_URL} error rc=${DEMO_RC}"
    show_logs
    fail "Extra check failed (curl error for /workflows/demo)"
  fi

  # 1) Статус должен быть 200/30x или 401 (если нет сессии — всё равно ручка жива)
  DEMO_STATUS="$(printf '%s' "$DEMO_HEADERS" | head -n 1 | awk '{print $2}')"
  if ! echo "$DEMO_STATUS" | grep -Eq '^(200|301|302|307|308|401)$'; then
    log "FAIL: /workflows/demo bad status: ${DEMO_STATUS}"
    log "Headers:"
    printf '%s\n' "$DEMO_HEADERS" | tee -a "$LOG"
    show_logs
    fail "Extra check failed (bad HTTP status for /workflows/demo)"
  fi

  # 2) Должен быть X-Frame-Options: SAMEORIGIN
  if ! printf '%s' "$DEMO_HEADERS" | grep -Eqi '^x-frame-options:[[:space:]]*SAMEORIGIN[[:space:]]*$'; then
    log "FAIL: missing required header: X-Frame-Options: SAMEORIGIN"
    log "Headers:"
    printf '%s\n' "$DEMO_HEADERS" | tee -a "$LOG"
    show_logs
    fail "Extra check failed (iframe protection header missing)"
  fi

  # 3) Не должно быть DENY
  if printf '%s' "$DEMO_HEADERS" | grep -Eqi '^x-frame-options:[[:space:]]*DENY[[:space:]]*$'; then
    log "FAIL: detected forbidden header: X-Frame-Options: DENY"
    log "Headers:"
    printf '%s\n' "$DEMO_HEADERS" | tee -a "$LOG"
    show_logs
    fail "Extra check failed (DENY blocks iframe)"
  fi

  log "OK: /workflows/demo status=${DEMO_STATUS}, X-Frame-Options=SAMEORIGIN"
else
  log "Skip extra /workflows/demo check: HTTP mode"
fi

log "=== UPDATE DONE ==="
