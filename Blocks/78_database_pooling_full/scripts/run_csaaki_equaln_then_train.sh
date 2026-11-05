#!/bin/bash
# CSA-AKI: Allyn full pool + equal-n per DB (cap = min train DB size).
# Hypothesis: D≈B because SICdb is only ~13%; balancing gives SICdb equal voice.
set -u
PY=/home/ps/miniconda3/envs/blendedlos/bin/python
LOG=/mnt/sda/csaaki_gongqian_train/logs_equaln
DATA=/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996/blendedlos_csaaki
OUT=/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996/Output_database_pooling_equaln
ROOT=/mnt/sda/csaaki_gongqian_train/Blocks/78_database_pooling_full/scripts/run_dbpool_experiment.py
mkdir -p "$LOG" "$OUT"

MIN_TRAIN=$("$PY" - <<'PY'
import pandas as pd
from pathlib import Path
lab = pd.read_parquet(
    "/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996/blendedlos_csaaki/"
    "extraction/train_on_mimic4_sicdb/train/labels.parquet"
)
if "source_dataset" not in lab.columns:
    lab = lab.copy()
    lab["source_dataset"] = lab.index.astype(str).str.split("-").str[0]
print(int(lab.groupby("source_dataset").size().min()))
PY
)

echo "EQUALN_START $(date -Iseconds)" | tee "$LOG/master.log"
echo "MIN_TRAIN_PER_DB=$MIN_TRAIN" | tee -a "$LOG/master.log"

export CUDA_VISIBLE_DEVICES=0
export DBPOOL_FULL_EPOCHS=1
export DBPOOL_DROP_TS="urine_output,creatinine"
export DBPOOL_TRAIN_STAYS_PER_DB="$MIN_TRAIN"
unset DBPOOL_KEEP_TS || true
unset DBPOOL_FAST_TRAIN || true
unset DBPOOL_N_EPOCHS || true
unset DBPOOL_MAX_N_BATCH || true

{
  echo "ARM=csaaki_allyn_equaln"
  echo "DROP=$DBPOOL_DROP_TS"
  echo "KEEP=Allyn keep=1 (no whitelist)"
  echo "DBPOOL_TRAIN_STAYS_PER_DB=$MIN_TRAIN"
  echo "note=cap each source_dataset in train/val/test splits to MIN_TRAIN (seed 974); D≈747 mimic+747 sicdb; B≈747 mimic"
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
echo "ALL_DONE_EQUALN $(date -Iseconds)" | tee -a "$LOG/master.log"
