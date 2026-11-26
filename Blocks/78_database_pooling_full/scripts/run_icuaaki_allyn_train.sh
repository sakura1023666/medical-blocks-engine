#!/usr/bin/env bash
# ICUAKI DN=1 4-arm train on 34 (single GPU sequential).
# Stage1+Stage2 QC must PASS before this.
set -euo pipefail

ROOT=/mnt/sda/BlendedICU/data/icuaaki_4db_20261106
DATA=$ROOT/blendedlos_icuaaki
OUT=$ROOT/Output_database_pooling
LOGDIR=$ROOT/logs/train
# reuse installed Block78 tree (has BlendedLoS upstream)
SCRIPT=/mnt/sda/liver_sofa2_train/Blocks/78_database_pooling_full/scripts/run_dbpool_experiment.py
PY=/home/ps/miniconda3/envs/blendedlos/bin/python

mkdir -p "$OUT" "$LOGDIR"

export DBPOOL_FULL_EPOCHS=1
export DBPOOL_PHYSIO_CLIP=1
export DBPOOL_DROP_TS="creatinine,urine_output"
unset DBPOOL_FAST_TRAIN || true
unset DBPOOL_N_EPOCHS || true
unset DBPOOL_MAX_N_BATCH || true
unset DBPOOL_TRAIN_STAYS_PER_DB || true
export CUDA_VISIBLE_DEVICES=0

log() { echo "$(date -Iseconds) $*"; }

run_unit() {
  local unit="$1"
  local wdir="$OUT/$unit"
  mkdir -p "$wdir"
  log "START unit=$unit -> $wdir"
  "$PY" -u "$SCRIPT" --unit "$unit" --blended-out "$DATA" --work-dir "$wdir" \
    2>&1 | tee "$LOGDIR/${unit}_$(date +%Y%m%d_%H%M%S).log"
  local ec=${PIPESTATUS[0]}
  log "EXIT unit=$unit ec=$ec"
  return $ec
}

log "ICUAKI 4-arm train begin DATA=$DATA"
run_unit liver_expA_amsterdam_solo
run_unit liver_expB_mimic_solo
run_unit liver_expC_mimic2amsterdam_transfer
run_unit liver_expD_pooled_mimic_amsterdam
log "ALL FOUR ARMS DONE"
