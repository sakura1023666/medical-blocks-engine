#!/bin/bash
# 3-GPU queue: 5 liver rules WITH MOESM1 physio clip, then full ICU (same pipeline).
# Host: start on 29. Uses GPU0+GPU1 locally; SSH to 34 for GPU2.
# Unix LF only.
set -u
SCRIPT_DIR=/mnt/sda/liver_sofa2_train/Blocks/78_database_pooling_full/scripts
ONE=$SCRIPT_DIR/run_one_cohort_physclip.sh
PREP=$SCRIPT_DIR/prepare_full_icu_blendedlos.py
EXTEND=$SCRIPT_DIR/extend_easl_splits_all4.py
PY=/home/ps/anaconda3/envs/torch/bin/python
LOGDIR=/mnt/sda/liver_easl_paper_extras/logs_physclip_queue
PLAN=$LOGDIR/PLAN_2days.md
mkdir -p "$LOGDIR"
chmod +x "$ONE" 2>/dev/null || true

# 34 credentials via env (set by launcher) or defaults empty → skip remote
LAB34_HOST="${LAB_34_HOST:-192.168.68.34}"
LAB34_USER="${LAB_34_USER:-ps}"
LAB34_PASS="${LAB_34_PASSWORD:-}"

log() { echo "$(date -Iseconds) $*"; }

cat > "$PLAN" <<'MD'
# Physclip 三卡排队计划（有 clip）

更正：旧结果 = 无 clip；本轮五条规则 + 全体 ICU = **有 clip**（`DBPOOL_PHYSIO_CLIP=1`）。

## 队列顺序

| 顺序 | 规则 | 约 stays | DROP（纳入泄漏） | 卡 |
|------|------|----------|------------------|-----|
| 1 | ACG+胆红素 | ~16k | bili+ALT+AST | 29 GPU0 |
| 2 | MARS (48h≥33) | ~21k | bilirubine | 29 GPU1 |
| 3 | SOFA≥2 | ~19k | bilirubine | 34 GPU0 |
| 4 | SOFA≥1 | ~36k | bilirubine | 先空出的卡 |
| 5 | ACG 纯酶学 | ~41k | ALT+AST | 先空出的卡 |
| 6 | 全体 ICU | ~350k | 无 | 三卡接力，约 3–7 天 |

每条规则包：主四臂 A→B→C→D + equaln + dataset + model + size + CI → `Output_physclip/` + `Output_paper_extras_physclip/`。

## 两天节奏（墙钟粗估）

- **今天**：并行开跑 1–3；傍晚–夜间接 4–5。小队列（acg_bili/mars/sofa2）主臂多半今天内完。
- **明天**：收完 sofa1/acg 的 extras；同时 `prepare_full_icu`；三卡切入全体 ICU 主臂。
- **之后 3–7 天**：全体 ICU size/dataset（大头）。

## 产出

- 各规则：`…/liver_dysfunction_<rule>_42151996/Output_physclip/`
- 全体：`…/blendedlos_full_icu_42151996/Output_physclip/`
- 日志：`/mnt/sda/liver_easl_paper_extras/logs_physclip_queue/`
MD

log "PLAN written $PLAN"
cat "$PLAN"

# --- prepare full ICU tree early (CPU) while GPUs train ---
(
  log "prepare_full_icu START"
  "$PY" "$PREP" --out /mnt/sda/BlendedICU/data/blendedlos_full_icu_42151996/blendedlos_full \
    > "$LOGDIR/prepare_full_icu_$(date +%Y%m%d_%H%M%S).log" 2>&1
  "$PY" "$EXTEND" --blended-out /mnt/sda/BlendedICU/data/blendedlos_full_icu_42151996/blendedlos_full \
    >> "$LOGDIR/prepare_full_icu_extend.log" 2>&1 || true
  log "prepare_full_icu DONE"
) &
PREP_PID=$!

run_local() {
  local cohort="$1" gpu="$2"
  nohup bash "$ONE" "$cohort" "$gpu" > "$LOGDIR/${cohort}_gpu${gpu}_$(date +%Y%m%d_%H%M%S).log" 2>&1 &
  echo $!
}

