#!/bin/bash
# On 34 (RTX 5880 ~49GB): train eICU + HiRID dataset_benchmark at paper batch=32.
# Expects data/workdir already synced under EASL paths (same layout as 29).
# Refreshes _run_one.py from template (max_los×24 sequence cap; batch stays 32).
set -u
PY="${PY:-}"
if [ -z "$PY" ] || [ ! -x "$PY" ] || ! "$PY" -c "import torch" >/dev/null 2>&1; then
  for cand in \
    /home/ps/miniconda3/envs/blendedlos/bin/python \
    /home/ps/anaconda3/envs/torch/bin/python \
    /home/ps/miniconda3/envs/torch/bin/python \
    /home/ps/anaconda3/envs/blendedlos/bin/python \
    /opt/conda/envs/torch/bin/python \
    "$(command -v python3 2>/dev/null || true)" \
    "$(command -v python 2>/dev/null || true)"; do
    if [ -n "$cand" ] && [ -x "$cand" ]; then
      if "$cand" -c "import torch" >/dev/null 2>&1; then
        PY="$cand"
        break
      fi
    fi
  done
fi
if ! "$PY" -c "import torch" >/dev/null 2>&1; then
  echo "FATAL: no python with torch (tried $PY)" >&2
  exit 1
fi

EASL_ROOT=/mnt/sda/BlendedICU/data/liver_dysfunction_easl_dili_42151996
WD=$EASL_ROOT/Output_paper_extras/liver_dataset_benchmark
UP=/mnt/sda/liver_sofa2_train/Blocks/78_database_pooling_full/upstream/BlendedLoS
SCRIPT_DIR=/mnt/sda/liver_sofa2_train/Blocks/78_database_pooling_full/scripts
# fallback upstream on 34
if [ ! -d "$UP" ]; then
  UP=/home/ps/blendedlos_repro/BlendedLoS-master
fi
LOGDIR=/mnt/sda/liver_easl_paper_extras/logs
mkdir -p "$LOGDIR" "$WD" "$SCRIPT_DIR"

export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0}"
export DBPOOL_FULL_EPOCHS=1
export DBPOOL_DROP_TS="alanine_aminotransferase,alkaline_phosphatase"
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
unset DBPOOL_TRAIN_STAYS_PER_DB DBPOOL_FAST_TRAIN DBPOOL_MAX_N_BATCH DBPOOL_N_EPOCHS
BS=32

log() { echo "$(date -Iseconds) $*"; }

has_metrics() {
  local db="$1"
  find "$WD/results" -path "*/${db}_100/*/metrics_multitask.csv" 2>/dev/null | grep -q .
}

# Refresh _run_one.py from template (max_los×24 sequence cap; batch stays 32)
TPL=$SCRIPT_DIR/_run_one_template.py
if [ -f "$TPL" ]; then
  "$PY" - <<PY
from pathlib import Path
tpl = Path("$TPL").read_text(encoding="utf-8")
wd = Path("$WD")
up = Path("$UP")
cfg = wd / "config.json"
text = (
    tpl.replace("__CWD__", str(wd))
    .replace("__UPSTREAM__", str(up))
    .replace("__CONFIG__", str(cfg))
    .replace("__EXPERIMENTS__", repr(["dataset_benchmark"]))
)
(wd / "_run_one.py").write_text(text, encoding="utf-8")
print("wrote", wd / "_run_one.py")
PY
  log "refreshed _run_one.py from template (seq cap max_los*24)"
else
  log "WARN missing template $TPL — using existing _run_one.py"
fi

patch_and_run() {
  local DB="$1"
  local LOGF="$LOGDIR/dataset_bench_${DB}_bs${BS}_34_$(date +%Y%m%d_%H%M%S).log"
  log "START $DB batch=$BS on 34 log=$LOGF"
  cd "$WD"
  "$PY" - <<PY
import json
from pathlib import Path
p = Path("config.json")
c = json.loads(p.read_text())
c["experiments"]["dataset_benchmark"]["runs"] = [
    {"train_on": ["${DB}"], "percentage_trainval": 100}
]
for k in ("batch_size_train", "batch_size_val", "batch_size_test"):
    c["config"][k] = ${BS}
# paths may need to stay absolute under EASL_ROOT
p.write_text(json.dumps(c, indent=2))
print("patched", "${DB}", ${BS})
PY
  export PYTHONPATH="$WD:$UP:${PYTHONPATH:-}"
  set +e
  "$PY" _run_one.py >"$LOGF" 2>&1
  ec=$?
  set -e
  log "EXIT $DB ec=$ec"
  return $ec
}

run_db() {
  local DB="$1"
  if has_metrics "$DB"; then
    log "SKIP $DB"
    return 0
  fi
  patch_and_run "$DB" || return 1
  has_metrics "$DB"
}

log "34 resume eicu+hirid paper batch=$BS GPU=$CUDA_VISIBLE_DEVICES PY=$PY"
nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader || true
# mark start for finish-watcher fatal window
date -Iseconds > "$LOGDIR/DATASET_BENCH_34_STARTED.time"
run_db eicu || { log "FATAL eicu"; exit 1; }
sleep 5
run_db hirid || { log "FATAL hirid"; exit 1; }
find "$WD/results" -name metrics_multitask.csv | sort
# Done only when both eicu+hirid metrics exist
if has_metrics eicu && has_metrics hirid; then
  date -Iseconds > "$LOGDIR/DATASET_BENCH_34_DONE.time"
  log "ALL_DONE_34 wrote DATASET_BENCH_34_DONE.time"
  exit 0
fi
log "FATAL missing metrics after train (no DONE marker)"
exit 1
