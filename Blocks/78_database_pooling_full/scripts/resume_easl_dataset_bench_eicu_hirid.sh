#!/bin/bash
# Resume liver_dataset_benchmark for eICU + HiRID only (Amsterdam/MIMIC already done).
# Paper params: batch_size=32, full epochs. Fresh process per DB (no batch reduction).
# Run on 29 only.
set -u
PY=/home/ps/anaconda3/envs/torch/bin/python
WD=/mnt/sda/BlendedICU/data/liver_dysfunction_easl_dili_42151996/Output_paper_extras/liver_dataset_benchmark
UP=/mnt/sda/liver_sofa2_train/Blocks/78_database_pooling_full/upstream/BlendedLoS
SCRIPT_DIR=/mnt/sda/liver_sofa2_train/Blocks/78_database_pooling_full/scripts
CI=$SCRIPT_DIR/eval_liver_paper_ci.py
FINAL=$SCRIPT_DIR/finalize_easl_paper_pub.py
EASL_ROOT=/mnt/sda/BlendedICU/data/liver_dysfunction_easl_dili_42151996
OUT=$EASL_ROOT/Output_paper_extras
LOGDIR=/mnt/sda/liver_easl_paper_extras/logs
PUB_LOCAL=$EASL_ROOT/summary_results
mkdir -p "$LOGDIR" "$PUB_LOCAL"

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

patch_and_run() {
  local DB="$1"
  local LOGF="$LOGDIR/dataset_bench_${DB}_bs${BS}_$(date +%Y%m%d_%H%M%S).log"
  log "START $DB batch=$BS (paper) log=$LOGF"
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
p.write_text(json.dumps(c, indent=2))
print("patched runs=[${DB}] batch=${BS}")
PY
  export PYTHONPATH="$WD:$UP:${PYTHONPATH:-}"
  set +e
  "$PY" _run_one.py >"$LOGF" 2>&1
  ec=$?
  set -e
  log "EXIT $DB batch=$BS ec=$ec"
  return $ec
}

run_db() {
  local DB="$1"
  if has_metrics "$DB"; then
    log "SKIP $DB (metrics already present)"
    return 0
  fi
  patch_and_run "$DB" || { log "FATAL $DB failed at paper batch=$BS"; return 1; }
  has_metrics "$DB" || { log "FATAL $DB no metrics after train"; return 1; }
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
fi

log "resume eicu+hirid paper batch=$BS CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES (seq capped at max_los*24h, batch unchanged)"
run_db eicu || exit 1
sleep 5
run_db hirid || exit 1

log "CI dataset_benchmark"
"$PY" "$CI" --root "$OUT" --units liver_dataset_benchmark --n-boot 10000 \
  --out "$OUT/ci_liver_dataset_benchmark" || true

log "finalize publication"
export EASL_ROOT
export LIVER_PUB_OUT="$PUB_LOCAL"
"$PY" "$FINAL" | tee "$LOGDIR/finalize_dataset_resume_$(date +%Y%m%d_%H%M%S).log"

echo "$PUB_LOCAL" > "$LOGDIR/PUBLISH_READY.path"
date -Iseconds > "$LOGDIR/PUBLISH_READY.time"
log "ALL_DONE PUBLISH_READY written"
find "$WD/results" -name metrics_multitask.csv | sort
exit 0
