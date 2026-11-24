#!/usr/bin/env bash
# Weekly additive sync: 01Block ↔ 01Block-new-Final (Saturday cron)
# Never overwrites / deletes. Logs under logs/blocks_weekly_sync/
set -euo pipefail

export TZ="${TZ:-Asia/Shanghai}"
export PATH="/usr/bin:/bin:/usr/local/bin:${PATH:-}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
A_ROOT="${SYNC_01BLOCK_A:-/mnt/e/01block/01Block}"
B_ROOT="${SYNC_01BLOCK_B:-${REPO_ROOT}}"
LOG_DIR="${B_ROOT}/logs/blocks_weekly_sync"
mkdir -p "${LOG_DIR}"
DAY="$(date +%F)"
LOG_FILE="${LOG_DIR}/${DAY}.log"
CRON_LOG="${LOG_DIR}/cron.log"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "${LOG_FILE}"; }

{
  log "===== weekly sync start ====="
  log "A=${A_ROOT}"
  log "B=${B_ROOT}"

  if [[ ! -d "${A_ROOT}" || ! -d "${B_ROOT}" ]]; then
    log "ERROR: missing root dir"
    exit 2
  fi

  PY="${B_ROOT}/scripts/sync_01block_bidirectional.py"
  if [[ ! -f "${PY}" ]]; then
    # fallback: copy script from B expected path already is PY
    log "ERROR: missing ${PY}"
    exit 2
  fi

  # Keep a copy of the sync script on A as well (additive)
  A_PY="${A_ROOT}/scripts/sync_01block_bidirectional.py"
  if [[ ! -f "${A_PY}" ]]; then
    mkdir -p "${A_ROOT}/scripts"
    cp -a "${PY}" "${A_PY}" || true
  fi
  A_SH="${A_ROOT}/scripts/sync_01block_weekly.sh"
  if [[ ! -f "${A_SH}" ]]; then
    cp -a "${B_ROOT}/scripts/sync_01block_weekly.sh" "${A_SH}" || true
  fi

  /usr/bin/python3 "${PY}" --a "${A_ROOT}" --b "${B_ROOT}" 2>&1 | tee -a "${LOG_FILE}"
  rc=${PIPESTATUS[0]}
  log "===== weekly sync end rc=${rc} ====="
  exit "${rc}"
} >>"${CRON_LOG}" 2>&1
