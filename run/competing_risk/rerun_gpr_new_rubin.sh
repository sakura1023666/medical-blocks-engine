#!/usr/bin/env bash
set -euo pipefail
BASE="/mnt/g/02block_result/11_ischemic stroke/Competing_risk_model_40119388/by_unit"
if [ -d "$BASE/【success】GPR[new]" ]; then
  rm -rf "$BASE/GPR[new]"
  mv "$BASE/【success】GPR[new]" "$BASE/GPR[new]"
fi

Rscript /mnt/e/01block/01Block-new-Final/run/competing_risk/patch_gpr_new_mice_ids.R

CFG="/mnt/g/02block_result/11_ischemic stroke/Competing_risk_model_40119388/config_competing_risk_stroke_batch.R"
ROOT="/mnt/e/01block/01Block-new-Final"
cd "$ROOT"
export SMOKE_NO_FEISHU=1 BLOCK_REPO_ROOT="$ROOT" BLOCK_RESULT_ROOT="/mnt/g/02block_result"
rm -f "$BASE/GPR[new]/_batch_status.json"
LOG="/mnt/g/02block_result/11_ischemic stroke/Competing_risk_model_40119388/logs/GPR_new_rubin_fix_$(date +%Y%m%d_%H%M%S).log"
nohup Rscript run/competing_risk/run_competing_risk_chf_batch.R \
  --config "$CFG" --only-unit 'GPR[new]' --workers 1 --units-only --no-skip \
  > "$LOG" 2>&1 &
echo "PID=$!"
echo "LOG=$LOG"
