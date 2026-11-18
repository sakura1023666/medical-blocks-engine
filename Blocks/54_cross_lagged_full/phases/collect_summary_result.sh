#!/usr/bin/env bash
# Dispatcher: every cross-lagged study_root → summary_result/{figure,table}
# - Default: generic collect (discovers phase1_*/phase3_* ; copies Tables + Figures)
# - Hip allages+HRS layout: keep original naming/lock copy
# - Optional override: $STUDY/collect_summary_result.local.sh
set -euo pipefail
STUDY="${1:-${CROSS_LAGGED_STUDY_ROOT:-/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747}}"
HERE="$(cd "$(dirname "$0")" && pwd)"

if [[ -f "$STUDY/collect_summary_result.local.sh" ]]; then
  bash "$STUDY/collect_summary_result.local.sh" "$STUDY"
  ENG_ROOT="${MEDICAL_BLOCKS_ROOT:-}"
  if [[ -z "$ENG_ROOT" ]]; then
    ENG_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
  fi
  Rscript "$ENG_ROOT/Blocks/54_cross_lagged_full/phases/export_summary_figures.R" "$STUDY"
  exit 0
fi

_is_hip=0
_is_dep_htn=0
if [[ -f "$STUDY/README_DEPRESSION_HTN_FRAILTY.txt" ]] ||
   [[ -f "$STUDY/data/harmonized/D04_CHARLS_depression_htn_baseline.RData" ]]; then
  _is_dep_htn=1
fi
# 抑郁×高血压绝不能走髋部专用收集（summary 残留 *Hip* 文件名也会误触发）
if [[ "$_is_dep_htn" != "1" ]] &&
   [[ -d "$STUDY/phase1_CHARLS_allages" ]] &&
   { [[ -d "$STUDY/phase1_HRS_allages" ]] || [[ -d "$STUDY/phase1_HRS" ]]; } &&
   { [[ ! -f "$STUDY/config_long_panel.R" ]] || ! grep -qE '^[[:space:]]*\.circadian_index_var[[:space:]]*<-' "$STUDY/config_long_panel.R" 2>/dev/null; }
then
  # 表名仍是髋部时才走旧脚本（新课题即使目录叫 allages 也用 generic）
  if ls "$STUDY"/phase1_CHARLS_allages/Tables/*Hip* >/dev/null 2>&1 ||
     ls "$STUDY"/summary_result/table/*Hip* >/dev/null 2>&1
  then
    _is_hip=1
  fi
fi

if [[ "$_is_hip" == "1" ]]; then
  bash "$HERE/collect_summary_result_hip.sh" "$STUDY"
else
  bash "$HERE/collect_summary_result_generic.sh" "$STUDY"
fi
