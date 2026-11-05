#!/bin/bash
# Mild denoise of Allyn full pool, then same CSA-AKI TPC units as other arms.
set -u
PY=/home/ps/miniconda3/envs/blendedlos/bin/python
LOG=/mnt/sda/csaaki_gongqian_train/logs_allyn_mild
SCR=/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996/feature_screen_allyn_mild
mkdir -p "$LOG" "$SCR"
echo "SCREEN_START $(date -Iseconds)" | tee "$LOG/master.log"
"$PY" -u /mnt/sda/csaaki_gongqian_train/screen_csaaki_allyn_mild_denoise.py \
  --min-cov-med 0.05 \
  > "$LOG/screen.log" 2>&1
ec=$?
echo "SCREEN_EXIT $ec $(date -Iseconds)" | tee -a "$LOG/master.log"
if [ "$ec" -ne 0 ]; then exit "$ec"; fi
KEEP_FILE="$SCR/csaaki_allyn_mild_keep_vars.txt"
test -s "$KEEP_FILE"
echo "KEEP_N=$(wc -l < "$KEEP_FILE")" | tee -a "$LOG/master.log"
cat "$KEEP_FILE" | tee -a "$LOG/master.log"

export CUDA_VISIBLE_DEVICES=0
export DBPOOL_FULL_EPOCHS=1
export DBPOOL_DROP_TS="urine_output,creatinine"
export DBPOOL_KEEP_TS="$(tr '\n' ',' < "$KEEP_FILE" | sed 's/,$//')"
unset DBPOOL_FAST_TRAIN
unset DBPOOL_TRAIN_STAYS_PER_DB
unset DBPOOL_N_EPOCHS
unset DBPOOL_MAX_N_BATCH
ROOT=/mnt/sda/csaaki_gongqian_train/Blocks/78_database_pooling_full/scripts/run_dbpool_experiment.py
DATA=/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996/blendedlos_csaaki
OUT=/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996/Output_database_pooling_allyn_mild
mkdir -p "$OUT"
{
  echo "ARM=csaaki_allyn_mild_denoise"
  echo "DROP=$DBPOOL_DROP_TS"
  echo "KEEP=$DBPOOL_KEEP_TS"
  echo "gates=Allyn keep=1 minus Cr/UO; drop meds not in BOTH train DBs (cov>=0.05); drop asymmetric train (max>=0.50 & min<0.05); NO UV/VIF/LASSO; NO ext/SMD hard gates"
} > "$OUT/FEATURE_GATE.txt"
"$PY" -c "import torch; assert torch.cuda.is_available(); print('cuda_ok', torch.cuda.get_device_name(0))"
UNITS=(
  csa_expA_sicdb_solo
  csa_expB_mimic_solo
  csa_expC_mimic2sicdb_transfer
  csa_expD_pooled_mimic_sicdb
  csa_model_benchmark
)
for u in "${UNITS[@]}"; do
  echo "START $u $(date -Iseconds)" | tee -a "$LOG/master.log"
  "$PY" -u "$ROOT" --unit "$u" --blended-out "$DATA" --work-dir "$OUT/$u" > "$LOG/${u}.log" 2>&1
  ec=$?
  echo "EXIT $u $ec $(date -Iseconds)" | tee -a "$LOG/master.log"
  if [ "$ec" -ne 0 ]; then echo "STOP_ON_FAIL $u" | tee -a "$LOG/master.log"; exit "$ec"; fi
done
echo "ALL_DONE_ALLYN_MILD $(date -Iseconds)" | tee -a "$LOG/master.log"
