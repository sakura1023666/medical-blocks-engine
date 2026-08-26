#!/usr/bin/env bash
# Shared engine.env loader for programmer CLI wrappers (same pattern as run_study.sh)
_load_engine() {
  local root="$1"
  ENGINE=""
  if [[ -f "${root}/engine.env" ]]; then
    # shellcheck disable=SC1090
    source <(grep -E '^MEDICAL_BLOCKS_ROOT=' "${root}/engine.env" | sed 's/\r$//')
    ENGINE="${MEDICAL_BLOCKS_ROOT:-}"
  fi
  if [[ -n "$ENGINE" && "$ENGINE" =~ ^[A-Za-z]:/ ]]; then
    local drive
    drive="$(echo "${ENGINE:0:1}" | tr '[:upper:]' '[:lower:]')"
    ENGINE="/mnt/${drive}${ENGINE:2}"
  fi
  if [[ -z "$ENGINE" || ! -d "$ENGINE" ]]; then
    if [[ -d "/mnt/e/01block/01Block-new-Final" ]]; then
      ENGINE="/mnt/e/01block/01Block-new-Final"
    else
      echo "[错误] engine.env 未设置有效 MEDICAL_BLOCKS_ROOT" >&2
      return 1
    fi
  fi
  export MEDICAL_BLOCKS_ROOT="$ENGINE"
}
