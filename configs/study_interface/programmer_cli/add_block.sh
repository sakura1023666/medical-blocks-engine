#!/usr/bin/env bash
# =============================================================================
#  add_block.sh — 挂接 block 到 hook slot（仅写 studies/<研究>/）
#  用法: ./add_block.sh <研究名> --slot SLOT_ID --block BLOCK_ID
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_load_engine.sh
source "${ROOT}/_load_engine.sh"
_load_engine "$ROOT"

STUDY="${1:-}"
if [[ -z "$STUDY" ]]; then
  echo "用法: $0 <研究名> --slot SLOT_ID --block BLOCK_ID" >&2
  exit 1
fi
shift

STUDY_DIR="${ROOT}/studies/${STUDY}"
CONFIG="${STUDY_DIR}/config.R"
if [[ ! -f "$CONFIG" ]]; then
  echo "[错误] 找不到配置: $CONFIG" >&2
  exit 1
fi

CATALOG="${ROOT}/docs/block_catalog"
CLI="${ENGINE}/scripts/run_programmer_block_hooks_cli.R"

if [[ ! -f "$CLI" ]]; then
  echo "[错误] 引擎 CLI 不存在: $CLI" >&2
  exit 1
fi

exec Rscript "$CLI" add --study-dir "$STUDY_DIR" --catalog-dir "$CATALOG" "$@"
