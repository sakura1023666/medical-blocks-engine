#!/bin/bash
# CSA-AKI 3-DB: MIMIC+eICU pool, INSPIRE external (no SICdb). Allyn full features.
set -u
PY=/home/ps/miniconda3/envs/blendedlos/bin/python
LOG=/mnt/sda/csaaki_gongqian_train/logs_mimic_eicu
DATA=/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996/blendedlos_csaaki
OUT=/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996/Output_database_pooling_mimic_eicu
ROOT=/mnt/sda/csaaki_gongqian_train/Blocks/78_database_pooling_full/scripts/run_dbpool_experiment.py
PREP=/mnt/sda/csaaki_gongqian_train/Blocks/78_database_pooling_full/scripts/prepare_csaaki_mimic_eicu_splits.py
mkdir -p "$LOG" "$OUT"

echo "CSA3_START $(date -Iseconds)" | tee "$LOG/master.log"
"$PY" -u "$PREP" 2>&1 | tee "$LOG/prepare_splits.log"
ec=$?
echo "PREPARE_EXIT $ec $(date -Iseconds)" | tee -a "$LOG/master.log"
if [ "$ec" -ne 0 ]; then exit "$ec"; fi
test -s "$DATA/extraction/train_on_eicu_mimic4/train/labels.parquet"

export CUDA_VISIBLE_DEVICES=0
export DBPOOL_FULL_EPOCHS=1
export DBPOOL_DROP_TS="urine_output,creatinine"
unset DBPOOL_KEEP_TS || true
unset DBPOOL_TRAIN_STAYS_PER_DB || true
unset DBPOOL_FAST_TRAIN || true
unset DBPOOL_N_EPOCHS || true
unset DBPOOL_MAX_N_BATCH || true

{
  echo "ARM=csaaki_mimic_eicu_3db"
  echo "DROP=$DBPOOL_DROP_TS"
  echo "KEEP=Allyn keep=1 (no whitelist)"
  echo "train=MIMIC+eICU; external=INSPIRE (+train-DB holdouts); no SICdb"
  echo "units=csa3_expA_eicu_solo,csa3_expB_mimic_solo,csa3_expC_mimic2eicu_transfer,csa3_expD_pooled_mimic_eicu,csa3_model_benchmark"
} > "$OUT/FEATURE_GATE.txt"

"$PY" -c "import torch; assert torch.cuda.is_available(); print('cuda_ok', torch.cuda.get_device_name(0))"

UNITS=(
  csa3_expA_eicu_solo
  csa3_expB_mimic_solo
  csa3_expC_mimic2eicu_transfer
  csa3_expD_pooled_mimic_eicu
  csa3_model_benchmark
)
for u in "${UNITS[@]}"; do
  echo "START $u $(date -Iseconds)" | tee -a "$LOG/master.log"
  "$PY" -u "$ROOT" --unit "$u" --blended-out "$DATA" --work-dir "$OUT/$u" > "$LOG/${u}.log" 2>&1
  ec=$?
  echo "EXIT $u $ec $(date -Iseconds)" | tee -a "$LOG/master.log"
  if [ "$ec" -ne 0 ]; then echo "STOP_ON_FAIL $u" | tee -a "$LOG/master.log"; exit "$ec"; fi
done
echo "ALL_DONE_CSA3_MIMIC_EICU $(date -Iseconds)" | tee -a "$LOG/master.log"
