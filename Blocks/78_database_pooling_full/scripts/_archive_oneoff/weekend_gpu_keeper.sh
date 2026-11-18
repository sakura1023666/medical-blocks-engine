#!/bin/bash
# Weekend keep-busy: whenever a local GPU is free, launch the next unfinished
# physclip unit. Run one copy per machine (29: GPUs 0,1; 34: GPU 0).
# Unix LF only. DBPOOL_PHYSIO_CLIP=1 always.
set -u
HOST_TAG="${1:-local}"
PY=""
for cand in \
  /home/ps/anaconda3/envs/torch/bin/python \
  /home/ps/miniconda3/envs/blendedlos/bin/python \
  /home/ps/miniconda3/envs/torch/bin/python; do
  if [ -x "$cand" ] && "$cand" -c "import torch" >/dev/null 2>&1; then
    PY=$cand; break
  fi
done
[ -n "$PY" ] || { echo "no torch python"; exit 1; }

SCRIPT=/mnt/sda/liver_sofa2_train/Blocks/78_database_pooling_full/scripts/run_dbpool_experiment.py
LOGDIR=/mnt/sda/liver_easl_paper_extras/logs_physclip_queue
mkdir -p "$LOGDIR"
LOCKDIR=$LOGDIR/locks
mkdir -p "$LOCKDIR"

export DBPOOL_PHYSIO_CLIP=1
export DBPOOL_FULL_EPOCHS=1
unset DBPOOL_FAST_TRAIN DBPOOL_N_EPOCHS DBPOOL_MAX_N_BATCH
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

log() { echo "$(date -Iseconds) [$HOST_TAG] $*"; }

has_metrics() {
  # $1 root dir containing results/**/metrics_multitask.csv
  find "$1" -name metrics_multitask.csv 2>/dev/null | grep -q .
}

cohort_root() {
  case "$1" in
    acg_bili) echo /mnt/sda/BlendedICU/data/liver_dysfunction_acg_bili_42151996 ;;
    mars) echo /mnt/sda/BlendedICU/data/liver_dysfunction_mars_42151996 ;;
    sofa1) echo /mnt/sda/BlendedICU/data/liver_dysfunction_sofa1_42151996 ;;
    sofa2) echo /mnt/sda/BlendedICU/data/liver_dysfunction_sofa2_42151996 ;;
    acg) echo /mnt/sda/BlendedICU/data/liver_dysfunction_acg_42151996 ;;
    full_icu) echo /mnt/sda/BlendedICU/data/blendedlos_full_icu_42151996 ;;
    *) return 1 ;;
  esac
}

cohort_data() {
  case "$1" in
    acg_bili) echo "$(cohort_root "$1")/blendedlos_acg_bili" ;;
    mars) echo "$(cohort_root "$1")/blendedlos_mars" ;;
    sofa1) echo "$(cohort_root "$1")/blendedlos_sofa1" ;;
    sofa2) echo "$(cohort_root "$1")/blendedlos_sofa2" ;;
    acg) echo "$(cohort_root "$1")/blendedlos_acg" ;;
    full_icu) echo "$(cohort_root "$1")/blendedlos_full" ;;
  esac
}

cohort_drop() {
  case "$1" in
    acg_bili) echo "bilirubine,alanine_aminotransferase,aspartate_aminotransferase" ;;
    mars|sofa1|sofa2) echo "bilirubine" ;;
    acg) echo "alanine_aminotransferase,aspartate_aminotransferase" ;;
    full_icu) echo "" ;;
  esac
}

# ALLOWED_COHORTS="acg_bili mars"  (space-separated). Default = all.
ALLOWED_COHORTS="${ALLOWED_COHORTS:-acg_bili mars sofa1 sofa2 acg full_icu}"

# Emit pending jobs as: COHORT|UNIT|KIND
# KIND=main|extra  (main under Output_physclip, extra under Output_paper_extras_physclip)
list_pending() {
  local c root data main extra
  for c in $ALLOWED_COHORTS; do
    root=$(cohort_root "$c") || continue
    data=$(cohort_data "$c")
    [ -d "$data/extraction/train_on_amsterdam/train/labels.parquet" ] || [ -d "$data/extraction/train_on_mimic4/train" ] || continue
    [ -f "$data/preprocessed_labels.parquet" ] || continue
    main=$root/Output_physclip
    extra=$root/Output_paper_extras_physclip
    for unit in \
      liver_expA_amsterdam_solo \
      liver_expB_mimic_solo \
      liver_expC_mimic2amsterdam_transfer \
      liver_expD_pooled_mimic_amsterdam; do
      if ! has_metrics "$main/$unit"; then
        echo "$c|$unit|main"
      fi
    done
    for unit in \
      liver_model_benchmark_equaln \
      liver_dataset_benchmark \
      liver_model_benchmark \
      liver_training_size_study; do
      if ! has_metrics "$extra/$unit"; then
        echo "$c|$unit|extra"
      fi
    done
  done
}

free_gpu() {
  # print first GPU index with mem used < 900 MiB
  nvidia-smi --query-gpu=index,memory.used --format=csv,noheader,nounits \
    | awk -F', ' '$2+0 < 900 {print $1; exit}'
}

gpu_busy() {
  local g="$1"
  # any python training using this CUDA device? approximate: mem >= 900
  local mem
  mem=$(nvidia-smi --query-gpu=index,memory.used --format=csv,noheader,nounits \
    | awk -F', ' -v g="$g" '$1+0==g+0 {print $2+0; exit}')
  [ "${mem:-0}" -ge 900 ]
}

