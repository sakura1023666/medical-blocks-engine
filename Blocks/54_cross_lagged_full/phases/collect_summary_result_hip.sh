#!/usr/bin/env bash
# Collect cross-lagged hip×frailty into summary_result/
# Structure mirrors hearing_loss incidence_38341157/summary_result
#
# 汇总策略：主文 logistic = 三分位（Table 2）only；
#   binary / quartile / quintile GLM 不拷入 summary（闸门链仍在 phase* 产出敏感性）。
set -euo pipefail
STUDY="${1:-/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747}"
OUT="$STUDY/summary_result"


rm -rf "$OUT" 2>/dev/null || true
mkdir -p "$OUT/figure" "$OUT/table"
# Windows/UNC 偶发只读残留时，尽量清掉再写
chmod -R u+w "$OUT" 2>/dev/null || true


# phase1 表常无库名后缀；汇总 / reorder 需要「Table *-DB. 标题」
_name_with_db() {
  local base="$1" db="$2"
  # 已带 -CHARLS./-ELSA./-HRS./-Pooled. 则原样
  if [[ "$base" =~ Table[[:space:]][A-Za-z0-9.XX-]+-(CHARLS|ELSA|HRS|Pooled)\. ]]; then
    printf '%s' "$base"
    return 0
  fi
  # Table 1. xxx → Table 1-DB. xxx
  if [[ "$base" =~ ^(Table[[:space:]][^./]+)\.[[:space:]](.+)$ ]]; then
    printf '%s-%s. %s' "${BASH_REMATCH[1]}" "$db" "${BASH_REMATCH[2]}"
    return 0
  fi
  printf '%s' "$base"
}

copy_xlsx() {
  local src="$1"
  local db_tag="${2:-}"
  [[ -f "$src" ]] || return 0
  local base dest
  base=$(basename "$src")
  # 排除中间多因素 / final VIF；主文 logistic 仅三分位进汇总（见 _copy_locked_logistic）
  case "$base" in
    *Multivariable*) return 0 ;;
    *'VIF, multivariate'*) return 0 ;;
    # 二分/四分/五分位 GLM 主表不进 summary（闸门链仍可在 phase1 产出，仅不汇总）
    *' - binary (GLM).xlsx') return 0 ;;
    *' - quartile (GLM).xlsx') return 0 ;;
    *' - quintile (GLM).xlsx') return 0 ;;
    # 非 Table2 的三分位副本也不从根 Tables 散落拷入（统一走 locked tertile→Table 2）
    *' - tertile (GLM).xlsx') return 0 ;;
  esac
  if [[ -n "$db_tag" ]]; then
    dest="$(_name_with_db "$base" "$db_tag")"
  else
    dest="$base"
  fi
  cp -a "$src" "$OUT/table/$dest"
}

# 三单库 + Pooled 后段表
for db in CHARLS ELSA HRS; do
  tab="$STUDY/phase1_${db}_allages/Tables"
  if [[ -d "$tab" ]]; then
    find "$tab" -maxdepth 1 -type f -name '*.xlsx' -print0 | while IFS= read -r -d '' f; do
      copy_xlsx "$f" "$db"
    done
  fi
done

pooled_tab="$STUDY/phase3_post_Pooled/Tables"
if [[ -d "$pooled_tab" ]]; then
  find "$pooled_tab" -maxdepth 1 -type f -name '*.xlsx' -print0 | while IFS= read -r -d '' f; do
    copy_xlsx "$f" "Pooled"
  done
fi

