#!/usr/bin/env bash
# =============================================================================
#  deploy_block_hooks_to_studies.sh
#
#  Export read-only block catalog + copy programmer CLI wrappers to study areas
#  on DockerHome ports 5001 / 5003 / 5006.
#  Also create editable/ symlink to the sole writable engine block (index).
#
#  Usage (from repo root):
#    ./scripts/deploy_block_hooks_to_studies.sh
# =============================================================================
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER_SRC="${REPO}/configs/study_interface/programmer_cli"
EDITABLE_README_SRC="${REPO}/configs/study_interface/editable/README.md"
ENGINE="${MEDICAL_BLOCKS_ROOT:-${REPO}}"
export MEDICAL_BLOCKS_ROOT="$ENGINE"

if [[ ! -d "$WRAPPER_SRC" ]]; then
  echo "[错误] 缺少 wrapper 模板: $WRAPPER_SRC" >&2
  exit 1
fi

# Resolve engine root for a study area (engine.env MEDICAL_BLOCKS_ROOT, else REPO)
.resolve_engine_for_dest() {
  local dest="$1"
  local eng="${REPO}"
  if [[ -f "${dest}/engine.env" ]]; then
    # shellcheck disable=SC1090
    local line
    line="$(grep -E '^MEDICAL_BLOCKS_ROOT=' "${dest}/engine.env" | head -n1 | sed 's/\r$//' || true)"
    if [[ -n "$line" ]]; then
      eng="${line#MEDICAL_BLOCKS_ROOT=}"
      eng="${eng%\"}"
      eng="${eng#\"}"
      eng="${eng%\'}"
      eng="${eng#\'}"
    fi
  fi
  if [[ ! -d "$eng" ]]; then
    eng="${REPO}"
  fi
  printf '%s' "$eng"
}

for PORT in 5001 5003 5006; do
  DEST="/mnt/g/DockerHome/${PORT}/medical-blocks-studies"
  if [[ ! -d "$DEST" ]]; then
    echo "[警告] 跳过不存在的端口目录: $DEST" >&2
    continue
  fi

  echo "==> Deploy block hooks to ${DEST}"

  mkdir -p "${DEST}/docs/block_catalog"
  Rscript "${REPO}/scripts/export_block_catalog.R" \
    --out "${DEST}/docs/block_catalog" \
    "$REPO"

  cp "${WRAPPER_SRC}/_load_engine.sh" \
     "${WRAPPER_SRC}/search_blocks.sh" \
     "${WRAPPER_SRC}/add_block.sh" \
     "${WRAPPER_SRC}/remove_block.sh" \
     "${WRAPPER_SRC}/search_blocks.bat" \
     "${WRAPPER_SRC}/add_block.bat" \
     "${WRAPPER_SRC}/remove_block.bat" \
     "$DEST/"

  chmod +x \
    "${DEST}/search_blocks.sh" \
    "${DEST}/add_block.sh" \
    "${DEST}/remove_block.sh" \
    "${DEST}/_load_engine.sh"

  # ── 方案 B：唯一可写入口 → 引擎 index ─────────────────────────────────────
  PORT_ENGINE="$(.resolve_engine_for_dest "$DEST")"
  INDEX_SRC="${PORT_ENGINE}/Blocks/00_index/01block_index.R"
  mkdir -p "${DEST}/editable"
  if [[ -f "$EDITABLE_README_SRC" ]]; then
    cp "$EDITABLE_README_SRC" "${DEST}/editable/README.md"
  fi
  if [[ ! -f "$INDEX_SRC" ]]; then
    echo "[警告] 引擎 index 不存在，跳过链接: $INDEX_SRC" >&2
  else
    ln -sfn "$INDEX_SRC" "${DEST}/editable/01block_index.R"
    echo "    editable: ${DEST}/editable/01block_index.R -> ${INDEX_SRC}"
  fi

  echo "    catalog: ${DEST}/docs/block_catalog"
  echo "    wrappers: search_blocks, add_block, remove_block (.sh + .bat)"
done

echo "Done."
