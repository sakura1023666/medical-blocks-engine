#!/usr/bin/env bash
# After units retrain DONE on 29 → finalize into summary_results_units
# (never touches legacy summary_results / Output_database_pooling).
set -euo pipefail

ROOT=/mnt/sda/BlendedICU/data/icuaaki_4db_20261106
DONE=$ROOT/logs/units_retrain/DONE.time
LOG=$ROOT/logs/units_retrain/watch_finalize.log
PY="${PY:-/home/ps/anaconda3/envs/torch/bin/python}"
BLOCK78=/mnt/sda/liver_sofa2_train/Blocks/78_database_pooling_full/scripts
# Prefer ROOT/scripts copies if present (may have disease-specific finalize helpers)
SCRIPTS=$ROOT/scripts
mkdir -p "$SCRIPTS" "$ROOT/logs/units_retrain"

exec > >(tee -a "$LOG") 2>&1
echo "$(date -Iseconds) units finalize watch begin"

while [[ ! -f $DONE ]]; do
  sleep 180
  echo "$(date -Iseconds) waiting units retrain DONE…"
  nvidia-smi --query-gpu=index,memory.used,utilization.gpu --format=csv,noheader || true
done
echo "$(date -Iseconds) units retrain DONE → finalize summary_results_units"

export ICUAKI_ROOT=$ROOT
export ICUAKI_MAIN_OUT=$ROOT/Output_database_pooling_units
export ICUAKI_EXTRA_OUT=$ROOT/Output_paper_extras_units
export ICUAKI_PUB_OUT=$ROOT/summary_results_units
export ICUAKI_N_BOOT="${ICUAKI_N_BOOT:-2000}"
export LIVER_ROOT=$ROOT
export LIVER_BLENDED_SUBDIR=blendedlos_icuaaki_units
export EASL_MAIN_OUT=$ICUAKI_MAIN_OUT
export EASL_EXTRA_OUT=$ICUAKI_EXTRA_OUT
export LIVER_PUB_OUT=$ICUAKI_PUB_OUT
export LIVER_COHORT_TITLE="ICU-AKI (KDIGO DN=1; units harmonized)"
export LIVER_COHORT_RULE_SHORT="KDIGO ICU-AKI DN=1; drop Cr/UO; glucose mmol/L + Hb g/dL"
export LIVER_TABLE1_FOOTNOTE="KDIGO ICU-AKI cohort (DN=1). Units harmonized (blood_glucose mmol/L; hemoglobin g/dL) before MOESM1 physio clip. Continuous: mean [SD]. Creatinine and urine_output excluded from model features."
export LIVER_FEATURE_DROP_EN="Creatinine and urine_output excluded from model features."
export LIVER_SKIP_TABLE1=1
export LIVER_SKIP_DELIVERY=1

mkdir -p "$ICUAKI_PUB_OUT"

EASL_FIN=""
for c in "$SCRIPTS/finalize_easl_paper_pub.py" "$BLOCK78/finalize_easl_paper_pub.py"; do
  [[ -f $c ]] && EASL_FIN=$c && break
done
ICU_FIN=""
for c in "$SCRIPTS/finalize_icuaaki_paper_pub.py" "$BLOCK78/finalize_icuaaki_paper_pub.py"; do
  [[ -f $c ]] && ICU_FIN=$c && break
done

if [[ -n $EASL_FIN ]]; then
  echo "running $EASL_FIN"
  "$PY" "$EASL_FIN" || echo "WARN easi finalize ec=$?"
else
  echo "WARN missing finalize_easl_paper_pub.py — skip base pack"
fi

if [[ -n $ICU_FIN ]]; then
  echo "running $ICU_FIN --extras-only"
  "$PY" "$ICU_FIN" --extras-only || "$PY" "$ICU_FIN" || echo "WARN icuaaki finalize ec=$?"
else
  echo "WARN missing finalize_icuaaki_paper_pub.py"
fi

# Gate units once more on the train tree used for this pack
"$PY" "$BLOCK78/harmonize_blendedlos_units.py" --root "$ROOT/blendedlos_icuaaki_units" --assert-only \
  || echo "WARN units assert after finalize"

date -Iseconds > "$ROOT/logs/units_retrain/FINALIZE_UNITS.time"
echo "$(date -Iseconds) UNITS_FINALIZE_DONE pub=$ICUAKI_PUB_OUT"
echo "SYNC_HINT: rsync -a $ICUAKI_PUB_OUT/ <G>/database_pooled_icuaaki_4db_20261106/summary_results_units/"
echo "LEGACY_KEPT: $ROOT has Output_database_pooling + G summary_results untouched"
