#!/bin/bash
# CSA-AKI prognostic-feature arm (does NOT overwrite Allyn-pool Output_database_pooling).
set -u
export CUDA_VISIBLE_DEVICES=0
export DBPOOL_FULL_EPOCHS=1
export DBPOOL_DROP_TS="urine_output,creatinine"
KEEP_FILE="${KEEP_FILE:-/mnt/sda/csaaki_gongqian_train/csaaki_prognostic_keep_vars.txt}"
export DBPOOL_KEEP_TS="$(tr '\n' ',' < "$KEEP_FILE" | sed 's/,$//')"
unset DBPOOL_FAST_TRAIN
unset DBPOOL_TRAIN_STAYS_PER_DB
unset DBPOOL_N_EPOCHS
unset DBPOOL_MAX_N_BATCH

PY=/home/ps/miniconda3/envs/blendedlos/bin/python
ROOT=/mnt/sda/csaaki_gongqian_train/Blocks/78_database_pooling_full/scripts/run_dbpool_experiment.py
DATA=/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996/blendedlos_csaaki
OUT=/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996/Output_database_pooling_prognostic
LOGDIR=/mnt/sda/csaaki_gongqian_train/logs_prognostic
mkdir -p "$OUT" "$LOGDIR"

{
  echo "ARM=csaaki_prognostic_best"
  echo "DROP=$DBPOOL_DROP_TS"
  echo "KEEP=$DBPOOL_KEEP_TS"
  echo "note: same BlendedLoS tree as Allyn arm; model inputs restricted by KEEP whitelist"
  echo "lit: reports/tst_feature_lit_csaaki_prognostic_2026-11-04.md"
} > "$OUT/FEATURE_GATE.txt"

"$PY" -c "import torch; assert torch.cuda.is_available(); print('cuda_ok', torch.cuda.get_device_name(0))"

# Fair head-to-head on main Table3-style arms + architecture benchmark (skip size sweep for speed).
UNITS=(
  csa_expA_sicdb_solo
  csa_expB_mimic_solo
  csa_expC_mimic2sicdb_transfer
  csa_expD_pooled_mimic_sicdb
  csa_model_benchmark
)

: > "$LOGDIR/master_prognostic.log"
for u in "${UNITS[@]}"; do
  echo "START $u $(date -Iseconds)" | tee -a "$LOGDIR/master_prognostic.log"
  "$PY" -u "$ROOT" --unit "$u" --blended-out "$DATA" --work-dir "$OUT/$u" \
    > "$LOGDIR/${u}.log" 2>&1
  ec=$?
  echo "EXIT $u $ec $(date -Iseconds)" | tee -a "$LOGDIR/master_prognostic.log"
  if [ "$ec" -ne 0 ]; then
    echo "STOP_ON_FAIL $u" | tee -a "$LOGDIR/master_prognostic.log"
    exit "$ec"
  fi
done
echo "ALL_DONE_PROGNOSTIC $(date -Iseconds)" | tee -a "$LOGDIR/master_prognostic.log"
