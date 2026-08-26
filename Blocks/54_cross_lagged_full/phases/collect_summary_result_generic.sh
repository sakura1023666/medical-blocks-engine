#!/usr/bin/env bash
# 固定出版清单收图/表（所有交叉滞后课题同一槽位，不拷中间件）。
# 清单：phases/PUBLICATION_SLOTS.md
#   Fig1–4, S1/S2 网络稳定性, S3 中介, S4/S5, S11 ROC
#   表 T1/T2/S1/S3–S8 + 敏感性 S9–S17.1
# 横断面第三库：有 NHANES 则用 NHANES（对应髋部 HRS）；纵向仅存在的 phase3_long_*。
set -euo pipefail
STUDY="${1:-${CROSS_LAGGED_STUDY_ROOT:-}}"
if [[ -z "$STUDY" || ! -d "$STUDY" ]]; then
  echo "need study_root" >&2
  exit 1
fi
OUT="$STUDY/summary_result"
TAB="$OUT/table"
FIG="$OUT/figure"
TMP="$OUT/_align_tmp"
rm -rf "$TMP"
mkdir -p "$TMP/table" "$TMP/figure"

cp_one() {
  local src="$1" dst="$2"
  [[ -f "$src" ]] || return 0
  mkdir -p "$(dirname "$dst")"
  cp -a "$src" "$dst"
}

first_existing() {
  local f
  for f in "$@"; do
    [[ -f "$f" ]] && { printf '%s' "$f"; return 0; }
  done
  return 1
}

_phase1() {
  local db="$1"
  if [[ -d "$STUDY/phase1_${db}" ]]; then echo "$STUDY/phase1_${db}"
  elif [[ -d "$STUDY/phase1_${db}_allages" ]]; then echo "$STUDY/phase1_${db}_allages"
  else echo "$STUDY/phase1_${db}"
  fi
}

IS_CIRC=0
if [[ -f "$STUDY/config_long_panel.R" ]] && grep -qE "circadian_index_var|ePWV" "$STUDY/config_long_panel.R" 2>/dev/null; then
  IS_CIRC=1
fi

if [[ "$IS_CIRC" == "1" ]]; then
  XS=(CHARLS ELSA NHANES)
  T1_SUF="Baseline characteristics of Circadian disorder.xlsx"
  T2_SUF="Logistic regression analysis of ePWV and Circadian disorder - quartile (GLM).xlsx"
  FIG2_SUF="RCS plot between ePWV and Circadian Disorder.pdf"
  FIG3_SUF="Subgroup Forest analyses of ePWV.pdf"
  FIG4_SUF="CLPN network of circadian conditions.pdf"
  S3_SUF="Longitudinal mediation path diagram of ePWV FI and circadian disorder.pdf"
  S4_SUF="Mean ePWV by Year and Disease.pdf"
  S5_NAME="Figure S5. Mean ePWV by Country and Disease.pdf"
  S6_NAME="Table S6. Correlation regression ePWV FI Circadian disorder.xlsx"
  S7_NAME="Table S7. Longitudinal mediation ePWV→FI→Circadian disorder.xlsx"
  S11_SUF="ROC ePWV.pdf"
else
  XS=(CHARLS ELSA HRS)
  T1_SUF="Baseline characteristics of Hip fracture.xlsx"
  T2_SUF="Logistic regression analysis of Frailty Index and Hip fracture - tertile (GLM).xlsx"
  FIG2_SUF="RCS plot between Frailty Index and Hip Fracture.pdf"
  FIG3_SUF="Subgroup Forest analyses of FI.pdf"
  FIG4_SUF="CLPN network of frailty index items.pdf"
  S3_SUF="Longitudinal mediation path diagram of FI and hip fracture.pdf"
  S4_SUF="Mean FI by Year and Disease.pdf"
  S5_NAME="Figure S5. Mean FI by Country and Disease.pdf"
  S6_NAME="Table S6. Correlation regression FI Depression Hip fracture.xlsx"
  S7_NAME="Table S7. Longitudinal mediation Frailty Index→Depression→Hip fracture.xlsx"
  S11_SUF="ROC FI.pdf"
fi

LONG=()
for db in CHARLS ELSA HRS; do
  if [[ -d "$STUDY/phase3_long_${db}" ]]; then
    LONG+=("$db")
  fi