# ── 主文 logistic：仅三分位 → Table 2（二分/四分位不进 summary_result）──
# 规则写入流水线：闸门确认主分组=tertile 后，binary/quartile 仅留在 step 目录作敏感性，不汇总
_copy_locked_logistic() {
  local db="$1" kind="$2"  # 仅调用 tertile
  local base_dir out_name
  if [[ "$db" == "Pooled" ]]; then
    base_dir="$STUDY/phase3_post_Pooled"
  else
    base_dir="$STUDY/phase1_${db}_allages"
  fi
  case "$kind" in
    tertile)  out_name="Table 2-${db}. Logistic regression analysis of Frailty Index and Hip fracture - tertile (GLM).xlsx" ;;
    *) return 0 ;;
  esac
  local csv x dir
  csv=$(find "$base_dir" -type f -name "Model2Factors_${kind}_glm.csv" ! -path '*_rcs*' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
  [[ -n "$csv" && -f "$csv" ]] || return 0
  dir=$(dirname "$csv")
  x=$(find "$dir" -type f -name '*.xlsx' ! -name '*RCS*' 2>/dev/null | head -1)
  if [[ -n "$x" && -f "$x" ]]; then
    cp -a "$x" "$OUT/table/$out_name"
    echo "locked $kind $db <- $x"
  fi
}
for db in CHARLS ELSA HRS Pooled; do
  _copy_locked_logistic "$db" tertile
done

# 纵向中介临时名（reorder → S7）
for db in CHARLS ELSA HRS Pooled; do
  src="$STUDY/phase3_long_${db}/Tables/Table_Mediation_Longitudinal_FI_Depression_Hip.xlsx"
  if [[ -f "$src" ]]; then
    cp -a "$src" "$OUT/table/Table S-MED-${db}. Longitudinal mediation FI→Depression→Hip fracture.xlsx"
  fi
done
# 合并版 S6 / S7（phase3 末尾写出）
if [[ -f "$STUDY/phase3_long_Pooled/Tables/Table S6. Correlation regression FI Depression Hip fracture.xlsx" ]]; then
  cp -a "$STUDY/phase3_long_Pooled/Tables/Table S6. Correlation regression FI Depression Hip fracture.xlsx" \
     "$OUT/table/Table S6. Correlation regression FI Depression Hip fracture.xlsx"
fi
if [[ -f "$STUDY/summary_result/table/Table S6. Correlation regression FI Depression Hip fracture.xlsx" ]]; then
  cp -a "$STUDY/summary_result/table/Table S6. Correlation regression FI Depression Hip fracture.xlsx" \
     "$OUT/table/Table S6. Correlation regression FI Depression Hip fracture.xlsx" 2>/dev/null || true
fi
if [[ -f "$STUDY/phase3_long_Pooled/Tables/Table S7. Longitudinal mediation Frailty Index→Depression→Hip fracture.xlsx" ]]; then
  cp -a "$STUDY/phase3_long_Pooled/Tables/Table S7. Longitudinal mediation Frailty Index→Depression→Hip fracture.xlsx" \
     "$OUT/table/Table S7. Longitudinal mediation Frailty Index→Depression→Hip fracture.xlsx"
fi
if [[ -f "$STUDY/summary_result/table/Table S7. Longitudinal mediation Frailty Index→Depression→Hip fracture.xlsx" ]]; then
  cp -a "$STUDY/summary_result/table/Table S7. Longitudinal mediation Frailty Index→Depression→Hip fracture.xlsx" \
     "$OUT/table/Table S7. Longitudinal mediation Frailty Index→Depression→Hip fracture.xlsx" 2>/dev/null || true
fi

# 兜底：若 step 拷贝失败，再从根 Tables 找 tertile
_copy_table2_tertile() {
  local db="$1"
  local dest="$OUT/table/Table 2-${db}. Logistic regression analysis of Frailty Index and Hip fracture - tertile (GLM).xlsx"
  [[ -f "$dest" ]] && return 0
  local hit=""
  hit=$(ls -1 "$OUT/table"/Table\ S*-${db}.\ Logistic\ regression\ analysis\ of\ *\ and\ Hip\ fracture\ -\ tertile\ \(GLM\).xlsx 2>/dev/null | head -1 || true)
  if [[ -n "${hit:-}" && -f "$hit" ]]; then
    cp -a "$hit" "$dest"
  fi
}
for db in CHARLS ELSA HRS Pooled; do
  _copy_table2_tertile "$db"
