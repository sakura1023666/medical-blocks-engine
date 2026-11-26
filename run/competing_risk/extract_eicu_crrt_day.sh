#!/usr/bin/env bash
# Thin wrapper → 课题 scripts
set -euo pipefail
PROJ=/mnt/g/02block_result/33_AKI/Competing_risk_CRRT_28d
python3 "$PROJ/scripts/extract_eicu_crrt_day.py" "$@"
Rscript "$PROJ/scripts/merge_eicu_crrt_day_into_baseline.R"