done

# ── TABLES ──────────────────────────────────────────────────────────────────
for db in "${XS[@]}"; do
  p1="$(_phase1 "$db")"
  # Table 1 — 优先 phase1 新表，避免 summary_result 里旧表覆盖重建结果
  src=$(first_existing \
    "$p1/Tables/Table 1-${db}. Baseline characteristics of Circadian rhythm.xlsx" \
    "$p1/Tables/Table 1-${db}. Baseline characteristics of Circadian disorder.xlsx" \
    "$p1/Tables/Table 1-USA. Baseline characteristics of Circadian rhythm.xlsx" \
    "$p1/Tables/Table 1-USA. Baseline characteristics of Circadian disorder.xlsx" \
    "$p1/Tables/Table 1-${db}. Baseline characteristics of Hip fracture.xlsx" \
    "$p1/Tables/Table 1. Baseline characteristics of Hip fracture.xlsx" \
    "$p1/Tables/Table 1. Baseline characteristics of Circadian rhythm.xlsx" \
    "$TAB/Table 1-${db}. ${T1_SUF}" \
    || true)
  cp_one "${src:-}" "$TMP/table/Table 1-${db}. ${T1_SUF}"

  # Table S1
  src=$(first_existing \
    "$TAB/Table S1-${db}. Baseline characteristics of patients before and after multiple imputation.xlsx" \
    "$p1/Tables/Table S1-${db}. Baseline characteristics before and after imputation.xlsx" \
    "$p1/Tables/Table S1-USA. Baseline characteristics before and after imputation.xlsx" \
    "$p1/Tables/Table S1-${db}. Baseline characteristics of patients before and after multiple imputation.xlsx" \
    "$p1/Tables/Table S1. Baseline characteristics of patients before and after multiple imputation.xlsx" \
    || true)
  cp_one "${src:-}" "$TMP/table/Table S1-${db}. Baseline characteristics of patients before and after multiple imputation.xlsx"

  # Table S3
  src=$(first_existing \
    "$TAB/Table S3-${db}. Univariate Regression Analysis.xlsx" \
    "$p1/Tables/Table S3-${db}. Univariate Regression Analysis.xlsx" \
    "$p1/Tables/Table S3-USA. Univariate Regression Analysis.xlsx" \
    "$p1/Tables/Table S3. Univariate Regression Analysis.xlsx" \
    || true)
  cp_one "${src:-}" "$TMP/table/Table S3-${db}. Univariate Regression Analysis.xlsx"

  # Table S4 VIF screen
  src=$(first_existing \
    "$TAB/Table S4-${db}. Multicollinearity Analysis (VIF, univariate p 0.1 screen).xlsx" \
    "$p1/Tables/Table S4-${db}. Multicollinearity Analysis (VIF, univariate p 0.1 screen).xlsx" \
    "$p1/Tables/Table S4-${db}. Multicollinearity Analysis VIF screen.xlsx" \
    "$p1/Tables/Table S4-USA. Multicollinearity Analysis VIF screen.xlsx" \
    "$p1/Tables/Table S4. Multicollinearity Analysis (VIF, univariate p 0.1 screen).xlsx" \
    || true)
  cp_one "${src:-}" "$TMP/table/Table S4-${db}. Multicollinearity Analysis (VIF, univariate p 0.1 screen).xlsx"
done

# Table 2：CHARLS/ELSA/第三库 + Pooled
for db in "${XS[@]}" Pooled; do
  if [[ "$db" == "Pooled" ]]; then
    pdir="$STUDY/phase3_post_Pooled"
  else
    pdir="$(_phase1 "$db")"
  fi
  src=$(first_existing \
    "$TAB/Table 2-${db}. ${T2_SUF}" \
    "$pdir/Tables/Table 2-${db}. Logistic regression of ePWV quartile.xlsx" \
    "$pdir/Tables/Table 3-${db}. Logistic regression of ePWV quartile.xlsx" \
    "$p1/Tables/Table 2-${db}. Logistic regression of ePWV quartile.xlsx" \
    "$p1/Tables/Table 3-${db}. Logistic regression of ePWV quartile.xlsx" \
    "$pdir/Tables/Table 2-USA. Logistic regression of ePWV quartile.xlsx" \
    "$pdir/Tables/Table 1-Pooled. Logistic regression of ePWV quartile.xlsx" \
    "$pdir/Tables/Table 2-${db}. Logistic regression analysis of Frailty Index and Hip fracture - tertile (GLM).xlsx" \
    "$pdir/Tables/Table 2-${db}. Logistic regression analysis of ePWV and Circadian disorder - quartile (GLM).xlsx" \
    || true)
  cp_one "${src:-}" "$TMP/table/Table 2-${db}. ${T2_SUF}"
