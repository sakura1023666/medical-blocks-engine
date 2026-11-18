#!/bin/bash
# Full EASL/DILI retrain with MOESM1 physiological clip → q5/q95 → [-4,4],
# then CI + finalize into summary_results.
# Run on 29 (2×GPU). Optional: set RUN_ON_34=1 and start resume script on 34 for eICU/HiRID.
# Unix LF only.
set -u
PY=/home/ps/anaconda3/envs/torch/bin/python
SCRIPT_DIR=/mnt/sda/liver_sofa2_train/Blocks/78_database_pooling_full/scripts
SCRIPT=$SCRIPT_DIR/run_dbpool_experiment.py
CI=$SCRIPT_DIR/eval_liver_paper_ci.py
FINAL=$SCRIPT_DIR/finalize_easl_paper_pub.py
EXTEND=$SCRIPT_DIR/extend_easl_splits_all4.py
EASL_ROOT=/mnt/sda/BlendedICU/data/liver_dysfunction_easl_dili_42151996
DATA=$EASL_ROOT/blendedlos_easl_dili
MAIN_OUT=$EASL_ROOT/Output_physclip
OUT=$EASL_ROOT/Output_paper_extras_physclip
LOGDIR=/mnt/sda/liver_easl_paper_extras/logs_physclip
PUB_LOCAL=$EASL_ROOT/summary_results
mkdir -p "$LOGDIR" "$MAIN_OUT" "$OUT" "$PUB_LOCAL"

export DBPOOL_FULL_EPOCHS=1
export DBPOOL_DROP_TS="alanine_aminotransferase,alkaline_phosphatase"
unset DBPOOL_FAST_TRAIN
unset DBPOOL_N_EPOCHS
unset DBPOOL_MAX_N_BATCH
unset DBPOOL_TRAIN_STAYS_PER_DB

log() { echo "$(date -Iseconds) $*"; }

run_unit() {
  local gpu="$1" unit="$2" wdir="$3"
  (
    export CUDA_VISIBLE_DEVICES="$gpu"
    export DBPOOL_DROP_TS DBPOOL_FULL_EPOCHS
    log "START gpu=$gpu unit=$unit -> $wdir"
    "$PY" "$SCRIPT" --unit "$unit" --blended-out "$DATA" --work-dir "$wdir"
    ec=$?
    log "EXIT gpu=$gpu unit=$unit ec=$ec"
    exit $ec
  )
}

# --- 0) extend splits (idempotent) ---
log "phase0 extend splits"
"$PY" "$EXTEND" | tee "$LOGDIR/extend_splits_$(date +%Y%m%d_%H%M%S).log" || true
MIN_TRAIN=$("$PY" - <<'PY'
import json
from pathlib import Path
p=Path("/mnt/sda/BlendedICU/data/liver_dysfunction_easl_dili_42151996/blendedlos_easl_dili/split_summary_all4.json")
if not p.exists():
    print(0); raise SystemExit
s=json.loads(p.read_text())
print(min(s[d]["persons"]["train"] for d in ("amsterdam","mimic4","eicu","hirid")))
PY
)
log "MIN_TRAIN_PER_DB=$MIN_TRAIN"

# --- 1) main four arms (A||B then C||D) ---
log "phase1 main arms A||B"
run_unit 0 liver_expA_amsterdam_solo "$MAIN_OUT/liver_expA_amsterdam_solo" \
  > "$LOGDIR/expA_$(date +%Y%m%d_%H%M%S).log" 2>&1 &
PID_A=$!
run_unit 1 liver_expB_mimic_solo "$MAIN_OUT/liver_expB_mimic_solo" \
  > "$LOGDIR/expB_$(date +%Y%m%d_%H%M%S).log" 2>&1 &
PID_B=$!
wait $PID_A; EC_A=$?
wait $PID_B; EC_B=$?
log "phase1 done A=$EC_A B=$EC_B"

log "phase1b main arms C||D"
run_unit 0 liver_expC_mimic2amsterdam_transfer "$MAIN_OUT/liver_expC_mimic2amsterdam_transfer" \
  > "$LOGDIR/expC_$(date +%Y%m%d_%H%M%S).log" 2>&1 &
