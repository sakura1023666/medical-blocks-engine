#!/usr/bin/env bash
# Collect hearing UHR triple-db into summary_result
# 三库：NHANES + CHARLS + Single（原李玲单库）
# 编号：S1–S4 screen | S5 lab assoc | S6 mediation | S7/S8 NHANES sens | S-XX RCS
set -euo pipefail
STUDY="${1:-/mnt/g/02block_result/15_hearing_loss/incidence_38341157}"
OUT="$STUDY/summary_result"

# 指标根：优先正式 success，其次副本
DUAL=""
for cand in "$STUDY/by_index/【success】UHR" "$STUDY/by_index/【success】UHR - 副本"; do
  if [[ -d "$cand" ]]; then DUAL="$cand"; break; fi
done
[[ -n "$DUAL" ]] || { echo "ERROR: no UHR success dir under $STUDY/by_index" >&2; exit 1; }

# Single 库路径（兼容旧 Liling 目录名）
SINGLE=""
for cand in "$DUAL/Single" "$DUAL/Liling" "$STUDY/by_index/UHR/Single" "$STUDY/by_index/UHR/Liling"; do
  if [[ -d "$cand" ]]; then SINGLE="$cand"; break; fi
done

rm -rf "$OUT"
mkdir -p "$OUT/figure" "$OUT/table"

copy_tables() {
  local src="$1"
  [[ -d "$src" ]] || return 0
  find "$src" -maxdepth 1 -type f -name '*.xlsx' -size +0 \
    ! -name '*Multivariable*' \
    ! -name '*VIF, multivariate*' \
    -exec cp -a {} "$OUT/table/" \;
}

# 指标根汇总 + 三库分库 Tables（去重：同名以分库为准后写入）
copy_tables "$DUAL/Tables"
copy_tables "$DUAL/NHANES/Tables"
copy_tables "$DUAL/CHARLS/Tables"
copy_tables "$SINGLE/Tables"

copy_fig_dir() {
  local src="$1" tag="$2"
  [[ -d "$src" ]] || return 0
  local f base dest
  shopt -s nullglob
  for f in "$src"/*.pdf "$src"/*.png "$src"/pdf/*.pdf "$src"/png/*.png; do
    [[ -f "$f" ]] || continue
    base=$(basename "$f")
    # 旧 Liling 前缀 → Single
    base="${base//-Liling./-Single.}"
    base="${base//Figure 2-Liling/Figure 2-Single}"
    base="${base//Figure 3-Liling/Figure 3-Single}"
    base="${base//Figure S1-Liling/Figure S1-Single}"
    base="${base//Figure S2-Liling/Figure S2-Single}"
    base="${base//Figure S3-Liling/Figure S3-Single}"
    if [[ "$base" == "Figure Missing Value Overview.pdf" || "$base" == "Figure Missing Value Overview.png" ]]; then
      dest="Figure Missing Value Overview-${tag}.${base##*.}"
      cp -a "$f" "$OUT/figure/$dest"
      if [[ "$tag" == "NHANES" ]]; then
        cp -a "$f" "$OUT/figure/Figure Missing Value Overview.${base##*.}"
      fi
    else
      cp -a "$f" "$OUT/figure/$base"
    fi
  done
  shopt -u nullglob
}

copy_fig_dir "$DUAL/Figures" "ALL"
copy_fig_dir "$DUAL/NHANES/Figures" "NHANES"
copy_fig_dir "$DUAL/CHARLS/Figures" "CHARLS"
copy_fig_dir "$SINGLE/Figures" "Single"

# 三库汇总森林图（若存在）
for extra in "$STUDY/by_index/UHR_triple_summary/Figure_triple_UHR_quartile_Model2_forest.pdf" \
             "$STUDY/by_index/UHR_triple_summary/Figure_triple_UHR_quartile_Model2_forest.png"; do
  [[ -f "$extra" ]] && cp -a "$extra" "$OUT/figure/$(basename "$extra")"
done

{
  echo "summary_result — hearing_loss UHR (triple: NHANES + CHARLS + Single)"
  echo "source_index: $DUAL"
  echo "single_db: ${SINGLE:-MISSING}"
  echo "generated: $(date -Iseconds)"
  echo "tables: S1–S4 screen | S5 lab assoc | S6 mediation | S7/S8 NHANES sens | S-XX RCS"
  echo "figures: Fig1 flowchart | Fig2 RCS (×3) | Fig3 subgroup (×3) | Missing | Fig S1 ROC | Fig S2 box | Fig S3 mediation"
  echo
  echo "=== figure ==="; ls -1 "$OUT/figure" 2>/dev/null | sort
  echo; echo "=== table ==="; ls -1 "$OUT/table" 2>/dev/null | sort
  echo
  echo "=== triple Table2 check ==="
  for db in NHANES CHARLS Single; do
    ls -1 "$OUT/table"/Table\ 2-*"${db}"*.xlsx 2>/dev/null || echo "MISSING Table2-$db"
  done
} > "$OUT/MANIFEST.txt"

echo "Done: $OUT (from $DUAL)"
echo "figure: $(ls -1 "$OUT/figure" 2>/dev/null | wc -l)  table: $(ls -1 "$OUT/table" 2>/dev/null | wc -l)"