done
# RCS cutoff 组表 → Table S-XX（不顺延数字链；四库均需；primary cutoff 二分；协变量=主文锁定）
# 按 Model2Factors_quartile_glm.csv 最新 mtime 定位（与 Table 2 locked 同策略）
_copy_locked_rcs_sxx() {
  local db="$1"
  local base_dir dest csv dir x
  if [[ "$db" == "Pooled" ]]; then
    base_dir="$STUDY/phase3_post_Pooled"
  else
    base_dir="$STUDY/phase1_${db}_allages"
  fi
  dest="$OUT/table/Table S-XX-${db}. Logistic regression analysis of Frailty Index and Hip fracture - quartile (GLM, RCS cutoff groups).xlsx"
  # 优先：含 RCS 的 step 目录里最新 Model2Factors_quartile_glm.csv
  csv=$(find "$base_dir" -type f -name "Model2Factors_quartile_glm.csv" -path '*rcs*' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
  if [[ -z "${csv:-}" || ! -f "${csv:-}" ]]; then
    csv=$(find "$base_dir" -type f -name "Model2Factors_quartile_glm.csv" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
  fi
  if [[ -n "${csv:-}" && -f "$csv" ]]; then
    dir=$(dirname "$csv")
    x=$(find "$dir" -type f -name '*RCS cutoff groups*.xlsx' 2>/dev/null | head -1)
    if [[ -n "${x:-}" && -f "$x" ]]; then
      cp -a "$x" "$dest"
      echo "locked RCS S-XX $db <- $x"
      return 0
    fi
  fi
  # 兜底：根 Tables 里 Frailty Index + RCS quartile
  x=$(ls -1t "$base_dir/Tables"/Table\ S*-${db}.\ Logistic\ regression\ analysis\ of\ Frailty\ Index\ and\ Hip\ fracture\ -\ quartile\ \(GLM,\ RCS\ cutoff\ groups\).xlsx 2>/dev/null | head -1 || true)
  if [[ -n "${x:-}" && -f "$x" ]]; then
    cp -a "$x" "$dest"
    echo "fallback RCS S-XX $db <- $x"
  fi
}
for db in CHARLS ELSA HRS Pooled; do
  _copy_locked_rcs_sxx "$db"
done
# 清掉 collect 过程中散落的非 S-XX / tertile|binary RCS 副本（保留四库 S-XX）
find "$OUT/table" -maxdepth 1 -type f -name '*RCS cutoff groups*.xlsx' ! -name 'Table S-XX-*' -delete 2>/dev/null || true

# Pooled bind N
if [[ -f "$STUDY/phase2_Pooled/Tables/Table_Pooled_bind_N.csv" ]]; then
  cp -a "$STUDY/phase2_Pooled/Tables/Table_Pooled_bind_N.csv" "$OUT/table/Table_Pooled_bind_N.csv"
fi

# 敏感性表（S9–S17.1）：仅收文件名含 Sensitivity 的正式表；不覆盖主文 T1/T2/S5
if [[ -d "$STUDY/sensitivity" ]]; then
  find "$STUDY/sensitivity" -type f \( -name 'Table S9*Sensitivity*.xlsx' \
    -o -name 'Table S10*Sensitivity*.xlsx' -o -name 'Table S11*Sensitivity*.xlsx' \
    -o -name 'Table S12*Sensitivity*.xlsx' -o -name 'Table S13*Sensitivity*.xlsx' \
    -o -name 'Table S14*Sensitivity*.xlsx' -o -name 'Table S15*Sensitivity*.xlsx' \
    -o -name 'Table S16*Sensitivity*.xlsx' -o -name 'Table S17*Sensitivity*.xlsx' \
    -o -name 'README_sensitivity.txt' \) -print0 2>/dev/null \
  | while IFS= read -r -d '' f; do
      cp -a "$f" "$OUT/table/$(basename "$f")"
    done
fi

# 图：统一成「Figure <n>-DB. 标题.pdf」，与 reorder 白名单一致
_fig_dest_name() {
  local base="$1" tag="$2"
  local stem="${base%.*}" ext="${base##*.}"
  # 已是 Figure X-DB. 形式
  if [[ "$stem" =~ ^Figure[[:space:]].+-(CHARLS|ELSA|HRS|Pooled)\. ]]; then
    printf '%s' "$base"
    return 0
  fi
  case "$stem" in
    "Figure Missing Value Overview")
      printf 'Figure Missing Value Overview-%s.pdf' "$tag"; return 0 ;;
    "Figure 2. RCS plot between Frailty Index and Hip Fracture"|"Figure 2. RCS plot between FI and Hip Fracture")
      printf 'Figure 2-%s. RCS plot between FI and Hip Fracture.pdf' "$tag"; return 0 ;;
    "Figure 3. Subgroup Forest analyses of FI"|"Figure 2. Subgroup Forest analyses of FI")
      # 亚组森林统一 Figure 3；若同目录有 Figure 3 优先保留 3
      printf 'Figure 3-%s. Subgroup Forest analyses of FI.pdf' "$tag"; return 0 ;;
    "Figure S1. ROC Frailty Index"|"Figure S1. ROC FI")
      # ROC 不再占 S1（S1 留给 CLPN edge bootstrap）；collect 阶段改挂临时名，reorder → S11
      printf 'Figure S11-%s. ROC FI.pdf' "$tag"; return 0 ;;
    # Figure S2 FI 箱线已废弃：勿收进 summary（与 S4 定义冲突）
    "Figure S2. Boxplot FI by Disease Group"|"Figure S6. Boxplot FI by Disease Group")
      return 1 ;;
    "Figure S1. CLPN edge weight bootstrap"|"Figure S1. CLPN edge-weight bootstrap")
      printf 'Figure S1-%s. CLPN edge weight bootstrap.pdf' "$tag"; return 0 ;;
    "Figure S2. CLPN case-dropping stability")
      printf 'Figure S2-%s. CLPN case-dropping stability.pdf' "$tag"; return 0 ;;
    "Figure S3. Boxplot Age by Disease Group")
      printf 'Figure S3-%s. Boxplot Age by Disease Group.pdf' "$tag"; return 0 ;;
    "Figure S4. Boxplot BMI by Disease Group")
      printf 'Figure S4-%s. Boxplot BMI by Disease Group.pdf' "$tag"; return 0 ;;
    "Figure 4. RCS plot between Frailty Index and Hip Fracture"|"Figure 3. RCS plot between Frailty Index and Hip Fracture")
      if [[ "$tag" == "Pooled" ]]; then
        printf 'Figure 2-Pooled. RCS plot between FI and Hip Fracture.pdf'
      else
        printf 'Figure 2-%s. RCS plot between FI and Hip Fracture.pdf' "$tag"
      fi
      return 0
      ;;
    "Figure 5. Subgroup Forest analyses of FI")
      printf 'Figure 5-Pooled. Subgroup Forest analyses of FI.pdf'; return 0 ;;
    "Figure S5. ROC Frailty Index")
      printf 'Figure S5-Pooled. ROC FI.pdf'; return 0 ;;
    "Figure S7. Boxplot Age by Disease Group")
      printf 'Figure S7-Pooled. Boxplot Age by Disease Group.pdf'; return 0 ;;
    "Figure S8. Boxplot BMI by Disease Group")
      printf 'Figure S8-Pooled. Boxplot BMI by Disease Group.pdf'; return 0 ;;
  esac
  # Figure N. title → Figure N-tag. title
  if [[ "$stem" =~ ^(Figure[[:space:]][^./]+)\.[[:space:]](.+)$ ]]; then
    printf '%s-%s. %s.%s' "${BASH_REMATCH[1]}" "$tag" "${BASH_REMATCH[2]}" "$ext"
    return 0
  fi
  printf '%s-%s.%s' "$stem" "$tag" "$ext"
}

