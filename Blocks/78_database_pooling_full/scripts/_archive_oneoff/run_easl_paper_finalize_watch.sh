#!/bin/bash
# Wait for current EASL extras, then equal-n + dataset_benchmark, CI, publish to 133 share.
# Run on 29 only. (Unix LF only — do not save as CRLF.)
set -u
PY=/home/ps/anaconda3/envs/torch/bin/python
SCRIPT_DIR=/mnt/sda/liver_sofa2_train/Blocks/78_database_pooling_full/scripts
SCRIPT=$SCRIPT_DIR/run_dbpool_experiment.py
CI=$SCRIPT_DIR/eval_liver_paper_ci.py
FINAL=$SCRIPT_DIR/finalize_easl_paper_pub.py
EXTEND=$SCRIPT_DIR/extend_easl_splits_all4.py
EASL_ROOT=/mnt/sda/BlendedICU/data/liver_dysfunction_easl_dili_42151996
DATA=$EASL_ROOT/blendedlos_easl_dili
MAIN_OUT=$EASL_ROOT/Output_noenzyme
OUT=$EASL_ROOT/Output_paper_extras
LOGDIR=/mnt/sda/liver_easl_paper_extras/logs
PUB_LOCAL=$EASL_ROOT/summary_results
mkdir -p "$LOGDIR" "$OUT" "$PUB_LOCAL"

export DBPOOL_FULL_EPOCHS=1
export DBPOOL_DROP_TS="alanine_aminotransferase,alkaline_phosphatase"
unset DBPOOL_FAST_TRAIN
unset DBPOOL_N_EPOCHS
unset DBPOOL_MAX_N_BATCH

log() { echo "$(date -Iseconds) $*"; }

# --- 1) wait for current orchestrator / GPU jobs ---
log "phase1 wait current extras"
while pgrep -f run_easl_paper_extras.sh >/dev/null 2>&1; do sleep 60; done
while pgrep -af run_dbpool_experiment | grep -E 'liver_model_benchmark|liver_training_size_study' | grep -v grep >/dev/null 2>&1; do
  log "still run_dbpool model/size..."
  sleep 120
done
while pgrep -af _run_one.py | grep -E 'Output_paper_extras/(liver_model_benchmark|liver_training_size_study)' | grep -v grep >/dev/null 2>&1; do
  log "still training model/size _run_one..."
  sleep 120
done
log "phase1 done"

# --- 2) extend splits for eICU/HiRID trainable + four-DB ---
log "phase2 extend splits"
"$PY" "$EXTEND" | tee "$LOGDIR/extend_splits_$(date +%Y%m%d_%H%M%S).log"
MIN_TRAIN=$("$PY" - <<'PY'
import json
from pathlib import Path
s=json.loads(Path("/mnt/sda/BlendedICU/data/liver_dysfunction_easl_dili_42151996/blendedlos_easl_dili/split_summary_all4.json").read_text())
print(min(s[d]["persons"]["train"] for d in ("amsterdam","mimic4","eicu","hirid")))
PY
)
export DBPOOL_TRAIN_STAYS_PER_DB="$MIN_TRAIN"
log "DBPOOL_TRAIN_STAYS_PER_DB=$DBPOOL_TRAIN_STAYS_PER_DB"

# --- 3) equal-n three models (GPU0) + dataset benchmark (GPU1) ---
log "phase3 equaln + dataset_benchmark"
(
  export CUDA_VISIBLE_DEVICES=0
  export DBPOOL_TRAIN_STAYS_PER_DB
  export DBPOOL_DROP_TS DBPOOL_FULL_EPOCHS
  log "START equaln"
  "$PY" "$SCRIPT" --unit liver_model_benchmark_equaln --blended-out "$DATA" \
    --work-dir "$OUT/liver_model_benchmark_equaln"
  log "EXIT equaln $?"
) > "$LOGDIR/equaln_$(date +%Y%m%d_%H%M%S).log" 2>&1 &
PID0=$!

(
  export CUDA_VISIBLE_DEVICES=1
  unset DBPOOL_TRAIN_STAYS_PER_DB
  export DBPOOL_DROP_TS DBPOOL_FULL_EPOCHS
  log "START dataset_benchmark"
  "$PY" "$SCRIPT" --unit liver_dataset_benchmark --blended-out "$DATA" \
    --work-dir "$OUT/liver_dataset_benchmark"
  log "EXIT dataset_benchmark $?"
) > "$LOGDIR/dataset_bench_$(date +%Y%m%d_%H%M%S).log" 2>&1 &
PID1=$!

wait $PID0; EC0=$?
wait $PID1; EC1=$?
log "phase3 done equaln=$EC0 dataset=$EC1"

# --- 4) CI on all available units ---
log "phase4 CI"
"$PY" "$CI" --root "$MAIN_OUT" \
  --units liver_expA_amsterdam_solo,liver_expB_mimic_solo,liver_expC_mimic2amsterdam_transfer,liver_expD_pooled_mimic_amsterdam \
  --n-boot 10000 --out "$OUT/ci_main_four_arms" || true
for u in liver_model_benchmark liver_model_benchmark_equaln liver_training_size_study liver_dataset_benchmark; do
  if [ -d "$OUT/$u/results" ]; then
    "$PY" "$CI" --root "$OUT" --units "$u" --n-boot 10000 --out "$OUT/ci_$u" || true
  fi
done

# --- 5) finalize publication locally then try sync to 133 mount if present ---
log "phase5 finalize"
export EASL_ROOT=/mnt/sda/BlendedICU/data/liver_dysfunction_easl_dili_42151996
export LIVER_PUB_OUT="$PUB_LOCAL"
"$PY" "$FINAL" | tee "$LOGDIR/finalize_$(date +%Y%m%d_%H%M%S).log"

for dest in \
  /mnt/g/02block_result/50_Cirrhosis/database_pooled_42151996/summary_results \
  /mnt/133/02block_result/50_Cirrhosis/database_pooled_42151996/summary_results
do
  if [ -d "$(dirname "$dest")" ] || mkdir -p "$dest" 2>/dev/null; then
    if [ -d "$dest" ] || mkdir -p "$dest" 2>/dev/null; then
      rsync -a --delete "$PUB_LOCAL/" "$dest/" && log "synced $dest" || log "sync fail $dest"
    fi
  fi
done

echo "$PUB_LOCAL" > "$LOGDIR/PUBLISH_READY.path"
date -Iseconds > "$LOGDIR/PUBLISH_READY.time"
log "ALL_DONE equaln=$EC0 dataset=$EC1 pub=$PUB_LOCAL"
exit 0