try_lock() {
  local key="$1"
  local lf="$LOCKDIR/${key}.lock"
  if mkdir "$lf" 2>/dev/null; then
    echo "$$ $(hostname) $(date -Iseconds)" > "$lf/owner"
    return 0
  fi
  # stale lock > 12h
  if [ -d "$lf" ]; then
    local age
    age=$(( $(date +%s) - $(stat -c %Y "$lf" 2>/dev/null || echo 0) ))
    if [ "$age" -gt 43200 ]; then
      rm -rf "$lf"
      mkdir "$lf" 2>/dev/null || return 1
      echo "$$ stale-taken $(date -Iseconds)" > "$lf/owner"
      return 0
    fi
  fi
  return 1
}

release_lock() {
  rm -rf "$LOCKDIR/${1}.lock" 2>/dev/null || true
}

run_job() {
  local gpu="$1" cohort="$2" unit="$3" kind="$4"
  local root data drop wdir key
  root=$(cohort_root "$cohort")
  data=$(cohort_data "$cohort")
  drop=$(cohort_drop "$cohort")
  if [ "$kind" = main ]; then
    wdir=$root/Output_physclip/$unit
  else
    wdir=$root/Output_paper_extras_physclip/$unit
  fi
  key="${cohort}__${unit}"
  try_lock "$key" || { log "skip locked $key"; return 1; }

  # re-check after lock
  if has_metrics "$wdir"; then
    log "already done $key"
    release_lock "$key"
    return 1
  fi

  mkdir -p "$(dirname "$wdir")"
  log "LAUNCH gpu=$gpu $key -> $wdir"
  (
    export CUDA_VISIBLE_DEVICES="$gpu"
    export DBPOOL_PHYSIO_CLIP=1
    export DBPOOL_FULL_EPOCHS=1
    if [ -n "$drop" ]; then export DBPOOL_DROP_TS="$drop"; else unset DBPOOL_DROP_TS; fi
    if [ "$unit" = "liver_model_benchmark_equaln" ]; then
      local min
      min=$("$PY" - <<PY
import json
from pathlib import Path
p=Path("$data")/"split_summary_all4.json"
if not p.exists():
    print(0)
else:
    s=json.loads(p.read_text())
    print(min(s[d]["persons"]["train"] for d in ("amsterdam","mimic4","eicu","hirid")))
PY
)
      export DBPOOL_TRAIN_STAYS_PER_DB="$min"
    else
      unset DBPOOL_TRAIN_STAYS_PER_DB
    fi
    "$PY" "$SCRIPT" --unit "$unit" --blended-out "$data" --work-dir "$wdir"
    ec=$?
    echo "$(date -Iseconds) EXIT $key ec=$ec" >> "$LOGDIR/weekend_keeper_${HOST_TAG}.log"
    # mark cohort done if all main+extra present
    if has_metrics "$root/Output_physclip/liver_expD_pooled_mimic_amsterdam" \
      && has_metrics "$root/Output_paper_extras_physclip/liver_training_size_study"; then
      date -Iseconds > "$LOGDIR/${cohort}_DONE.time"
    fi
    release_lock "$key"
    exit $ec
  ) > "$LOGDIR/weekend_${HOST_TAG}_${key}_gpu${gpu}_$(date +%Y%m%d_%H%M%S).log" 2>&1 &
  echo $!
}

log "keeper start host=$(hostname) py=$PY allowed=[$ALLOWED_COHORTS]"
# kill old useless waiters on this host
pkill -f 'requeue_acg_bili_mars' 2>/dev/null || true

# Discover local GPU count
NGPU=$(nvidia-smi -L 2>/dev/null | wc -l)
[ "$NGPU" -ge 1 ] || { log "no GPU"; exit 1; }

while true; do
  # On 34: after acg_bili+mars fully done, unlock full_icu help (29 owns full_icu first)
  if [ "$HOST_TAG" = "34" ]; then
    if [ -f "$LOGDIR/acg_bili_DONE.time" ] && [ -f "$LOGDIR/mars_DONE.time" ]; then
      if [[ " $ALLOWED_COHORTS " != *" full_icu "* ]]; then
        ALLOWED_COHORTS="$ALLOWED_COHORTS full_icu"
        log "unlocked full_icu after acg_bili+mars DONE"
      fi
    fi
  fi
  pending=$(list_pending | head -40)
  if [ -z "$pending" ]; then
    log "queue empty; sleep 600"
    sleep 600
    continue
  fi

  for g in $(seq 0 $((NGPU - 1))); do
    if gpu_busy "$g"; then
      continue
    fi
    # pick first pending not locked
    launched=0
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      c=${line%%|*}; rest=${line#*|}; u=${rest%%|*}; k=${rest##*|}
      key="${c}__${u}"
      [ -d "$LOCKDIR/${key}.lock" ] && continue
      root=$(cohort_root "$c")
      if [ "$k" = main ]; then wdir=$root/Output_physclip/$u; else wdir=$root/Output_paper_extras_physclip/$u; fi
      has_metrics "$wdir" && continue
      pid=$(run_job "$g" "$c" "$u" "$k" || true)
      if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
        log "spawned pid=$pid gpu=$g $key"
        launched=1
        sleep 15  # let mem climb before next GPU assign
        break
      fi
    done <<< "$pending"
    [ "$launched" = 1 ] || true
  done
  sleep 90
done