run_34() {
  local cohort="$1"
  if [ -z "$LAB34_PASS" ]; then
    log "WARN no LAB_34_PASSWORD; run $cohort on 29 GPU0 after current jobs"
    run_local "$cohort" 0
    return
  fi
  # ensure scripts on 34
  sshpass -p "$LAB34_PASS" ssh -o StrictHostKeyChecking=no "${LAB34_USER}@${LAB34_HOST}" \
    "mkdir -p $SCRIPT_DIR $LOGDIR; test -x $ONE" || true
  sshpass -p "$LAB34_PASS" ssh -o StrictHostKeyChecking=no "${LAB34_USER}@${LAB34_HOST}" \
    "nohup bash $ONE $cohort 0 > $LOGDIR/${cohort}_gpu0_34_\$(date +%Y%m%d_%H%M%S).log 2>&1 & echo \$!"
}

# Wave 1: three cohorts
PID0=$(run_local acg_bili 0)
PID1=$(run_local mars 1)
PID2=$(run_34 sofa2)
log "WAVE1 pids local=$PID0,$PID1 remote=$PID2 prep=$PREP_PID"

# Wait for first local finish, then sofa1 / acg
wait_any_local() {
  while kill -0 "$PID0" 2>/dev/null && kill -0 "$PID1" 2>/dev/null; do
    sleep 120
  done
  if ! kill -0 "$PID0" 2>/dev/null; then echo 0; elif ! kill -0 "$PID1" 2>/dev/null; then echo 1; else echo 0; fi
}

FREE=$(wait_any_local)
log "WAVE2 start sofa1 on gpu=$FREE"
PID_S1=$(run_local sofa1 "$FREE")

# wait for the other local
while kill -0 "$PID0" 2>/dev/null || kill -0 "$PID1" 2>/dev/null; do sleep 120; done
# pick free gpu for acg
if ! kill -0 "$PID_S1" 2>/dev/null; then
  FREE2=0
else
  # sofa1 still running — use the other gpu
  FREE2=$( [ "$FREE" = "0" ] && echo 1 || echo 0 )
fi
log "WAVE2b start acg on gpu=$FREE2"
PID_ACG=$(run_local acg "$FREE2")

wait "$PID_S1" 2>/dev/null || true
wait "$PID_ACG" 2>/dev/null || true
wait "$PREP_PID" 2>/dev/null || true

# wait 34 sofa2 if we can poll
if [ -n "$LAB34_PASS" ]; then
  while sshpass -p "$LAB34_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=20 \
    "${LAB34_USER}@${LAB34_HOST}" "test ! -f $LOGDIR/sofa2_DONE.time" 2>/dev/null; do
    log "waiting sofa2 on 34..."
    sleep 300
  done
fi

log "WAVE3 full_icu on 3 GPUs (main arms split)"
# Split full ICU: A on 29:0, B on 29:1, D on 34; then C on first free; extras after
export DBPOOL_PHYSIO_CLIP=1
export DBPOOL_FULL_EPOCHS=1
unset DBPOOL_DROP_TS
DATA_FULL=/mnt/sda/BlendedICU/data/blendedlos_full_icu_42151996/blendedlos_full
MAIN_FULL=/mnt/sda/BlendedICU/data/blendedlos_full_icu_42151996/Output_physclip
OUT_FULL=/mnt/sda/BlendedICU/data/blendedlos_full_icu_42151996/Output_paper_extras_physclip
mkdir -p "$MAIN_FULL" "$OUT_FULL"
echo "DBPOOL_PHYSIO_CLIP=1 DROP=" > "$MAIN_FULL/PHYSIO_CLIP.txt"

