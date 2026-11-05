#!/bin/bash
# Wait until TARGET_LOCAL, then freeze+prepare+physclip-train four ULN cohorts on GPU 0.
# Order: smallest first (all3 → bili → alt → ast).
set -u
TARGET_LOCAL="${TARGET_LOCAL:-2026-11-06 00:00:00}"
GPU="${GPU:-0}"
PY=/home/ps/miniconda3/envs/blendedlos/bin/python
SCRIPT_DIR=/mnt/sda/liver_sofa2_train/Blocks/78_database_pooling_full/scripts
LOGDIR=/mnt/sda/liver_easl_paper_extras/logs_uln_four
mkdir -p "$LOGDIR"
LOG=$LOGDIR/schedule_$(date +%Y%m%d_%H%M%S).log
exec > >(tee -a "$LOG") 2>&1

log() { echo "$(date -Iseconds) $*"; }

log "SCHEDULED target=$TARGET_LOCAL gpu=$GPU"
TARGET_TS=$(date -d "$TARGET_LOCAL" +%s)
NOW=$(date +%s)
SLEEP=$((TARGET_TS - NOW))
if [ "$SLEEP" -gt 0 ]; then
  log "sleep ${SLEEP}s until $TARGET_LOCAL"
  sleep "$SLEEP"
else
  log "target already passed; start after GPU free"
fi

# wait until no other dbpool / TPC trainer holds the GPU (allow idle keeper)
wait_gpu() {
  local i=0
  while true; do
    if pgrep -f 'run_dbpool_experiment.py|run_one_cohort_physclip.sh|_run_one.py' >/dev/null 2>&1; then
      i=$((i + 1))
      if [ $((i % 10)) -eq 1 ]; then
        log "GPU busy (other dbpool); waiting… ($i)"
      fi
      sleep 60
      continue
    fi
    # memory used < 2GB roughly free
    used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits -i "$GPU" 2>/dev/null | head -1 | tr -d ' ')
    used=${used:-99999}
    if [ "$used" -lt 2500 ]; then
      log "GPU $GPU free (mem_used=${used}MiB)"
      return 0
    fi
    i=$((i + 1))
    if [ $((i % 10)) -eq 1 ]; then
      log "GPU mem_used=${used}MiB; waiting… ($i)"
    fi
    sleep 60
  done
}

wait_gpu

log "FREEZE four ULN cohorts"
"$PY" "$SCRIPT_DIR/freeze_liver_uln_four.py" | tee "$LOGDIR/freeze_$(date +%Y%m%d_%H%M%S).log"

# smallest → largest
for COHORT in uln_all3 uln_bili uln_alt uln_ast; do
  log "======== PREPARE $COHORT ========"
  "$PY" "$SCRIPT_DIR/prepare_liver_uln_cohort.py" --cohort "$COHORT" \
    | tee "$LOGDIR/${COHORT}_prepare_$(date +%Y%m%d_%H%M%S).log"

  # optional QC rebuild if script present
  if [ -f "$SCRIPT_DIR/liver_cohort_qc_rebuild.py" ]; then
    ROOT=$(case "$COHORT" in
      uln_ast) echo /mnt/sda/BlendedICU/data/liver_dysfunction_uln_ast_42151996 ;;
      uln_alt) echo /mnt/sda/BlendedICU/data/liver_dysfunction_uln_alt_42151996 ;;
      uln_bili) echo /mnt/sda/BlendedICU/data/liver_dysfunction_uln_bili_42151996 ;;
      uln_all3) echo /mnt/sda/BlendedICU/data/liver_dysfunction_uln_all3_42151996 ;;
    esac)
    OUTNAME=$(case "$COHORT" in
      uln_ast) echo blendedlos_uln_ast ;;
      uln_alt) echo blendedlos_uln_alt ;;
      uln_bili) echo blendedlos_uln_bili ;;
      uln_all3) echo blendedlos_uln_all3 ;;
    esac)
    log "QC/rebuild $COHORT"
    "$PY" "$SCRIPT_DIR/liver_cohort_qc_rebuild.py" --root "$ROOT" --out-name "$OUTNAME" \
      | tee "$LOGDIR/${COHORT}_qc_$(date +%Y%m%d_%H%M%S).log" || log "QC warn ec=$?"
  fi

  log "======== TRAIN $COHORT on GPU $GPU ========"
  bash "$SCRIPT_DIR/run_one_cohort_physclip.sh" "$COHORT" "$GPU" \
    | tee "$LOGDIR/${COHORT}_train_$(date +%Y%m%d_%H%M%S).log" \
    || log "TRAIN warn cohort=$COHORT ec=$?"
  date -Iseconds > "$LOGDIR/${COHORT}_DONE.time"
done

date -Iseconds > "$LOGDIR/ALL_FOUR_DONE.time"
log "ALL_FOUR_DONE"
