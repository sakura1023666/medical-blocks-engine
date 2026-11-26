#!/usr/bin/env bash
# ICUAKI unit-harmonized FULL retrain on 192.168.68.29 (GPU1 preferred).
# Does NOT overwrite legacy Output_database_pooling / summary_results.
# Writes:
#   blendedlos_icuaaki_units/
#   Output_database_pooling_units/
#   Output_paper_extras_units/
#   summary_results_units/   (after finalize)
set -euo pipefail

ROOT=/mnt/sda/BlendedICU/data/icuaaki_4db_20261106
SRC_DATA=$ROOT/blendedlos_icuaaki
DATA=$ROOT/blendedlos_icuaaki_units
MAIN_OUT=$ROOT/Output_database_pooling_units
EXTRA_OUT=$ROOT/Output_paper_extras_units
LOGDIR=$ROOT/logs/units_retrain
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Prefer sofa2 tree (has upstream/BlendedLoS)
BLOCK78=/mnt/sda/liver_sofa2_train/Blocks/78_database_pooling_full
SCRIPT=$BLOCK78/scripts/run_dbpool_experiment.py
HARMONIZE=$BLOCK78/scripts/harmonize_blendedlos_units.py
EXTEND=$BLOCK78/scripts/extend_easl_splits_all4.py
CI=$BLOCK78/scripts/eval_liver_paper_ci.py
PY="${PY:-/home/ps/anaconda3/envs/torch/bin/python}"
GPU="${CUDA_VISIBLE_DEVICES:-1}"

mkdir -p "$LOGDIR" "$MAIN_OUT" "$EXTRA_OUT"

export CUDA_VISIBLE_DEVICES="$GPU"
export DBPOOL_FULL_EPOCHS=1
export DBPOOL_PHYSIO_CLIP=1
export DBPOOL_DROP_TS="creatinine,urine_output"
unset DBPOOL_SKIP_UNITS_GATE || true
unset DBPOOL_FAST_TRAIN || true
unset DBPOOL_N_EPOCHS || true
unset DBPOOL_MAX_N_BATCH || true
unset DBPOOL_TRAIN_STAYS_PER_DB || true
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

log() { echo "$(date -Iseconds) $*"; }

if [[ ! -x $PY ]]; then
  echo "missing python: $PY" >&2
  exit 1
fi
if [[ ! -f $SCRIPT || ! -f $HARMONIZE ]]; then
  echo "missing engine scripts under $BLOCK78/scripts" >&2
  exit 1
fi

log "==== 1) seed units tree from previous assemble (no wipe of SRC) ===="
if [[ ! -d $SRC_DATA/preprocessed_timeseries ]]; then
  echo "missing source data $SRC_DATA — rsync from 34 first" >&2
  exit 1
fi
mkdir -p "$DATA"
# Fresh copy so legacy blendedlos_icuaaki stays mg/dL/g×100 for audit
if [[ ! -f $DATA/preprocessed_labels.parquet ]]; then
  log "rsync $SRC_DATA -> $DATA"
  rsync -a --delete "$SRC_DATA"/ "$DATA"/
else
  log "units tree exists; will re-harmonize in place"
fi

log "==== 2) engine unit harmonize + gate ===="
"$PY" -u "$HARMONIZE" --root "$DATA" --dbs amsterdam,mimic4,eicu,hirid \
  2>&1 | tee "$LOGDIR/harmonize_$(date +%Y%m%d_%H%M%S).log"

# Prefer local extend if Block78 copy missing
if [[ ! -f $EXTEND && -f $ROOT/scripts/extend_easl_splits_all4.py ]]; then
  EXTEND=$ROOT/scripts/extend_easl_splits_all4.py
fi
if [[ ! -f $CI && -f $ROOT/scripts/eval_liver_paper_ci.py ]]; then
  CI=$ROOT/scripts/eval_liver_paper_ci.py
fi