(
  export CUDA_VISIBLE_DEVICES=0 DBPOOL_PHYSIO_CLIP=1 DBPOOL_FULL_EPOCHS=1
  unset DBPOOL_DROP_TS
  "$PY" "$SCRIPT_DIR/run_dbpool_experiment.py" --unit liver_expA_amsterdam_solo \
    --blended-out "$DATA_FULL" --work-dir "$MAIN_FULL/liver_expA_amsterdam_solo"
) > "$LOGDIR/full_icu_A.log" 2>&1 &
FA=$!
(
  export CUDA_VISIBLE_DEVICES=1 DBPOOL_PHYSIO_CLIP=1 DBPOOL_FULL_EPOCHS=1
  unset DBPOOL_DROP_TS
  "$PY" "$SCRIPT_DIR/run_dbpool_experiment.py" --unit liver_expB_mimic_solo \
    --blended-out "$DATA_FULL" --work-dir "$MAIN_FULL/liver_expB_mimic_solo"
) > "$LOGDIR/full_icu_B.log" 2>&1 &
FB=$!

if [ -n "$LAB34_PASS" ]; then
  sshpass -p "$LAB34_PASS" ssh -o StrictHostKeyChecking=no "${LAB34_USER}@${LAB34_HOST}" bash -s <<EOF
export CUDA_VISIBLE_DEVICES=0 DBPOOL_PHYSIO_CLIP=1 DBPOOL_FULL_EPOCHS=1
unset DBPOOL_DROP_TS DBPOOL_FAST_TRAIN
nohup $PY $SCRIPT_DIR/run_dbpool_experiment.py --unit liver_expD_pooled_mimic_amsterdam \
  --blended-out $DATA_FULL --work-dir $MAIN_FULL/liver_expD_pooled_mimic_amsterdam \
  > $LOGDIR/full_icu_D_34.log 2>&1 &
echo \$!
EOF
fi

wait $FA $FB || true
# Transfer after B (needs mimic pretrained from B's run — C trains its own mimic then retrain)
(
  export CUDA_VISIBLE_DEVICES=0 DBPOOL_PHYSIO_CLIP=1 DBPOOL_FULL_EPOCHS=1
  unset DBPOOL_DROP_TS
  "$PY" "$SCRIPT_DIR/run_dbpool_experiment.py" --unit liver_expC_mimic2amsterdam_transfer \
    --blended-out "$DATA_FULL" --work-dir "$MAIN_FULL/liver_expC_mimic2amsterdam_transfer"
) > "$LOGDIR/full_icu_C.log" 2>&1

# extras on 29 both GPUs after C
MIN_TRAIN=$("$PY" - <<PY
import json
from pathlib import Path
s=json.loads(Path("$DATA_FULL/split_summary_all4.json").read_text())
print(min(s[d]["persons"]["train"] for d in ("amsterdam","mimic4","eicu","hirid")))
PY
)
(
  export CUDA_VISIBLE_DEVICES=0 DBPOOL_PHYSIO_CLIP=1 DBPOOL_FULL_EPOCHS=1 DBPOOL_TRAIN_STAYS_PER_DB=$MIN_TRAIN
  unset DBPOOL_DROP_TS
  "$PY" "$SCRIPT_DIR/run_dbpool_experiment.py" --unit liver_model_benchmark_equaln \
    --blended-out "$DATA_FULL" --work-dir "$OUT_FULL/liver_model_benchmark_equaln"
) > "$LOGDIR/full_icu_equaln.log" 2>&1 &
(
  export CUDA_VISIBLE_DEVICES=1 DBPOOL_PHYSIO_CLIP=1 DBPOOL_FULL_EPOCHS=1
  unset DBPOOL_DROP_TS DBPOOL_TRAIN_STAYS_PER_DB
  "$PY" "$SCRIPT_DIR/run_dbpool_experiment.py" --unit liver_dataset_benchmark \
    --blended-out "$DATA_FULL" --work-dir "$OUT_FULL/liver_dataset_benchmark"
  "$PY" "$SCRIPT_DIR/run_dbpool_experiment.py" --unit liver_model_benchmark \
    --blended-out "$DATA_FULL" --work-dir "$OUT_FULL/liver_model_benchmark"
  "$PY" "$SCRIPT_DIR/run_dbpool_experiment.py" --unit liver_training_size_study \
    --blended-out "$DATA_FULL" --work-dir "$OUT_FULL/liver_training_size_study"
) > "$LOGDIR/full_icu_extras_gpu1.log" 2>&1 &
wait || true

date -Iseconds > "$LOGDIR/QUEUE_ALL_DONE.time"
log "QUEUE_ALL_DONE"
exit 0
