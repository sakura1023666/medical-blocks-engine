#!/usr/bin/env bash
# Full stroke ANLR pipeline for landmark days (from raw outcome build → tables/figures)
set -euo pipefail
ENGINE="${ENGINE:-/mnt/e/01block/01Block-new-Final}"
cd "$ENGINE"
DAYS_LIST="${*:-7 14 28 90 365}"
for DAYS in $DAYS_LIST; do
  if [ "$DAYS" = "28" ]; then
    OUT="summary_results"
  else
    OUT="summary_results_${DAYS}d"
  fi
  export STROKE_ANLR_DAYS="$DAYS"
  export STROKE_ANLR_OUT="$OUT"
  LOG="/mnt/g/02block_result/11_ischemic stroke/prognosis_v2_41904528/run_landmark_${DAYS}d.log"
  echo "======== START ${DAYS}d -> ${OUT} ========" | tee "$LOG"
  Rscript run/prognosis_v2/run_prognosis_v2_stroke_anlr.R --days "$DAYS" --out "$OUT" 2>&1 | tee -a "$LOG"
  Rscript run/prognosis_v2/remirror_stroke_anlr_pub.R 2>&1 | tee -a "$LOG"
  Rscript run/prognosis_v2/_fix_stroke_anlr_mediation_corr_first.R 2>&1 | tee -a "$LOG"
  Rscript run/prognosis_v2/_fix_stroke_anlr_fig2_full_shared.R 2>&1 | tee -a "$LOG"
  Rscript run/prognosis_v2/_fix_stroke_anlr_fig7_lit_forest.R 2>&1 | tee -a "$LOG"
  echo "======== DONE ${DAYS}d ========" | tee -a "$LOG"
  ls -la "/mnt/g/02block_result/11_ischemic stroke/prognosis_v2_41904528/${OUT}/Figures/pdf/" | tee -a "$LOG"
  ls "/mnt/g/02block_result/11_ischemic stroke/prognosis_v2_41904528/${OUT}/Tables/"*.xlsx 2>/dev/null | wc -l | tee -a "$LOG"
done
