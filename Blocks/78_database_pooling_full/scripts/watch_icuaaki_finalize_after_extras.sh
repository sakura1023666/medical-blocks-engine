#!/usr/bin/env bash
# Wait for paper extras DONE, then cirrhosis-aligned finalize + sync hint.
set -euo pipefail
ROOT=/mnt/sda/BlendedICU/data/icuaaki_4db_20261106
PY=/home/ps/miniconda3/envs/blendedlos/bin/python
LOG=$ROOT/logs/watch_finalize.log
exec > >(tee -a "$LOG") 2>&1

echo "$(date -Iseconds) watch begin"
while [[ ! -f $ROOT/logs/paper_extras/DONE.time ]]; do
  sleep 120
  echo "$(date -Iseconds) waiting extras… gpu=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | head -1)%"
done
echo "$(date -Iseconds) extras DONE; running cirrhosis-aligned finalize"

export ICUAKI_ROOT=$ROOT
export ICUAKI_PUB_OUT=$ROOT/summary_results
export ICUAKI_EXTRA_OUT=$ROOT/Output_paper_extras
export ICUAKI_MAIN_OUT=$ROOT/Output_database_pooling
export ICUAKI_N_BOOT=2000
export LIVER_ROOT=$ROOT
export LIVER_BLENDED_SUBDIR=blendedlos_icuaaki
export EASL_MAIN_OUT=$ROOT/Output_database_pooling
export EASL_EXTRA_OUT=$ROOT/Output_paper_extras
export LIVER_PUB_OUT=$ROOT/summary_results
export LIVER_COHORT_TITLE="ICU-AKI (KDIGO DN=1)"
export LIVER_COHORT_RULE_SHORT="KDIGO ICU-AKI DN=1; drop Cr/UO from features"
export LIVER_TABLE1_FOOTNOTE="KDIGO ICU-AKI cohort (DN=1). Continuous: mean [SD] (vitals/labs = stay-level hourly mean after physiological-range clip). Drug exposure: any hourly dose >0. Creatinine and urine_output excluded from model features."
export LIVER_FEATURE_DROP_EN="Creatinine and urine_output excluded from model features."
export LIVER_SKIP_TABLE1=1
export LIVER_SKIP_DELIVERY=1

# Base pack (cirrhosis layout) — Table1 already rebuilt separately if cache exists
"$PY" "$ROOT/scripts/finalize_easl_paper_pub.py"

# Clinical extras S3–S5 / Fig3–5 on top (do not clobber cirrhosis base)
"$PY" "$ROOT/scripts/finalize_icuaaki_paper_pub.py" --extras-only

# Prefer full Table1 if rebuilt
if [[ -f $ROOT/summary_results/Tables/Table\ 1.\ Cohort\ characteristics.xlsx ]]; then
  echo "Table1 present"
fi

date -Iseconds > "$ROOT/logs/FINALIZE_ALIGNED.time"
echo "$(date -Iseconds) ALIGNED_FINALIZE_DONE"