done

# S5 / S5.1 / S6 / S7 合并表
cp_one "$TAB/Table S5. Change analysis Mean FI and FI change.xlsx" \
       "$TMP/table/Table S5. Change analysis Mean FI and FI change.xlsx"
cp_one "$STUDY/summary_result/table/Table S5. Change analysis Mean FI and FI change.xlsx" \
       "$TMP/table/Table S5. Change analysis Mean FI and FI change.xlsx"
# 上面 TAB 可能已是旧目录；TMP 写入时 TAB 仍在
for cand in \
  "$OUT/table/Table S5. Change analysis Mean FI and FI change.xlsx"
do
  cp_one "$cand" "$TMP/table/Table S5. Change analysis Mean FI and FI change.xlsx"
done
cp_one "$OUT/table/Table S5.1. Change analysis Mean FI and FI change.xlsx" \
       "$TMP/table/Table S5.1. Change analysis Mean FI and FI change.xlsx"

src=$(first_existing \
  "$OUT/table/$S6_NAME" \
  "$OUT/table/Table S6. Correlation regression.xlsx" \
  "$OUT/table/Table S6. Correlation regression ePWV FI Circadian disorder.xlsx" \
  "$OUT/table/Table S6. Correlation regression FI Depression Hip fracture.xlsx" \
  || true)
cp_one "${src:-}" "$TMP/table/$S6_NAME"

src=$(first_existing \
  "$OUT/table/$S7_NAME" \
  "$OUT/table/Table S7. Longitudinal mediation.xlsx" \
  "$OUT/table/Table S7. Longitudinal mediation ePWV to FI to Circadian disorder.xlsx" \
  "$OUT/table/Table S7. Longitudinal mediation Frailty Index→Depression→Hip fracture.xlsx" \
  || true)
cp_one "${src:-}" "$TMP/table/$S7_NAME"

# S8 CLPN
for db in "${LONG[@]}"; do
  src=$(first_existing \
    "$STUDY/phase3_long_${db}/Tables/Table S8-${db}. CLPN adjacency.csv" \
    "$OUT/table/Table S8-${db}. CLPN adjacency.csv" \
    || true)
  cp_one "${src:-}" "$TMP/table/Table S8-${db}. CLPN adjacency.csv"
done

# CLPN bootstrap 旁表（与髋部 summary 一致：不收 CHARLS，收 ELSA + 第三纵向库）
for db in "${LONG[@]}"; do
  if [[ "$db" == "CHARLS" ]]; then
    continue
  fi
  for bn in \
    "CLPN_bootstrap_${db}.rds" \
    "CLPN_case_dropping_${db}.csv" \
    "CLPN_edge_bootstrap_${db}.csv"
  do
    src=$(first_existing \
      "$STUDY/phase3_long_${db}/Tables/$bn" \
      "$OUT/table/$bn" \
      || true)
    cp_one "${src:-}" "$TMP/table/$bn"
  done
done

# 敏感性 S9–S17.1：只收正式 Sensitivity 基线/logistic/Change，不要 Normality 与截断名
if [[ -d "$STUDY/sensitivity" ]]; then
  find "$STUDY/sensitivity" -type f \( \
      -name 'Table S*Sensitivity*Baseline characteristics*.xlsx' \
      -o -name 'Table S*Sensitivity*Logistic regression*GLM*.xlsx' \
      -o -name 'Table S*Sensitivity*Change analysis*.xlsx' \
      -o -name 'README_sensitivity.txt' \
    \) -print0 2>/dev/null \
  | while IFS= read -r -d '' f; do
      cp_one "$f" "$TMP/table/$(basename "$f")"
    done