copy_fig_dir() {
  local src="$1" tag="$2"
  [[ -d "$src" ]] || return 0
  local f base dest
  for f in "$src"/*; do
    [[ -f "$f" ]] || continue
    case "$f" in *.pdf|*.png|*.PDF|*.PNG) ;; *) continue ;; esac
    base=$(basename "$f")
    # 跳过废弃的 FI 疾病组箱线（summary 只保留 Figure S4 描述组间 FI）
    if [[ "$base" =~ Boxplot[[:space:]]+FI[[:space:]]+by[[:space:]]+Disease ]]; then
      continue
    fi
    dest="$(_fig_dest_name "$base" "$tag")"
    [[ -n "${dest:-}" ]] || continue
    # 若 Figure 2 Subgroup 已由 Figure 3 覆盖则跳过覆盖 RCS 以外的错误 2 号
    if [[ "$base" == "Figure 2. Subgroup Forest analyses of FI.pdf" ]]; then
      # 仅当无 Figure 3 时使用
      if [[ -f "$src/Figure 3. Subgroup Forest analyses of FI.pdf" ]]; then
        continue
      fi
    fi
    cp -a "$f" "$OUT/figure/$dest"
  done
}

for db in CHARLS ELSA HRS; do
  copy_fig_dir "$STUDY/phase1_${db}_allages/Figures" "$db"
  # 逐步目录里的图（缺总 Figures 时）
  find "$STUDY/phase1_${db}_allages" -type d -name Figures 2>/dev/null | while read -r d; do
    copy_fig_dir "$d" "$db"
  done
done
copy_fig_dir "$STUDY/phase3_post_Pooled/Figures" "Pooled"
find "$STUDY/phase3_post_Pooled" -type d -name Figures 2>/dev/null | while read -r d; do
  copy_fig_dir "$d" "Pooled"
done
# 统一 Pooled RCS 为 Figure 2（与三库命名一致；源常为 Figure 4/3）
for cand in \
  "$OUT/figure/Figure 2-Pooled. RCS plot between FI and Hip Fracture.pdf" \
  "$OUT/figure/Figure 4-Pooled. RCS plot between FI and Hip Fracture.pdf" \
  "$STUDY/phase3_post_Pooled/Figures/Figure 4-Pooled. RCS plot between FI and Hip Fracture.pdf" \
  "$STUDY/phase3_post_Pooled/Figures/Figure 3-Pooled. RCS plot between Frailty Index and Hip Fracture.pdf"
do
  if [[ -f "$cand" ]]; then
    if [[ "$cand" != "$OUT/figure/Figure 2-Pooled. RCS plot between FI and Hip Fracture.pdf" ]]; then
      cp -a "$cand" "$OUT/figure/Figure 2-Pooled. RCS plot between FI and Hip Fracture.pdf"
    fi
    echo "Pooled RCS → Figure 2-Pooled <- $cand"
    break
  fi
done

# 纵向产出（flowchart / Fig1 / country-year / network / forest / mediation / change）
for db in CHARLS ELSA HRS Pooled; do
  src="$STUDY/phase3_long_${db}/Figures"
  if [[ -d "$src" ]]; then
    for f in "$src"/*; do
      [[ -f "$f" ]] || continue
      case "$f" in *.pdf|*.png|*.PDF|*.PNG) ;; *) continue ;; esac
      base=$(basename "$f")
      case "$base" in
        Figure\ 1-*)
          cp -a "$f" "$OUT/figure/$base"
          ;;
        Fig1_*)
          cp -a "$f" "$OUT/figure/Figure L1-${db}. Mean FI by Year and Disease.pdf"
          ;;
        Fig_CountryYear_*)
          cp -a "$f" "$OUT/figure/Figure L2-${db}. FI by Country Year.pdf"
          ;;
        Fig_CLPN_*|Fig_CLPN*)
          cp -a "$f" "$OUT/figure/Figure L3-${db}. CLPN network.pdf"
          ;;
        Figure\ S1-*\ CLPN\ edge*|Figure\ S1-*.\ CLPN\ edge*)
          cp -a "$f" "$OUT/figure/$base"
          ;;
        Figure\ S2-*\ CLPN\ case*|Figure\ S2-*.\ CLPN\ case*)
          cp -a "$f" "$OUT/figure/$base"
          ;;
        Fig_Subgroup_*)
          cp -a "$f" "$OUT/figure/Figure L4-${db}. Subgroup Forest FI binary.pdf"
          ;;
        Fig_Mediation_*|*mediation*)
          cp -a "$f" "$OUT/figure/Figure S3-${db}. Longitudinal mediation path diagram of FI and hip fracture.pdf"
          ;;
        *)
          cp -a "$f" "$OUT/figure/${base%.pdf}-${db}.pdf"
          ;;
      esac
    done
  fi
  tab="$STUDY/phase3_long_${db}/Tables"
  [[ -d "$tab" ]] || continue
  for f in "$tab"/*; do
    [[ -f "$f" ]] || continue
    base=$(basename "$f")
    case "$base" in
      Flowchart_attrition*)
        # 中间件，不进正式 S 编号（Figure 1 流程图已覆盖）
        :
        ;;
      CLPN_edge_bootstrap_*.csv|CLPN_case_dropping_*.csv|CLPN_bootstrap_*.rds)
        cp -a "$f" "$OUT/table/$(basename "$f")"
        ;;
      Table\ S5.\ Change\ analysis*|Table\ S5.1.\ Change\ analysis*)
        cp -a "$f" "$OUT/table/$(basename "$f")"
        ;;
      Table_Change_FI_mean_and_change.csv|Table_Change_FI_mean_and_change.xlsx|Table_Change_FI_mean_and_change_pub.xlsx)
        cp -a "$f" "$OUT/table/${db}_$(basename "$f")"
        ;;
      Table_Change_FI_mean_and_change_twowave.csv|Table_Change_FI_mean_and_change_twowave.xlsx|Table_Change_FI_mean_and_change_twowave_pub.xlsx)
        cp -a "$f" "$OUT/table/${db}_$(basename "$f")"
        ;;
      Table_Change_FI_mean_and_change_pub.rds|Table_Change_FI_mean_and_change_twowave_pub.rds)
        cp -a "$f" "$OUT/table/${db}_$(basename "$f")"
        ;;
      Table_Change_FI_meta.csv|Table_Change_FI_meta_twowave.csv)
        cp -a "$f" "$OUT/table/${db}_$(basename "$f")"
        ;;
      Table3_Correlation*)
        cp -a "$f" "$OUT/table/Table S6-${db}. $base"
        ;;
      Table_Mediation_Longitudinal_FI_Depression_Hip.xlsx|Table_Mediation_Longitudinal*.xlsx)
        # 分库中介表不进 summary（仅保留合并 Table S7）
        :
        ;;
      Table_Mediation_Longitudinal_pub.rds|Table3_Correlation_Regression_pub.rds)
        cp -a "$f" "$OUT/table/${db}_$(basename "$f")"
        ;;
      Table\ S8-*.\ CLPN\ adjacency.csv)
        cp -a "$f" "$OUT/table/$(basename "$f")"
        ;;
      CLPN_adjacency.csv)
        cp -a "$f" "$OUT/table/Table S8-${db}. CLPN adjacency.csv"
        ;;
      CLPN_adjacency_raw_codes.csv|CLPN_FI_item_label_dictionary.csv)
        cp -a "$f" "$OUT/table/${db}_$base"
        ;;
      Fig1_FI_by_Year_Disease.csv|CountryYear_p_FI.csv|Subgroup_OR_*)
        cp -a "$f" "$OUT/table/${db}_$base"
        ;;
    esac
  done
done

# 若 phase 已生成 Table S5 / S5.1 / S6 / S7，确保进 summary（也从分库 pub.rds 现组合并；
# long_figs 曾写 summary_result 会被本脚本开头 rm -rf 清掉）
_rebuild_s5_from_rds() {
  local which="$1" # auto | twowave
  local engine="${MEDICAL_BLOCKS_ROOT:-/mnt/e/01block/01Block-new-Final}"
  Rscript --vanilla -e "
    study <- Sys.getenv('STUDY_ROOT', unset = '$STUDY')
    root <- Sys.getenv('MEDICAL_BLOCKS_ROOT', unset = '$engine')
    '%||%' <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
    uf <- file.path(root, 'R/utils.R')
    if (file.exists(uf)) try(source(uf, local = FALSE), silent = TRUE)
    f <- file.path(root, 'Blocks/54_cross_lagged_full/20block_cross_lagged_change_logistic.R')
    if (!file.exists(f)) { message('S5 rebuild skip: missing ', f); quit(save='no', status=0) }
    register_block <- function(...) invisible(NULL)
    source(f, local = FALSE)
    if (!exists('cross_lagged_change_build_table_s5')) {
      message('S5 rebuild skip: no function')
      quit(save = 'no', status = 0)
    }
    cohorts <- c('CHARLS', 'ELSA', 'HRS', 'Pooled')
    if ('$which' == 'twowave') {
      rds <- file.path(study, paste0('phase3_long_', cohorts), 'Tables',
                       'Table_Change_FI_mean_and_change_twowave_pub.rds')
      out <- file.path(study, 'summary_result', 'table',
        'Table S5.1. Change analysis Mean FI and FI change.xlsx')
      title <- 'Table S5.1. Change analysis Mean FI and FI change'
    } else {
      rds <- file.path(study, paste0('phase3_long_', cohorts), 'Tables',
                       'Table_Change_FI_mean_and_change_pub.rds')
      out <- file.path(study, 'summary_result', 'table',
        'Table S5. Change analysis Mean FI and FI change.xlsx')
      title <- 'Table S5. Change analysis Mean FI and FI change'
    }
    if (!any(file.exists(rds))) { message('S5 rebuild: no rds'); quit(save='no', status=0) }
    dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
    res <- cross_lagged_change_build_table_s5(rds, out, cohorts = cohorts, title = title)
    message('S5 rebuilt: ', out, ' cohorts=', paste(res\$cohorts, collapse=','),
            ' | ', res\$n_events %||% '')
  " || true
}
_rebuild_s6_s7_from_rds() {
  local engine="${MEDICAL_BLOCKS_ROOT:-/mnt/e/01block/01Block-new-Final}"
  Rscript --vanilla -e "
    study <- Sys.getenv('STUDY_ROOT', unset = '$STUDY')
    root <- Sys.getenv('MEDICAL_BLOCKS_ROOT', unset = '$engine')
    register_block <- function(...) invisible(NULL)
    '%||%' <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
    for (uf in c(file.path(root, 'R/utils.R'), file.path(root, 'R/sci_xlsx_utils.R'))) {
      if (file.exists(uf)) try(source(uf, local = FALSE), silent = TRUE)
    }
    cohorts <- c('CHARLS', 'ELSA', 'HRS')
    out_dir <- file.path(study, 'summary_result', 'table')
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

    # S6
    f6 <- file.path(root, 'Blocks/54_cross_lagged_full/15block_cross_lagged_corr_table.R')
    out6 <- file.path(out_dir, 'Table S6. Correlation regression FI Depression Hip fracture.xlsx')
    if (!file.exists(out6)) {
      if (file.exists(f6)) source(f6, local = FALSE)
      rds6 <- file.path(study, paste0('phase3_long_', cohorts), 'Tables',
                        'Table3_Correlation_Regression_pub.rds')
      if (exists('cross_lagged_corr_build_table_s6', mode = 'function') && any(file.exists(rds6))) {
        res6 <- cross_lagged_corr_build_table_s6(rds6, out6, cohorts = cohorts)
        message('S6 rebuilt: ', out6, ' cohorts=', paste(res6\$cohorts, collapse=','))
      } else message('S6 rebuild skip: fn/rds missing')
    } else message('S6 already present: ', out6)

    # S7 (filename uses unicode arrow U+2192)
    f7 <- file.path(root, 'Blocks/20_mediation/06block_mediation_longitudinal.R')
    out7 <- file.path(out_dir, paste0(
      'Table S7. Longitudinal mediation Frailty Index',
      intToUtf8(0x2192L), 'Depression', intToUtf8(0x2192L), 'Hip fracture.xlsx'
    ))
    if (!file.exists(out7)) {
      if (file.exists(f7)) source(f7, local = FALSE)
      rds7 <- file.path(study, paste0('phase3_long_', cohorts), 'Tables',
                        'Table_Mediation_Longitudinal_pub.rds')
      if (exists('cross_lagged_mediation_build_table_s7', mode = 'function') && any(file.exists(rds7))) {
        res7 <- cross_lagged_mediation_build_table_s7(rds7, out7, cohorts = cohorts)
        message('S7 rebuilt: ', out7, ' cohorts=', paste(res7\$cohorts, collapse=','))
      } else message('S7 rebuild skip: fn/rds missing')
    } else message('S7 already present: ', out7)
  " || true
}
export STUDY_ROOT="$STUDY"
export MEDICAL_BLOCKS_ROOT="${MEDICAL_BLOCKS_ROOT:-/mnt/e/01block/01Block-new-Final}"
# 始终从分库 rds 重建 S5/S5.1（含 Pooled + 表内 N/Events + 表注），避免陈旧缺列表
_rebuild_s5_from_rds auto
_rebuild_s5_from_rds twowave
# S6/S7: long_figs 合并表会被开头 rm -rf 清掉 → 从分库 rds 重建
_rebuild_s6_s7_from_rds

{
  echo "summary_result — Hip fracture × Frailty (cross-lagged PMID 40595747)"
  echo "generated: $(date -Iseconds)"
  echo "cohorts: CHARLS + ELSA + HRS + Pooled"
  echo "tables: T1 + S1–S4 | Table2 tertile ONLY | S-XX RCS | S5 change(auto) | S5.1 change(all two_wave) | S6 corr (M1≠M2) | S7 mediation(merged only) | S8 CLPN labeled | S9–S17.1 sensitivity"
  echo "figures: Missing | RCS | Subgroup | Fig1 flowchart | Fig4 CLPN | S1 edge-boot | S2 case-drop | S3 mediation | S4–S5 FI desc | L1-L4 long panels | S11 ROC"
  echo "summary policy: main logistic=tertile; Change S5=auto(2y/3y+); S5.1=all two_wave; S6=corr Crude/M1/M2(M1≠M2); S7=merged longitudinal mediation only; S8=CLPN adjacency with FI item labels; S1/S2=CLPN bootstrap stability (lit Supp 25–26); S9–S17.1 sensitivity (chronic>=2 / complete-case unimputed listwise N may be <AfterMI / exclude event<=2y; competing_risk skipped); no per-DB S7; no S9 flowchart tables"
  echo "attrition: drop if baseline ID absent from ALL follow-up years; FU time = first disease year else last FU year"
  echo
  echo "=== figure ==="; ls -1 "$OUT/figure" 2>/dev/null | sort || true
  echo; echo "=== table ==="; ls -1 "$OUT/table" 2>/dev/null | sort || true
} > "$OUT/MANIFEST.txt"

echo "Done: $OUT"
echo "figure: $(ls -1 "$OUT/figure" 2>/dev/null | wc -l)  table: $(ls -1 "$OUT/table" 2>/dev/null | wc -l)"

ENG_ROOT="${MEDICAL_BLOCKS_ROOT:-}"
if [[ -z "$ENG_ROOT" ]]; then
  ENG_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
fi
Rscript "$ENG_ROOT/Blocks/54_cross_lagged_full/phases/export_summary_figures.R" "$STUDY"
