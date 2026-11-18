#!/usr/bin/env bash
# Amsterdam↔MIMIC cross-eval for all four ULN cohorts, then rebuild Table 3 / S4/S6/S8.
set -euo pipefail
PY="${PY:-/home/ps/miniconda3/envs/blendedlos/bin/python}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGDIR="${LOGDIR:-/mnt/sda/liver_easl_paper_extras/logs_uln_four}"
mkdir -p "$LOGDIR"
LOG="$LOGDIR/cross_eval_uln_four_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
echo "[start] $LOG"

cross_one() {
  local key="$1" root="$2" blended="$3" drop="$4"
  echo "======== cross $key ========"
  export LIVER_ROOT="$root"
  export LIVER_BLENDED_SUBDIR="$blended"
  export DBPOOL_DROP_TS="$drop"
  export DBPOOL_PHYSIO_CLIP=1
  "$PY" -u "$SCRIPT_DIR/cross_eval_ams_mimic.py"
}

cross_one all3 \
  /mnt/sda/BlendedICU/data/liver_dysfunction_uln_all3_42151996 \
  blendedlos_uln_all3 \
  "aspartate_aminotransferase,alanine_aminotransferase,bilirubine"

cross_one bili \
  /mnt/sda/BlendedICU/data/liver_dysfunction_uln_bili_42151996 \
  blendedlos_uln_bili \
  "bilirubine"

cross_one alt \
  /mnt/sda/BlendedICU/data/liver_dysfunction_uln_alt_42151996 \
  blendedlos_uln_alt \
  "alanine_aminotransferase"

cross_one ast \
  /mnt/sda/BlendedICU/data/liver_dysfunction_uln_ast_42151996 \
  blendedlos_uln_ast \
  "aspartate_aminotransferase"

echo "======== rebuild Table3 pack ========"
export ULN_TRIPLE_PUB_OUT="${ULN_TRIPLE_PUB_OUT:-/mnt/sda/liver_uln_pub/summary_results_uln_triple}"
"$PY" -u "$SCRIPT_DIR/refresh_uln_table3_after_cross.py"

echo "[done] $LOG"
echo "ALL_CROSS_DONE $(date -Iseconds)"
