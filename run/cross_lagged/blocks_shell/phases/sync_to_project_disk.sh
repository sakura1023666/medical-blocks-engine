#!/usr/bin/env bash
# 将交叉滞后 study 工作目录镜像到课题盘（02block_result 等）。
# 用法:
#   bash sync_to_project_disk.sh <SRC_STUDY_ROOT> [DEST_SYNC_ROOT]
# 环境变量:
#   CROSS_LAGGED_SYNC_ROOT   优先作为 DEST（含空格路径时推荐只靠 env）
#   CROSS_LAGGED_SYNC_DELETE 设为 1 时对 summary_result / phase* 做 --delete 镜像
# 跳过 data/（多为原始/共享数据或 symlink，课题盘通常已有）
set -euo pipefail

SRC="${1:-}"
# 路径含空格时：优先 env（R 侧 setenv），避免 argv 被误拆
DEST="${CROSS_LAGGED_SYNC_ROOT:-}"
if [[ -z "$DEST" && $# -ge 2 ]]; then
  # 拼接 $2 及之后直到看起来不像下一选项（兼容空格路径误拆）
  shift
  DEST="$*"
fi

if [[ -z "$SRC" || ! -d "$SRC" ]]; then
  echo "sync_to_project_disk: SRC 无效: ${SRC:-<empty>}" >&2
  exit 1
fi

# 从 SRC 内指针文件读 DEST
if [[ -z "$DEST" ]]; then
  for f in CROSS_LAGGED_SYNC_ROOT sync_to.txt .sync_to; do
    if [[ -f "$SRC/$f" ]]; then
      DEST="$(head -n 1 "$SRC/$f" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [[ -n "$DEST" ]] && break
    fi
  done
fi

if [[ -z "$DEST" ]]; then
  echo "sync_to_project_disk: 未指定 DEST（传第 2 参 / 设 CROSS_LAGGED_SYNC_ROOT / 写 SRC/CROSS_LAGGED_SYNC_ROOT）" >&2
  exit 1
fi

SRC="$(cd -- "$SRC" && { pwd -P 2>/dev/null || pwd; })"
mkdir -p -- "$DEST"
DEST="$(cd -- "$DEST" && { pwd -P 2>/dev/null || pwd; })"

if [[ "$SRC" == "$DEST" ]]; then
  echo "sync_to_project_disk: SRC 已在课题盘 ($SRC)，跳过"
  exit 0
fi

# 可写探测
if ! touch -- "$DEST/.cross_lagged_sync_probe_$$" 2>/dev/null; then
  echo "sync_to_project_disk: DEST 不可写: $DEST" >&2
  exit 1
fi
rm -f -- "$DEST/.cross_lagged_sync_probe_$$"

echo "======== sync_to_project_disk ========"
echo "SRC : $SRC"
echo "DEST: $DEST"
ts="$(date -Iseconds)"

_sync_one() {
  local rel="$1"
  local s="$SRC/$rel"
  local d="$DEST/$rel"
  [[ -e "$s" ]] || return 0
  if command -v rsync >/dev/null 2>&1; then
    if [[ -d "$s" ]]; then
      mkdir -p -- "$d"
      local del=()
      if [[ "${CROSS_LAGGED_SYNC_DELETE:-0}" == "1" ]]; then
        del=(--delete)
      fi
      rsync -a "${del[@]}" --exclude 'checkpoints/' "$s/" "$d/"
    else
      mkdir -p -- "$(dirname -- "$d")"
      rsync -a "$s" "$d"
    fi
  else
    if [[ -d "$s" ]]; then
      mkdir -p -- "$d"
      cp -a "$s"/. "$d"/ 2>/dev/null || cp -a "$s" "$d"
    else
      mkdir -p -- "$(dirname -- "$d")"
      cp -a "$s" "$d"
    fi
  fi
  echo "  + $rel"
}

# 优先保证 summary 与产出目录；排除 data/
_sync_one "summary_result"

shopt -s nullglob
for p in "$SRC"/phase1_* "$SRC"/phase2_* "$SRC"/phase3_*; do
  [[ -e "$p" ]] || continue
  _sync_one "$(basename "$p")"
done
for p in "$SRC"/config_phase*.R \
         "$SRC"/*_acceptance.txt \
         "$SRC"/mediation_depression_covar_lock.* \
         "$SRC"/cohort_*.txt \
         "$SRC"/README*.txt \
         "$SRC"/WHERE*.txt \
         "$SRC"/CROSS_LAGGED_SYNC_ROOT \
         "$SRC"/sync_to.txt; do
  [[ -e "$p" ]] || continue
  _sync_one "$(basename "$p")"
done
shopt -u nullglob

{
  echo "mirrored_from=$SRC"
  echo "mirrored_to=$DEST"
  echo "synced_at=$ts"
  echo "policy=exclude data/ and phase*/checkpoints (CROSS_LAGGED_SYNC_CHECKPOINTS=1 to include)"
} > "$DEST/LAST_SYNC_FROM_ENGINE.txt"

if [[ "${CROSS_LAGGED_SYNC_CHECKPOINTS:-0}" == "1" ]]; then
  shopt -s nullglob
  for p in "$SRC"/phase1_* "$SRC"/phase2_* "$SRC"/phase3_*; do
    bn="$(basename "$p")"
    if [[ -d "$p/checkpoints" ]]; then
      mkdir -p -- "$DEST/$bn/checkpoints"
      if command -v rsync >/dev/null 2>&1; then
        rsync -a "$p/checkpoints/" "$DEST/$bn/checkpoints/"
      else
        cp -a "$p/checkpoints/." "$DEST/$bn/checkpoints/" 2>/dev/null || true
      fi
      echo "  + $bn/checkpoints"
    fi
  done
  shopt -u nullglob
fi

echo "DONE sync → $DEST"
echo "  summary_result: $(ls -1 "$DEST/summary_result/table" 2>/dev/null | wc -l) tables, $(ls -1 "$DEST/summary_result/figure" 2>/dev/null | wc -l) figures"
exit 0
