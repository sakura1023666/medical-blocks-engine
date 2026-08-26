#!/usr/bin/env bash
# 从 summary_result/table 剔除二分位/四分位/五分位 GLM（主文仅保留三分位 Table 2）
# 不删 Table S-XX（RCS cutoff groups）。用法：
#   bash Blocks/54_cross_lagged_full/phases/prune_summary_nonsummary_logistic.sh [study_root]
#   或: Rscript run/cross_lagged/run_cross_lagged_frailty.R --phase prune --study-root ...
set -euo pipefail
STUDY="${1:-/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747}"
TAB="$STUDY/summary_result/table"
[[ -d "$TAB" ]] || { echo "missing $TAB"; exit 1; }
chmod -R u+w "$STUDY/summary_result" 2>/dev/null || true
n=0
while IFS= read -r -d '' f; do
  case "$(basename "$f")" in
    Table\ S-XX-*) continue ;;
    *RCS\ cutoff*) continue ;;
  esac
  rm -fv -- "$f"
  n=$((n + 1))
done < <(find "$TAB" -maxdepth 1 -type f \( \
  -name '*binary (GLM).xlsx' -o \
  -name '*quartile (GLM).xlsx' -o \
  -name '*quintile (GLM).xlsx' \
\) ! -name '*RCS*' -print0)
echo "pruned $n file(s) from $TAB"
echo "re-run: bash Blocks/54_cross_lagged_full/phases/reorder_summary_result.sh \"$STUDY\""
