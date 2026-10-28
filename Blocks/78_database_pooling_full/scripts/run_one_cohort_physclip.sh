#!/bin/bash
# One liver-rule cohort: MOESM1 physio clip ON, inclusion features dropped per RULE.
# Args: COHORT_KEY  GPU_ID
# COHORT_KEY: mars|acg|acg_bili|sofa1|sofa2|full_icu
set -u
COHORT="${1:?cohort}"
GPU="${2:?gpu}"
PY=""
for cand in \
  /home/ps/anaconda3/envs/torch/bin/python \
  /home/ps/miniconda3/envs/blendedlos/bin/python \
  /home/ps/miniconda3/envs/torch/bin/python \
  /home/ps/anaconda3/envs/blendedlos/bin/python; do
  if [ -x "$cand" ] && "$cand" -c "import torch" >/dev/null 2>&1; then
    PY=$cand
    break
  fi
done
if [ -z "$PY" ]; then
  echo "FATAL: no python with torch" >&2
  exit 1
fi
SCRIPT_DIR=/mnt/sda/liver_sofa2_train/Blocks/78_database_pooling_full/scripts
SCRIPT=$SCRIPT_DIR/run_dbpool_experiment.py
CI=$SCRIPT_DIR/eval_liver_paper_ci.py
EXTEND=$SCRIPT_DIR/extend_easl_splits_all4.py

case "$COHORT" in
  mars)
    ROOT=/mnt/sda/BlendedICU/data/liver_dysfunction_mars_42151996
    DATA=$ROOT/blendedlos_mars
    DROP=bilirubine
    ;;
  acg)
    ROOT=/mnt/sda/BlendedICU/data/liver_dysfunction_acg_42151996
    DATA=$ROOT/blendedlos_acg
    DROP=alanine_aminotransferase,aspartate_aminotransferase
    ;;
  acg_bili)
    ROOT=/mnt/sda/BlendedICU/data/liver_dysfunction_acg_bili_42151996
    DATA=$ROOT/blendedlos_acg_bili
    DROP=bilirubine,alanine_aminotransferase,aspartate_aminotransferase
    ;;
  sofa1)
    ROOT=/mnt/sda/BlendedICU/data/liver_dysfunction_sofa1_42151996
    DATA=$ROOT/blendedlos_sofa1
    DROP=bilirubine
    ;;
  sofa2)
    ROOT=/mnt/sda/BlendedICU/data/liver_dysfunction_sofa2_42151996
    DATA=$ROOT/blendedlos_sofa2
    DROP=bilirubine
    ;;
  full_icu)
    ROOT=/mnt/sda/BlendedICU/data/blendedlos_full_icu_42151996
    DATA=$ROOT/blendedlos_full
    DROP=
    ;;
  *)
    echo "unknown cohort $COHORT" >&2
    exit 2
    ;;
esac

MAIN_OUT=$ROOT/Output_physclip
OUT=$ROOT/Output_paper_extras_physclip
LOGDIR=/mnt/sda/liver_easl_paper_extras/logs_physclip_queue
mkdir -p "$LOGDIR" "$MAIN_OUT" "$OUT"

export CUDA_VISIBLE_DEVICES="$GPU"
export DBPOOL_FULL_EPOCHS=1
export DBPOOL_PHYSIO_CLIP=1
export DBPOOL_DROP_TS="$DROP"
unset DBPOOL_FAST_TRAIN DBPOOL_N_EPOCHS DBPOOL_MAX_N_BATCH DBPOOL_TRAIN_STAYS_PER_DB
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

log() { echo "$(date -Iseconds) [$COHORT gpu=$GPU] $*"; }

run_unit() {
  local unit="$1" wdir="$2"
  log "START $unit -> $wdir"
  "$PY" "$SCRIPT" --unit "$unit" --blended-out "$DATA" --work-dir "$wdir"
  local ec=$?
  log "EXIT $unit ec=$ec"
  return $ec
}

log "BEGIN physclip DROP=[$DROP] data=$DATA"
echo "DBPOOL_PHYSIO_CLIP=1 DROP=$DROP" > "$MAIN_OUT/PHYSIO_CLIP.txt"
echo "DROP=$DROP" > "$MAIN_OUT/DROPPED_FEATURES.txt"

# extend four-DB splits (idempotent)
"$PY" "$EXTEND" --blended-out "$DATA" | tee "$LOGDIR/${COHORT}_extend_$(date +%Y%m%d_%H%M%S).log"
MIN_TRAIN=$("$PY" - <<PY
import json
from pathlib import Path
p=Path("$DATA")/"split_summary_all4.json"
if not p.exists():
    print(0); raise SystemExit
s=json.loads(p.read_text())
print(min(s[d]["persons"]["train"] for d in ("amsterdam","mimic4","eicu","hirid")))
PY
)
log "MIN_TRAIN_PER_DB=$MIN_TRAIN"

# main four arms sequential on this GPU (A→B→C→D)
run_unit liver_expA_amsterdam_solo "$MAIN_OUT/liver_expA_amsterdam_solo" || true
run_unit liver_expB_mimic_solo "$MAIN_OUT/liver_expB_mimic_solo" || true
run_unit liver_expC_mimic2amsterdam_transfer "$MAIN_OUT/liver_expC_mimic2amsterdam_transfer" || true
run_unit liver_expD_pooled_mimic_amsterdam "$MAIN_OUT/liver_expD_pooled_mimic_amsterdam" || true

# extras
export DBPOOL_TRAIN_STAYS_PER_DB="$MIN_TRAIN"
run_unit liver_model_benchmark_equaln "$OUT/liver_model_benchmark_equaln" || true
unset DBPOOL_TRAIN_STAYS_PER_DB
run_unit liver_dataset_benchmark "$OUT/liver_dataset_benchmark" || true
run_unit liver_model_benchmark "$OUT/liver_model_benchmark" || true
run_unit liver_training_size_study "$OUT/liver_training_size_study" || true

# CI
log "CI"
"$PY" "$CI" --root "$MAIN_OUT" \
  --units liver_expA_amsterdam_solo,liver_expB_mimic_solo,liver_expC_mimic2amsterdam_transfer,liver_expD_pooled_mimic_amsterdam \
  --n-boot 10000 --out "$OUT/ci_main_four_arms" || true
for u in liver_model_benchmark liver_model_benchmark_equaln liver_training_size_study liver_dataset_benchmark; do
  if [ -d "$OUT/$u/results" ]; then
    "$PY" "$CI" --root "$OUT" --units "$u" --n-boot 10000 --out "$OUT/ci_$u" || true
  fi
done

date -Iseconds > "$LOGDIR/${COHORT}_DONE.time"
echo "$MAIN_OUT" > "$LOGDIR/${COHORT}_DONE.path"
log "ALL_DONE cohort=$COHORT"
exit 0
