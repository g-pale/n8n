#!/usr/bin/env bash
set -euo pipefail

TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="/opt/n8n/backups"
mkdir -p "$BACKUP_DIR"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

backup_volume () {
  local VOL="$1"
  local NAME="$2"

  if ! docker volume inspect "$VOL" >/dev/null 2>&1; then
    log "Skip: volume not found: ${VOL}"
    return 0
  fi

  log "Backing up volume '${VOL}' -> ${NAME}-${TS}.tar.gz"
  docker run --rm \
    -v "${VOL}":/data:ro \
    -v "${BACKUP_DIR}":/backup \
    ubuntu tar czf "/backup/${NAME}-${TS}.tar.gz" /data
}

log "==> Backup started: ${TS}"

# Volumes (из текущего сервера)
backup_volume "n8n_n8n_data" "n8n_data"
backup_volume "n8n_caddy_data" "caddy_data"
backup_volume "n8n_caddy_config" "caddy_config"

# Ротация: хранить 14 последних комплектов (якорь = n8n_data)
KEEP=14
log "Rotation: keep last ${KEEP} backups"

OLD_N8N=$(ls -1t "${BACKUP_DIR}"/n8n_data-*.tar.gz 2>/dev/null | tail -n +$((KEEP+1)) || true)

if [ -n "${OLD_N8N}" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    base="$(basename "$f")"
    suffix="${base#n8n_data-}"  # YYYYMMDD-HHMMSS.tar.gz
    rm -f "${BACKUP_DIR}/n8n_data-${suffix}" \
          "${BACKUP_DIR}/caddy_data-${suffix}" \
          "${BACKUP_DIR}/caddy_config-${suffix}" || true
    log "Deleted old set: *-${suffix}"
  done <<< "${OLD_N8N}"
else
  log "No old backups to delete"
fi

log "==> Backup done: ${BACKUP_DIR}"