PID_C=$!
run_unit 1 liver_expD_pooled_mimic_amsterdam "$MAIN_OUT/liver_expD_pooled_mimic_amsterdam" \
  > "$LOGDIR/expD_$(date +%Y%m%d_%H%M%S).log" 2>&1 &
PID_D=$!
wait $PID_C; EC_C=$?
wait $PID_D; EC_D=$?
log "phase1b done C=$EC_C D=$EC_D"

# --- 2) equal-n + dataset_benchmark + model_benchmark + size study ---
log "phase2 extras"
(
  export CUDA_VISIBLE_DEVICES=0
  export DBPOOL_TRAIN_STAYS_PER_DB="$MIN_TRAIN"
  export DBPOOL_DROP_TS DBPOOL_FULL_EPOCHS
  log "START equaln"
  "$PY" "$SCRIPT" --unit liver_model_benchmark_equaln --blended-out "$DATA" \
    --work-dir "$OUT/liver_model_benchmark_equaln"
  log "EXIT equaln $?"
) > "$LOGDIR/equaln_$(date +%Y%m%d_%H%M%S).log" 2>&1 &
PID_EQ=$!

(
  export CUDA_VISIBLE_DEVICES=1
  unset DBPOOL_TRAIN_STAYS_PER_DB
  export DBPOOL_DROP_TS DBPOOL_FULL_EPOCHS
  log "START dataset_benchmark"
  "$PY" "$SCRIPT" --unit liver_dataset_benchmark --blended-out "$DATA" \
    --work-dir "$OUT/liver_dataset_benchmark"
  log "EXIT dataset_benchmark $?"
  log "START model_benchmark"
  "$PY" "$SCRIPT" --unit liver_model_benchmark --blended-out "$DATA" \
    --work-dir "$OUT/liver_model_benchmark"
  log "EXIT model_benchmark $?"
  log "START training_size_study"
  "$PY" "$SCRIPT" --unit liver_training_size_study --blended-out "$DATA" \
    --work-dir "$OUT/liver_training_size_study"
  log "EXIT training_size_study $?"
) > "$LOGDIR/extras_gpu1_$(date +%Y%m%d_%H%M%S).log" 2>&1 &
PID_EX=$!

wait $PID_EQ; EC_EQ=$?
wait $PID_EX; EC_EX=$?
log "phase2 done equaln=$EC_EQ extras=$EC_EX"

# --- 3) CI ---
log "phase3 CI"
export EASL_MAIN_OUT="$MAIN_OUT"
export EASL_EXTRA_OUT="$OUT"
"$PY" "$CI" --root "$MAIN_OUT" \
  --units liver_expA_amsterdam_solo,liver_expB_mimic_solo,liver_expC_mimic2amsterdam_transfer,liver_expD_pooled_mimic_amsterdam \
  --n-boot 10000 --out "$OUT/ci_main_four_arms" || true
for u in liver_model_benchmark liver_model_benchmark_equaln liver_training_size_study liver_dataset_benchmark; do
  if [ -d "$OUT/$u/results" ]; then
    "$PY" "$CI" --root "$OUT" --units "$u" --n-boot 10000 --out "$OUT/ci_$u" || true
  fi
done

# --- 4) finalize ---
log "phase4 finalize"
export EASL_ROOT
export EASL_MAIN_OUT="$MAIN_OUT"
export EASL_EXTRA_OUT="$OUT"
export LIVER_PUB_OUT="$PUB_LOCAL"
"$PY" "$FINAL" | tee "$LOGDIR/finalize_$(date +%Y%m%d_%H%M%S).log"

for dest in \
  /mnt/g/02block_result/50_Cirrhosis/database_pooled_42151996/summary_results \
  /mnt/133/02block_result/50_Cirrhosis/database_pooled_42151996/summary_results
do
  if mkdir -p "$dest" 2>/dev/null; then
    rsync -a --delete "$PUB_LOCAL/" "$dest/" && log "synced $dest" || log "sync fail $dest"
  fi
done

echo "$PUB_LOCAL" > "$LOGDIR/PUBLISH_READY.path"
date -Iseconds > "$LOGDIR/PUBLISH_READY.time"
log "ALL_DONE A=$EC_A B=$EC_B C=$EC_C D=$EC_D equaln=$EC_EQ extras=$EC_EX pub=$PUB_LOCAL"
exit 0
