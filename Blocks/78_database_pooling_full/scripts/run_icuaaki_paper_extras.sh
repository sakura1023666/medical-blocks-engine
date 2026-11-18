#!/usr/bin/env bash
# ICUAKI paper extras to match cirrhosis summary_results layout:
#   extend all4 splits → equal-n LSTM/Transformer/TPC → dataset benchmark
#   → model benchmark → training-size study → CI
set -euo pipefail

ROOT=/mnt/sda/BlendedICU/data/icuaaki_4db_20261106
DATA=$ROOT/blendedlos_icuaaki
MAIN_OUT=$ROOT/Output_database_pooling
OUT=$ROOT/Output_paper_extras
LOGDIR=$ROOT/logs/paper_extras
SCRIPT_DIR=$ROOT/scripts
# Must use Block78 tree that contains upstream/BlendedLoS (not the thin scripts/ copy).
SCRIPT=/mnt/sda/liver_sofa2_train/Blocks/78_database_pooling_full/scripts/run_dbpool_experiment.py
EXTEND=$SCRIPT_DIR/extend_easl_splits_all4.py
CI=$SCRIPT_DIR/eval_liver_paper_ci.py
PY=/home/ps/miniconda3/envs/blendedlos/bin/python
if [[ ! -f $SCRIPT ]]; then
  echo "missing BlendedLoS runner: $SCRIPT" >&2
  exit 1
fi

mkdir -p "$OUT" "$LOGDIR"

export DBPOOL_FULL_EPOCHS=1
export DBPOOL_PHYSIO_CLIP=1
export DBPOOL_DROP_TS="creatinine,urine_output"
export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0}"
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
unset DBPOOL_FAST_TRAIN || true
unset DBPOOL_N_EPOCHS || true
unset DBPOOL_MAX_N_BATCH || true
unset DBPOOL_TRAIN_STAYS_PER_DB || true

log() { echo "$(date -Iseconds) $*"; }

run_unit() {
  local unit="$1" wdir="$2"
  mkdir -p "$wdir"
  log "START $unit -> $wdir"
  "$PY" -u "$SCRIPT" --unit "$unit" --blended-out "$DATA" --work-dir "$wdir" \
    2>&1 | tee "$LOGDIR/${unit}_$(date +%Y%m%d_%H%M%S).log"
  local ec=${PIPESTATUS[0]}
  log "EXIT $unit ec=$ec"
  return $ec
}

log "ICUAKI paper extras BEGIN DATA=$DATA"
"$PY" "$EXTEND" --blended-out "$DATA" | tee "$LOGDIR/extend_$(date +%Y%m%d_%H%M%S).log"

MIN_TRAIN=$("$PY" - <<PY
import json
from pathlib import Path
p = Path("$DATA") / "split_summary_all4.json"
s = json.loads(p.read_text())
print(min(s[d]["persons"]["train"] for d in ("amsterdam", "mimic4", "eicu", "hirid")))
PY
)
log "MIN_TRAIN_PER_DB=$MIN_TRAIN"
echo "MIN_TRAIN_PER_DB=$MIN_TRAIN DROP=$DBPOOL_DROP_TS" > "$OUT/FEATURE_GATE.txt"

export DBPOOL_TRAIN_STAYS_PER_DB="$MIN_TRAIN"
run_unit liver_model_benchmark_equaln "$OUT/liver_model_benchmark_equaln"
unset DBPOOL_TRAIN_STAYS_PER_DB

run_unit liver_dataset_benchmark "$OUT/liver_dataset_benchmark"
run_unit liver_model_benchmark "$OUT/liver_model_benchmark"
run_unit liver_training_size_study "$OUT/liver_training_size_study"

log "CI extras"
for u in liver_model_benchmark_equaln liver_dataset_benchmark liver_model_benchmark liver_training_size_study; do
  if [[ -d $OUT/$u/results ]]; then
    "$PY" "$CI" --root "$OUT" --units "$u" --n-boot 2000 --out "$OUT/ci_$u" \
      2>&1 | tee "$LOGDIR/ci_${u}_$(date +%Y%m%d_%H%M%S).log" || true
  fi
done

# refresh main-arm CI with fixed DeLong (idempotent overwrite)
"$PY" "$CI" --root "$MAIN_OUT" \
  --units liver_expA_amsterdam_solo,liver_expB_mimic_solo,liver_expC_mimic2amsterdam_transfer,liver_expD_pooled_mimic_amsterdam \
  --n-boot 2000 --out "$OUT/ci_main_four_arms" \
  2>&1 | tee "$LOGDIR/ci_main_$(date +%Y%m%d_%H%M%S).log" || true

date -Iseconds > "$LOGDIR/DONE.time"
log "ALL_DONE paper extras"
