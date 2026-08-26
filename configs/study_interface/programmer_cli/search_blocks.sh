#!/usr/bin/env bash
# =============================================================================
#  search_blocks.sh — 只读搜索 block catalog / 列出 hook slots
#  用法:
#    ./search_blocks.sh [query]
#    ./search_blocks.sh --routine environment
#    ./search_blocks.sh --list-slots --routine environment
#    ./search_blocks.sh --tag plot --routine ml
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_load_engine.sh
source "${ROOT}/_load_engine.sh"
_load_engine "$ROOT"

CATALOG="${ROOT}/docs/block_catalog"
CLI="${ENGINE}/scripts/run_programmer_block_hooks_cli.R"

if [[ ! -f "$CLI" ]]; then
  echo "[错误] 引擎 CLI 不存在: $CLI" >&2
  exit 1
fi

if [[ "${1:-}" == "--list-slots" ]]; then
  shift
  exec Rscript "$CLI" list-slots --catalog "$CATALOG" "$@"
fi

exec Rscript "$CLI" search --catalog "$CATALOG" "$@"