run_unit() {
  local unit="$1" wdir="$2"
  mkdir -p "$wdir"
  log "START $unit -> $wdir GPU=$CUDA_VISIBLE_DEVICES"
  "$PY" -u "$SCRIPT" --unit "$unit" --blended-out "$DATA" --work-dir "$wdir" \
    2>&1 | tee "$LOGDIR/${unit}_$(date +%Y%m%d_%H%M%S).log"
  local ec=${PIPESTATUS[0]}
  log "EXIT $unit ec=$ec"
  return $ec
}

log "==== 3) Main four arms ===="
run_unit liver_expA_amsterdam_solo "$MAIN_OUT/liver_expA_amsterdam_solo"
run_unit liver_expB_mimic_solo "$MAIN_OUT/liver_expB_mimic_solo"
run_unit liver_expC_mimic2amsterdam_transfer "$MAIN_OUT/liver_expC_mimic2amsterdam_transfer"
run_unit liver_expD_pooled_mimic_amsterdam "$MAIN_OUT/liver_expD_pooled_mimic_amsterdam"

log "==== 4) paper extras (equal-n / dataset / model / size) ===="
if [[ -f $EXTEND ]]; then
  "$PY" "$EXTEND" --blended-out "$DATA" | tee "$LOGDIR/extend_$(date +%Y%m%d_%H%M%S).log"
fi
MIN_TRAIN=$("$PY" - <<PY
import json
from pathlib import Path
p = Path("$DATA") / "split_summary_all4.json"
if not p.exists():
  p = Path("$DATA") / "split_summary.json"
s = json.loads(p.read_text())
dbs=("amsterdam","mimic4","eicu","hirid")
vals=[]
for d in dbs:
  if d in s and "persons" in s[d] and "train" in s[d]["persons"]:
    vals.append(s[d]["persons"]["train"])
print(min(v for v in vals if v>0) if vals else 0)
PY
)
log "MIN_TRAIN_PER_DB=$MIN_TRAIN"
echo "MIN_TRAIN_PER_DB=$MIN_TRAIN DROP=$DBPOOL_DROP_TS UNITS=harmonized" > "$EXTRA_OUT/FEATURE_GATE.txt"

if [[ "${MIN_TRAIN}" -gt 0 ]]; then
  export DBPOOL_TRAIN_STAYS_PER_DB="$MIN_TRAIN"
  run_unit liver_model_benchmark_equaln "$EXTRA_OUT/liver_model_benchmark_equaln" || true
  unset DBPOOL_TRAIN_STAYS_PER_DB
fi
run_unit liver_dataset_benchmark "$EXTRA_OUT/liver_dataset_benchmark" || true
run_unit liver_model_benchmark "$EXTRA_OUT/liver_model_benchmark" || true
run_unit liver_training_size_study "$EXTRA_OUT/liver_training_size_study" || true

log "==== 5) CI ===="
if [[ -f $CI ]]; then
  for u in liver_model_benchmark_equaln liver_dataset_benchmark liver_model_benchmark liver_training_size_study; do
    if [[ -d $EXTRA_OUT/$u/results ]]; then
      "$PY" "$CI" --root "$EXTRA_OUT" --units "$u" --n-boot 2000 --out "$EXTRA_OUT/ci_$u" \
        2>&1 | tee "$LOGDIR/ci_${u}_$(date +%Y%m%d_%H%M%S).log" || true
    fi
  done
  "$PY" "$CI" --root "$MAIN_OUT" \
    --units liver_expA_amsterdam_solo,liver_expB_mimic_solo,liver_expC_mimic2amsterdam_transfer,liver_expD_pooled_mimic_amsterdam \
    --n-boot 2000 --out "$EXTRA_OUT/ci_main_four_arms" \
    2>&1 | tee "$LOGDIR/ci_main_$(date +%Y%m%d_%H%M%S).log" || true
fi

date -Iseconds > "$LOGDIR/DONE.time"
log "ALL_DONE units retrain (legacy Output_* untouched)"
