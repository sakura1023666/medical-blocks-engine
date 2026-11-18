#!/usr/bin/env bash
# Mild-denoise Allyn pool train (mortality AUROC primary).
set -euo pipefail
ROOT=/mnt/sda/csaaki_gongqian_train
BLENDED=/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996/blendedlos_csaaki
OUT=/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996/Output_database_pooling_allyn_mild
KEEP=/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996/feature_screen_allyn_mild/csaaki_allyn_mild_keep_vars.txt
PY=/mnt/sda/csaaki_gongqian_train/.venv_csaaki/bin/python
LOGDIR=$ROOT/logs
mkdir -p "$LOGDIR" "$OUT"

if [[ ! -f "$KEEP" ]]; then
  echo "[ERR] missing KEEP list: $KEEP" >&2
  exit 1
fi

export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0}"
export DBPOOL_KEEP_TS="$KEEP"
unset DBPOOL_DROP_TS || true

echo "[allyn_mild] KEEP=$(wc -l < "$KEEP") vars"
echo "[allyn_mild] OUT=$OUT"
cd "$ROOT/BlendedICU"
exec "$PY" -u -m TPC.train \
  --dataset_dir "$BLENDED" \
  --output_dir "$OUT" \
  --task multitask \
  --model TPC \
  --seed 974 \
  2>&1 | tee "$LOGDIR/train_allyn_mild.log"