fi
cp_one "$OUT/table/README_sensitivity.txt" "$TMP/table/README_sensitivity.txt"
cp_one "$STUDY/phase2_Pooled/Figure3_subgroup_var_lock.txt" "$TMP/table/Figure3_subgroup_var_lock.txt"
cp_one "$STUDY/summary_result/table/Figure3_subgroup_var_lock.txt" "$TMP/table/Figure3_subgroup_var_lock.txt"

# 合并 S5 / S5.1 / S6 / S7（从分库 rds 重建）
export STUDY_ROOT="$STUDY"
export MEDICAL_BLOCKS_ROOT="${MEDICAL_BLOCKS_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
Rscript --vanilla -e '
study <- Sys.getenv("STUDY_ROOT")
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT")
register_block <- function(...) invisible(NULL)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
uf <- file.path(root, "R/utils.R")
if (file.exists(uf)) try(source(uf, local = FALSE), silent = TRUE)
out_dir <- "'"$TMP"'/table"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
all_cohorts <- c("CHARLS", "ELSA", "HRS", "NHANES")
have <- all_cohorts[dir.exists(file.path(study, paste0("phase3_long_", all_cohorts)))]
is_circ <- file.exists(file.path(study, "config_long_panel.R")) &&
  any(grepl("circadian_index_var|ePWV", readLines(file.path(study, "config_long_panel.R"), warn = FALSE)))
# 节律病节点：Pooled 单独收（其 pub.rds 与各库同名，但 db 字段为 "Pooled"）
if (is_circ && dir.exists(file.path(study, "phase3_long_Pooled")))
  have <- c(have, "Pooled")
s6 <- if (is_circ) "Table S6. Correlation regression ePWV FI Circadian disorder.xlsx" else
  "Table S6. Correlation regression FI Depression Hip fracture.xlsx"
s7 <- if (is_circ) {
  paste0("Table S7. Longitudinal mediation ePWV", intToUtf8(0x2192L), "FI", intToUtf8(0x2192L), "Circadian disorder.xlsx")
} else {
  paste0("Table S7. Longitudinal mediation Frailty Index", intToUtf8(0x2192L), "Depression", intToUtf8(0x2192L), "Hip fracture.xlsx")
}
f5 <- file.path(root, "Blocks/54_cross_lagged_full/20block_cross_lagged_change_logistic.R")
if (length(have) && file.exists(f5)) {
  source(f5, local = FALSE)
  if (exists("cross_lagged_change_build_table_s5", mode = "function")) {
    rds <- file.path(study, paste0("phase3_long_", have), "Tables", "Table_Change_FI_mean_and_change_pub.rds")
    if (any(file.exists(rds)))
      cross_lagged_change_build_table_s5(rds, file.path(out_dir, "Table S5. Change analysis Mean FI and FI change.xlsx"), cohorts = have)
    rds1 <- file.path(study, paste0("phase3_long_", have), "Tables", "Table_Change_FI_mean_and_change_twowave_pub.rds")
    if (any(file.exists(rds1)))
      cross_lagged_change_build_table_s5(rds1, file.path(out_dir, "Table S5.1. Change analysis Mean FI and FI change.xlsx"), cohorts = have, title = "Table S5.1. Change analysis Mean FI and FI change")
  }
}
f6 <- file.path(root, "Blocks/54_cross_lagged_full/15block_cross_lagged_corr_table.R")
if (length(have) && file.exists(f6)) {
  source(f6, local = FALSE)
  if (exists("cross_lagged_corr_build_table_s6", mode = "function")) {
    rds6 <- file.path(study, paste0("phase3_long_", have), "Tables", "Table3_Correlation_Regression_pub.rds")
    if (any(file.exists(rds6))) try(cross_lagged_corr_build_table_s6(rds6, file.path(out_dir, s6), cohorts = have), silent = FALSE)
  }
}
f7 <- file.path(root, "Blocks/20_mediation/06block_mediation_longitudinal.R")
if (length(have) && file.exists(f7)) {
  source(f7, local = FALSE)
  if (exists("cross_lagged_mediation_build_table_s7", mode = "function")) {
    rds7 <- file.path(study, paste0("phase3_long_", have), "Tables", "Table_Mediation_Longitudinal_pub.rds")
    if (any(file.exists(rds7))) try(cross_lagged_mediation_build_table_s7(rds7, file.path(out_dir, s7), cohorts = have), silent = FALSE)
  }
}
' || true

