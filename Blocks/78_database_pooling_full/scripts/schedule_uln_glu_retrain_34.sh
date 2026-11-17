#!/bin/bash
# ULN-triple full retrain AFTER permanent MIMIC blood_glucose → mmol/L.
# - Does NOT touch existing Output_physclip / summary_results_uln_triple
# - Writes Output_physclip_glu_mmol + pack → summary(new)
# - Fig2 stay-level pinned to Table3 Gen (engine finalize)
set -u
GPU="${GPU:-0}"
OUT_TAG="${OUT_TAG:-physclip_glu_mmol}"
export OUT_TAG
PY=""
for cand in \
  /home/ps/anaconda3/envs/torch/bin/python \
  /home/ps/miniconda3/envs/blendedlos/bin/python \
  /home/ps/miniconda3/envs/torch/bin/python; do
  if [ -x "$cand" ] && "$cand" -c "import torch" >/dev/null 2>&1; then
    PY=$cand
    break
  fi
done
if [ -z "$PY" ]; then
  echo "FATAL: no python with torch" >&2
  exit 1
fi
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGDIR=/mnt/sda/liver_easl_paper_extras/logs_uln_glu_retrain
mkdir -p "$LOGDIR"
LOG=$LOGDIR/schedule_$(date +%Y%m%d_%H%M%S).log
exec > >(tee -a "$LOG") 2>&1

log() { echo "$(date -Iseconds) $*"; }

# Delivery paths (never overwrite legacy ULN triple pack)
PUB_34="/mnt/sda/liver_uln_pub/summary(new)"
STAGING_34="/mnt/sda/liver_uln_pub/_staging_uln_sens_new"
PUB_G="/mnt/g/02block_result/50_Cirrhosis/database_pooled_42151996/summary(new)"
export ULN_TRIPLE_PUB_OUT="$PUB_34"
export ULN_TRIPLE_STAGING="$STAGING_34"
export ULN_FORCE_MAIN=1
export ULN_FORCE_SENS=1
export MEDICAL_BLOCKS_ROOT="${MEDICAL_BLOCKS_ROOT:-/mnt/sda/liver_sofa2_train}"

log "BEGIN OUT_TAG=$OUT_TAG GPU=$GPU PY=$PY"
log "torch=$($PY -c 'import torch; print(torch.__version__)')"

# 1) Full unit harmonize (glucose mmol/L + hemoglobin g/dL) — idempotent gate
log "======== HARMONIZE units (glucose+Hb) on blendedlos_ready ========"
"$PY" -u "$SCRIPT_DIR/harmonize_blendedlos_units.py" \
  --root /mnt/sda/BlendedICU/data/blendedlos_ready \
  | tee "$LOGDIR/units_harmonize_$(date +%Y%m%d_%H%M%S).log"
"$PY" -u "$SCRIPT_DIR/harmonize_blendedlos_units.py" \
  --root /mnt/sda/BlendedICU/data/blendedlos_ready --assert-only \
  | tee -a "$LOGDIR/units_harmonize_$(date +%Y%m%d_%H%M%S).log"

# 2) Wait for GPU memory
wait_gpu() {
  local i=0
  while true; do
    if pgrep -f 'run_dbpool_experiment.py|run_one_cohort_physclip.sh' >/dev/null 2>&1; then
      i=$((i + 1))
      [ $((i % 10)) -eq 1 ] && log "other dbpool busy; waiting… ($i)"
      sleep 60
      continue
    fi
    used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits -i "$GPU" 2>/dev/null | head -1 | tr -d ' ')
    used=${used:-99999}
    # allow up to ~12GB used by idle services; need headroom for TPC
    if [ "$used" -lt 20000 ]; then
      log "GPU $GPU usable (mem_used=${used}MiB)"
      return 0
    fi
    i=$((i + 1))
    [ $((i % 10)) -eq 1 ] && log "GPU mem_used=${used}MiB; waiting… ($i)"
    sleep 60
  done
}
wait_gpu

# 3) Train four cohorts → new Output_*_${OUT_TAG} (legacy Output_physclip untouched)
#    FAIL_FAST=1: any arm failure aborts (do not fake ALL_DONE)
export FAIL_FAST=1
for COHORT in uln_all3 uln_bili uln_alt uln_ast; do
  log "======== TRAIN $COHORT OUT_TAG=$OUT_TAG ========"
  if ! OUT_TAG="$OUT_TAG" FAIL_FAST=1 bash "$SCRIPT_DIR/run_one_cohort_physclip.sh" "$COHORT" "$GPU" \
    | tee "$LOGDIR/${COHORT}_train_$(date +%Y%m%d_%H%M%S).log"; then
    log "FATAL TRAIN cohort=$COHORT — stop schedule"
    exit 1
  fi
  date -Iseconds > "$LOGDIR/${COHORT}_DONE.time"
done

# 4) Cross-eval into new extras dirs
log "======== CROSS EVAL ========"
export OUT_TAG
if ! bash "$SCRIPT_DIR/run_uln_cross_eval_four.sh" \
  | tee "$LOGDIR/cross_$(date +%Y%m%d_%H%M%S).log"; then
  log "FATAL CROSS"
  exit 1
fi

# 5) Pack to summary(new) on 34
log "======== PACK summary(new) ========"
if ! "$PY" -u "$SCRIPT_DIR/pack_uln_triple_summary.py" \
  | tee "$LOGDIR/pack_$(date +%Y%m%d_%H%M%S).log"; then
  log "FATAL PACK"
  exit 1
fi

# 6) Mirror to G: delivery if mounted
if [ -d "/mnt/g/02block_result/50_Cirrhosis/database_pooled_42151996" ]; then
  log "======== MIRROR → $PUB_G ========"
  mkdir -p "$PUB_G"
  rsync -a --delete "$PUB_34"/ "$PUB_G"/ || log "rsync warn ec=$?"
else
  log "G: not mounted on 34; leave pack at $PUB_34"
fi

date -Iseconds > "$LOGDIR/ALL_GLU_RETRAIN_DONE.time"
log "ALL_GLU_RETRAIN_DONE PUB=$PUB_34"
log "legacy untouched: summary_results_uln_triple + Output_physclip"