# ── FIGURES ─────────────────────────────────────────────────────────────────
# Fig1 flowchart：纵向库 + Pooled 用纵向纳排；无纵向的横断面库（如 NHANES）补横断面纳排
for db in "${LONG[@]}" Pooled; do
  src=$(first_existing \
    "$STUDY/phase3_long_${db}/Figures/Figure 1-${db}. Longitudinal inclusion exclusion flowchart.pdf" \
    "$OUT/figure/Figure 1-${db}. Longitudinal inclusion exclusion flowchart.pdf" \
    || true)
  cp_one "${src:-}" "$TMP/figure/Figure 1-${db}. Longitudinal inclusion exclusion flowchart.pdf"
done
# XS-only（无 phase3_long_*）：画/收横断面 Figure 1
XS_ONLY=()
for db in "${XS[@]}"; do
  skip=0
  for L in "${LONG[@]}"; do
    [[ "$db" == "$L" ]] && skip=1 && break
  done
  [[ "$skip" == "1" ]] && continue
  XS_ONLY+=("$db")
done
if [[ ${#XS_ONLY[@]} -gt 0 ]]; then
  export STUDY_ROOT="$STUDY"
  export MEDICAL_BLOCKS_ROOT="${MEDICAL_BLOCKS_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
  export XS_ONLY_CSV="$(IFS=,; echo "${XS_ONLY[*]}")"
  Rscript --vanilla -e '
    study <- Sys.getenv("STUDY_ROOT")
    root <- Sys.getenv("MEDICAL_BLOCKS_ROOT")
    dbs <- strsplit(Sys.getenv("XS_ONLY_CSV"), ",", fixed = TRUE)[[1]]
    source(file.path(root, "R/utils.R"), local = FALSE)
    source(file.path(root, "R/attrition_log.R"), local = FALSE)
    source(file.path(root, "R/cross_lagged_covariate_lock.R"), local = FALSE)
    source(file.path(root, "R/cross_lagged_xs_flowchart.R"), local = FALSE)
    for (db in dbs) {
      p <- tryCatch(cross_lagged_draw_xs_fig1(study, db), error = function(e) {
        message(db, " xs fig1: ", e$message); NULL
      })
      if (!is.null(p)) message("xs fig1: ", p)
    }
  ' || true
  for db in "${XS_ONLY[@]}"; do
    p1="$(_phase1 "$db")"
    src=$(first_existing \
      "$p1/Figures/Figure 1-${db}. Inclusion exclusion flowchart.pdf" \
      "$OUT/figure/Figure 1-${db}. Inclusion exclusion flowchart.pdf" \
      || true)
    cp_one "${src:-}" "$TMP/figure/Figure 1-${db}. Inclusion exclusion flowchart.pdf"
  done
fi

# Fig2 RCS：横断面三库 + Pooled
for db in "${XS[@]}"; do
  p1="$(_phase1 "$db")"
  src=$(first_existing \
    "$p1/Figures/Figure 2-${db}. ${FIG2_SUF}" \
    "$p1/Figures/Figure 2-${db}. RCS plot between ePWV and Circadian Disorder.pdf" \
    "$p1/Figures/Figure 2-USA. RCS plot between ePWV and Circadian Disorder.pdf" \
    "$p1/Figures/Figure 2-${db}. RCS plot between Frailty Index and Hip Fracture.pdf" \
    "$OUT/figure/Figure 2-${db}. ${FIG2_SUF}" \
    || true)
  cp_one "${src:-}" "$TMP/figure/Figure 2-${db}. ${FIG2_SUF}"
done
src=$(first_existing \
  "$STUDY/phase3_post_Pooled/Figures/Figure 2-Pooled. RCS plot between ePWV and Circadian Disorder.pdf" \
  "$STUDY/phase3_post_Pooled/Figures/Figure 3-Pooled. RCS plot between ePWV and Circadian Disorder.pdf" \
  "$STUDY/phase3_post_Pooled/Figures/Figure 2-Pooled. RCS plot between Frailty Index and Hip Fracture.pdf" \
  "$OUT/figure/Figure 2-Pooled. ${FIG2_SUF}" \
  || true)
cp_one "${src:-}" "$TMP/figure/Figure 2-Pooled. ${FIG2_SUF}"

# Fig3 亚组：仅单库（不要 Pooled）
for db in "${XS[@]}"; do
  p1="$(_phase1 "$db")"
  src=$(first_existing \
    "$p1/Figures/Figure 3-${db}. ${FIG3_SUF}" \
    "$p1/Figures/Figure 3-${db}. Subgroup Forest analyses of ePWV.pdf" \
    "$p1/Figures/Figure 3-USA. Subgroup Forest analyses of ePWV.pdf" \
    "$p1/Figures/Figure 3-${db}. Subgroup Forest analyses of FI.pdf" \
    "$OUT/figure/Figure 3-${db}. ${FIG3_SUF}" \
    || true)
  cp_one "${src:-}" "$TMP/figure/Figure 3-${db}. ${FIG3_SUF}"
done

# Fig4 CLPN
for db in "${LONG[@]}"; do
  src=$(first_existing \
    "$OUT/figure/Figure 4-${db}. ${FIG4_SUF}" \
    "$STUDY/phase3_long_${db}/Figures/Fig4_CLPN_network_pub.pdf" \
    "$STUDY/phase3_long_${db}/Figures/Fig_CLPN_network.pdf" \
    || true)
  cp_one "${src:-}" "$TMP/figure/Figure 4-${db}. ${FIG4_SUF}"
done

# S1/S2 CLPN bootstrap
for db in "${LONG[@]}"; do
  src=$(first_existing \
    "$STUDY/phase3_long_${db}/Figures/Figure S1-${db}. CLPN edge weight bootstrap.pdf" \
    "$OUT/figure/Figure S1-${db}. CLPN edge weight bootstrap.pdf" \
    || true)
  cp_one "${src:-}" "$TMP/figure/Figure S1-${db}. CLPN edge weight bootstrap.pdf"
  src=$(first_existing \
    "$STUDY/phase3_long_${db}/Figures/Figure S2-${db}. CLPN case-dropping stability.pdf" \
    "$OUT/figure/Figure S2-${db}. CLPN case-dropping stability.pdf" \
    || true)
  cp_one "${src:-}" "$TMP/figure/Figure S2-${db}. CLPN case-dropping stability.pdf"
done

# S3 中介路径
for db in "${LONG[@]}" Pooled; do
  src=$(first_existing \
    "$STUDY/phase3_long_${db}/Figures/Fig_Mediation_Longitudinal_${db}.pdf" \
    "$STUDY/phase3_long_${db}/Figures/Figure S3-${db}. ${S3_SUF}" \
    "$OUT/figure/Figure S3-${db}. ${S3_SUF}" \
    "$OUT/figure/Figure S3-${db}. Longitudinal mediation.pdf" \
    || true)
  cp_one "${src:-}" "$TMP/figure/Figure S3-${db}. ${S3_SUF}"
done

# S4 Mean index by year（昼夜=ePWV；髋部=FI；NHANES 无纵向也收）
S4_DBS=("${LONG[@]}")
if [[ "$IS_CIRC" == "1" ]]; then
  S4_DBS+=(NHANES)
fi
for db in "${S4_DBS[@]}"; do
  src=$(first_existing \
    "$OUT/figure/Figure S4-${db}. ${S4_SUF}" \
    "$STUDY/phase3_long_${db}/Figures/FigS4_Mean_ePWV_by_Year_Disease.pdf" \
    "$STUDY/phase3_long_${db}/Figures/FigS4_Mean_FI_by_Year_Disease.pdf" \
    "$STUDY/phase1_${db}/Figures/FigS4_Mean_ePWV_by_Year_Disease.pdf" \
    "$OUT/figure/Figure S4-${db}. Mean FI by Year and Disease.pdf" \
    "$OUT/figure/Figure S4-${db}. Mean ePWV by Year and Disease.pdf" \
    || true)
  cp_one "${src:-}" "$TMP/figure/Figure S4-${db}. ${S4_SUF}"
done

# S5 country
src=$(first_existing \
  "$OUT/figure/${S5_NAME}" \
  "$OUT/figure/Figure S5. Mean ePWV by Country and Disease.pdf" \
  "$OUT/figure/Figure S5. Mean FI by Country and Disease.pdf" \
  "$STUDY/phase3_long_Pooled/Figures/FigS5_Mean_ePWV_by_Country_Disease.pdf" \
  "$STUDY/phase3_long_Pooled/Figures/FigS5_Mean_FI_by_Country_Disease.pdf" \
  || true)
cp_one "${src:-}" "$TMP/figure/${S5_NAME}"

# S11 ROC（不占 S1）
for db in "${XS[@]}"; do
  p1="$(_phase1 "$db")"
  src=$(first_existing \
    "$p1/Figures/Figure S1-${db}. ROC Multivariable ePWV.pdf" \
    "$p1/Figures/Figure S1-USA. ROC Multivariable ePWV.pdf" \
    "$p1/Figures/Figure S1-${db}. ROC Frailty Index.pdf" \
    "$p1/Figures/Figure S11-${db}. ${S11_SUF}" \
    "$OUT/figure/Figure S11-${db}. ${S11_SUF}" \
    || true)
  cp_one "${src:-}" "$TMP/figure/Figure S11-${db}. ${S11_SUF}"
done

src=$(first_existing \
  "$OUT/figure/README_FigS1_S2_CLPN_bootstrap.txt" \
  "$OUT/figure/README_FigS4_S5_Fig4.txt" \
  || true)
cp_one "${src:-}" "$TMP/figure/README_FigS1_S2_CLPN_bootstrap.txt"

# Fig1-Pooled：若缺则用分库纳排表现画
if [[ ! -f "$TMP/figure/Figure 1-Pooled. Longitudinal inclusion exclusion flowchart.pdf" ]]; then
  Rscript --vanilla -e '
    study <- "'"$STUDY"'"
    out <- file.path(study, "summary_result/_align_tmp/figure",
                     "Figure 1-Pooled. Longitudinal inclusion exclusion flowchart.pdf")
    rows <- list()
    for (db in c("CHARLS", "ELSA", "HRS")) {
      f <- file.path(study, paste0("phase3_long_", db), "Tables",
                     paste0("Flowchart_attrition_", db, ".csv"))
      if (!file.exists(f)) next
      d <- utils::read.csv(f, check.names = FALSE)
      n_final <- if ("n" %in% names(d) && "step" %in% names(d)) {
        d$n[grepl("Final", d$step, ignore.case = TRUE)][1]
      } else NA
      rows[[db]] <- sprintf("%s: see Flowchart_attrition (final n=%s)", db, as.character(n_final))
    }
    if (!length(rows)) quit(save = "no", status = 0)
    dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
    grDevices::pdf(out, width = 8.5, height = 8)
    graphics::plot.new()
    graphics::title("Pooled — attrition by cohort")
    graphics::text(0.05, seq(0.85, 0.5, length.out = length(rows)),
                   labels = unlist(rows), adj = 0, cex = 1.1)
    grDevices::dev.off()
  ' || true
fi

rm -rf "$TAB" "$FIG"
mv "$TMP/table" "$TAB"
mv "$TMP/figure" "$FIG"
rmdir "$TMP" 2>/dev/null || rm -rf "$TMP"

# 出版槽位完整性（纵向无第三库 / 无随访库的槽位标 N/A，不算缺）
missing=()
need_fig() { [[ -f "$FIG/$1" ]] || missing+=("figure/$1"); }
need_tab() { [[ -f "$TAB/$1" ]] || missing+=("table/$1"); }
for db in "${LONG[@]}" Pooled; do
  need_fig "Figure 1-${db}. Longitudinal inclusion exclusion flowchart.pdf"
  need_fig "Figure S3-${db}. ${S3_SUF}"
done
for db in "${XS[@]}"; do
  skip=0
  for L in "${LONG[@]}"; do [[ "$db" == "$L" ]] && skip=1 && break; done
  if [[ "$skip" != "1" ]]; then
    need_fig "Figure 1-${db}. Inclusion exclusion flowchart.pdf"
  fi
done
for db in "${XS[@]}"; do
  need_fig "Figure 2-${db}. ${FIG2_SUF}"
  need_fig "Figure 3-${db}. ${FIG3_SUF}"
  need_fig "Figure S11-${db}. ${S11_SUF}"
  need_tab "Table 1-${db}. ${T1_SUF}"
  need_tab "Table 2-${db}. ${T2_SUF}"
  need_tab "Table S1-${db}. Baseline characteristics of patients before and after multiple imputation.xlsx"
  need_tab "Table S3-${db}. Univariate Regression Analysis.xlsx"
  need_tab "Table S4-${db}. Multicollinearity Analysis (VIF, univariate p 0.1 screen).xlsx"
done
need_fig "Figure 2-Pooled. ${FIG2_SUF}"
need_tab "Table 2-Pooled. ${T2_SUF}"
for db in "${LONG[@]}"; do
  need_fig "Figure 4-${db}. ${FIG4_SUF}"
  need_fig "Figure S1-${db}. CLPN edge weight bootstrap.pdf"
  need_fig "Figure S2-${db}. CLPN case-dropping stability.pdf"
  need_fig "Figure S4-${db}. ${S4_SUF}"
  need_tab "Table S8-${db}. CLPN adjacency.csv"
done
if [[ "$IS_CIRC" == "1" ]]; then
  need_fig "Figure S4-NHANES. ${S4_SUF}"
fi
need_fig "${S5_NAME}"
need_tab "Table S5. Change analysis Mean FI and FI change.xlsx"
need_tab "Table S5.1. Change analysis Mean FI and FI change.xlsx"
need_tab "$S6_NAME"
need_tab "$S7_NAME"
# 敏感性：横断面 S9/S10/S12/S13；纵向另加 S15/S16；合并 Change S11/S14/S17
if [[ -d "$STUDY/sensitivity" ]]; then
  n_sens=$(find "$TAB" -maxdepth 1 -type f \( -name 'Table S9*.xlsx' -o -name 'Table S10*.xlsx' \
    -o -name 'Table S12*.xlsx' -o -name 'Table S13*.xlsx' \) | wc -l)
  if [[ "$n_sens" -eq 0 ]]; then
    missing+=("table/S9–S13 sensitivity (run phase_sensitivity.R)")
  fi
  n_early=$(find "$TAB" -maxdepth 1 -type f \( -name 'Table S15*.xlsx' -o -name 'Table S16*.xlsx' \) | wc -l)
  if [[ ${#LONG[@]} -gt 0 && "$n_early" -eq 0 ]]; then
    missing+=("table/S15–S16 sensitivity (run phase_sensitivity.R)")
  fi
  [[ -f "$TAB/README_sensitivity.txt" ]] || missing+=("table/README_sensitivity.txt")
else
  missing+=("sensitivity/ (run phase_sensitivity.R)")
fi

{
  echo "summary_result aligned to PUBLICATION_SLOTS.md"
  echo "generated: $(date -Iseconds)"
  echo "study: $STUDY"
  echo "XS cohorts: ${XS[*]}"
  echo "LONG cohorts: ${LONG[*]}"
  echo "figures: Fig1 flowchart | Fig2 RCS | Fig3 subgroup (no Pooled) | Fig4 CLPN | S1 edge-boot | S2 case-drop | S3 mediation | S4–S5 FI desc | S11 ROC"
  echo "tables: T1 | T2 | S1 | S3 | S4 VIF screen | S5/S5.1 change | S6 corr merged | S7 mediation merged | S8 CLPN | S9–S17.1 sensitivity"
  echo "excluded: S2 normality, multivariable, VIF final, RCS S-XX, boxplot, missing-overview, Fig3-Pooled, per-DB S6/S7, raw csv/rds except CLPN bootstrap"
  echo
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "=== MISSING slots ==="
    printf '%s\n' "${missing[@]}"
    echo
  else
    echo "=== MISSING slots === (none)"
    echo
  fi
  echo "=== figure ==="; ls -1 "$FIG" | sort
  echo; echo "=== table ==="; ls -1 "$TAB" | sort
} > "$OUT/MANIFEST.txt"

echo "Done: $OUT"
echo "figure: $(ls -1 "$FIG" | wc -l)  table: $(ls -1 "$TAB" | wc -l)"
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "MISSING ${#missing[@]} publication slots (see $OUT/MANIFEST.txt)" >&2
fi

ENG_ROOT="${MEDICAL_BLOCKS_ROOT:-}"
if [[ -z "$ENG_ROOT" ]]; then
  ENG_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
fi
Rscript "$ENG_ROOT/Blocks/54_cross_lagged_full/phases/export_summary_figures.R" "$STUDY"
