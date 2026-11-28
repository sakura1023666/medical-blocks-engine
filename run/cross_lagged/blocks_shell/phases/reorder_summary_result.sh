#!/usr/bin/env bash
# 整理 summary_result：统一 Table/Figure「编号-库名」命名；删不重要中间件；重编号冲突项
set -euo pipefail
STUDY="${1:-/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747}"
OUT="$STUDY/summary_result"
TAB="$OUT/table"
FIG="$OUT/figure"
TMP="$OUT/_reorder_tmp"
rm -rf "$TMP"
mkdir -p "$TMP/table" "$TMP/figure"

cp_one() {
  local src="$1" dst="$2"
  [[ -f "$src" ]] || return 0
  mkdir -p "$(dirname "$dst")"
  cp -a "$src" "$dst"
}

# ── TABLES（主文 + 补充，按听力风格）────────────────────────────────────────
# 优先 summary 暂存表；缺则直接从 phase1_*_allages 拉（文件名常无 -DB）
_phase1_tab() { echo "$STUDY/phase1_${1}_allages/Tables"; }

# Table 1 / 2
for db in CHARLS ELSA HRS; do
  if [[ -f "$TAB/Table 1-${db}. Baseline characteristics of Hip fracture.xlsx" ]]; then
    cp_one "$TAB/Table 1-${db}. Baseline characteristics of Hip fracture.xlsx" \
           "$TMP/table/Table 1-${db}. Baseline characteristics of Hip fracture.xlsx"
  else
    cp_one "$(_phase1_tab "$db")/Table 1. Baseline characteristics of Hip fracture.xlsx" \
           "$TMP/table/Table 1-${db}. Baseline characteristics of Hip fracture.xlsx"
  fi
done
for db in CHARLS ELSA HRS Pooled; do
  # 主表 Table 2 = tertile（锁定 Age+Alcohol；ELSA 四分位分离）
  if [[ -f "$TAB/Table 2-${db}. Logistic regression analysis of Frailty Index and Hip fracture - tertile (GLM).xlsx" ]]; then
    cp_one "$TAB/Table 2-${db}. Logistic regression analysis of Frailty Index and Hip fracture - tertile (GLM).xlsx" \
           "$TMP/table/Table 2-${db}. Logistic regression analysis of Frailty Index and Hip fracture - tertile (GLM).xlsx"
  elif [[ -f "$TAB/Table 2-${db}. Logistic regression analysis of FI and Hip fracture - tertile (GLM).xlsx" ]]; then
    cp_one "$TAB/Table 2-${db}. Logistic regression analysis of FI and Hip fracture - tertile (GLM).xlsx" \
           "$TMP/table/Table 2-${db}. Logistic regression analysis of Frailty Index and Hip fracture - tertile (GLM).xlsx"
  else
    # fallback：从 S* tertile 找
    for f in "$TAB"/Table\ S*-${db}.\ Logistic\ regression\ analysis\ of\ *\ and\ Hip\ fracture\ -\ tertile\ \(GLM\)*.xlsx; do
      [[ -f "$f" ]] || continue
      cp_one "$f" "$TMP/table/Table 2-${db}. Logistic regression analysis of Frailty Index and Hip fracture - tertile (GLM).xlsx"
      break
    done
  fi
done

# S1–S4 筛选链（单库）
for db in CHARLS ELSA HRS; do
  p1="$(_phase1_tab "$db")"
  if [[ -f "$TAB/Table S1-${db}. Baseline characteristics of patients before and after multiple imputation.xlsx" ]]; then
    cp_one "$TAB/Table S1-${db}. Baseline characteristics of patients before and after multiple imputation.xlsx" \
           "$TMP/table/Table S1-${db}. Baseline characteristics of patients before and after multiple imputation.xlsx"
  else
    cp_one "$p1/Table S1. Baseline characteristics of patients before and after multiple imputation.xlsx" \
           "$TMP/table/Table S1-${db}. Baseline characteristics of patients before and after multiple imputation.xlsx"
  fi
  # normality 文件名含 n=
  hit_n=""
  for f in "$TAB"/Table\ S2-${db}.\ Normality*.xlsx; do
    [[ -f "$f" ]] || continue
    hit_n="$f"; break
  done
  if [[ -n "${hit_n:-}" ]]; then
    cp_one "$hit_n" "$TMP/table/$(basename "$hit_n")"
  else
    for f in "$p1"/Table\ S2.\ Normality*.xlsx; do
      [[ -f "$f" ]] || continue
      base=$(basename "$f")
      cp_one "$f" "$TMP/table/Table S2-${db}. ${base#Table S2. }"
      break
    done
  fi
  if [[ -f "$TAB/Table S3-${db}. Univariate Regression Analysis.xlsx" ]]; then
    cp_one "$TAB/Table S3-${db}. Univariate Regression Analysis.xlsx" \
           "$TMP/table/Table S3-${db}. Univariate Regression Analysis.xlsx"
  else
    cp_one "$p1/Table S3. Univariate Regression Analysis.xlsx" \
           "$TMP/table/Table S3-${db}. Univariate Regression Analysis.xlsx"
  fi
  if [[ -f "$TAB/Table S4-${db}. Multicollinearity Analysis (VIF, univariate p 0.1 screen).xlsx" ]]; then
    cp_one "$TAB/Table S4-${db}. Multicollinearity Analysis (VIF, univariate p 0.1 screen).xlsx" \
           "$TMP/table/Table S4-${db}. Multicollinearity Analysis (VIF, univariate p 0.1 screen).xlsx"
  else
    cp_one "$p1/Table S4. Multicollinearity Analysis (VIF, univariate p 0.1 screen).xlsx" \
           "$TMP/table/Table S4-${db}. Multicollinearity Analysis (VIF, univariate p 0.1 screen).xlsx"
  fi
done

# Table S-XX = RCS cutoff groups（四库均需：CHARLS/ELSA/HRS/Pooled；协变量=锁定 Age+Alcohol）
for db in CHARLS ELSA HRS Pooled; do
  hit=""
  for f in \
    "$TAB/Table S-XX-${db}. Logistic regression analysis of Frailty Index and Hip fracture - quartile (GLM, RCS cutoff groups).xlsx" \
    "$TAB/Table S-XX-${db}. Logistic regression analysis of FI and Hip fracture - quartile (GLM, RCS cutoff groups).xlsx"
  do
    [[ -f "$f" ]] || continue
    hit="$f"; break
  done
  if [[ -n "$hit" ]]; then
    cp_one "$hit" "$TMP/table/Table S-XX-${db}. Logistic regression analysis of Frailty Index and Hip fracture - quartile (GLM, RCS cutoff groups).xlsx"
  fi
done

# S5 change：自动设计（2年 two_wave / ≥3 年 three_plus）
if [[ -f "$TAB/Table S5. Change analysis Mean FI and FI change.xlsx" ]]; then
  cp_one "$TAB/Table S5. Change analysis Mean FI and FI change.xlsx" \
         "$TMP/table/Table S5. Change analysis Mean FI and FI change.xlsx"
elif [[ -f "$STUDY/phase3_long_Pooled/Tables/Table S5. Change analysis Mean FI and FI change.xlsx" ]]; then
  cp_one "$STUDY/phase3_long_Pooled/Tables/Table S5. Change analysis Mean FI and FI change.xlsx" \
         "$TMP/table/Table S5. Change analysis Mean FI and FI change.xlsx"
fi
# S5.1：Change analysis（内部仍可用 two_wave 设计，出版名不含 two-wave）
if [[ -f "$TAB/Table S5.1. Change analysis Mean FI and FI change.xlsx" ]]; then
  cp_one "$TAB/Table S5.1. Change analysis Mean FI and FI change.xlsx" \
         "$TMP/table/Table S5.1. Change analysis Mean FI and FI change.xlsx"
elif [[ -f "$TAB/Table S5.1. Change analysis Mean FI and FI change (two-wave).xlsx" ]]; then
  cp_one "$TAB/Table S5.1. Change analysis Mean FI and FI change (two-wave).xlsx" \
         "$TMP/table/Table S5.1. Change analysis Mean FI and FI change.xlsx"
elif [[ -f "$STUDY/phase3_long_Pooled/Tables/Table S5.1. Change analysis Mean FI and FI change.xlsx" ]]; then
  cp_one "$STUDY/phase3_long_Pooled/Tables/Table S5.1. Change analysis Mean FI and FI change.xlsx" \
         "$TMP/table/Table S5.1. Change analysis Mean FI and FI change.xlsx"
elif [[ -f "$STUDY/phase3_long_Pooled/Tables/Table S5.1. Change analysis Mean FI and FI change (two-wave).xlsx" ]]; then
  cp_one "$STUDY/phase3_long_Pooled/Tables/Table S5.1. Change analysis Mean FI and FI change (two-wave).xlsx" \
         "$TMP/table/Table S5.1. Change analysis Mean FI and FI change.xlsx"
fi
rm -f "$TMP/table"/Table\ S7-*.\ Change\ analysis*.xlsx 2>/dev/null || true

# S6 correlation（合并版优先；保留分库副本备查）
if [[ -f "$TAB/Table S6. Correlation regression FI Depression Hip fracture.xlsx" ]]; then
  cp_one "$TAB/Table S6. Correlation regression FI Depression Hip fracture.xlsx" \
         "$TMP/table/Table S6. Correlation regression FI Depression Hip fracture.xlsx"
elif [[ -f "$STUDY/phase3_long_Pooled/Tables/Table S6. Correlation regression FI Depression Hip fracture.xlsx" ]]; then
  cp_one "$STUDY/phase3_long_Pooled/Tables/Table S6. Correlation regression FI Depression Hip fracture.xlsx" \
         "$TMP/table/Table S6. Correlation regression FI Depression Hip fracture.xlsx"
fi
for db in CHARLS ELSA HRS Pooled; do
  if [[ -f "$TAB/Table S6-${db}. Table3_Correlation_Regression_FI_Depression_Hip.xlsx" ]]; then
    cp_one "$TAB/Table S6-${db}. Table3_Correlation_Regression_FI_Depression_Hip.xlsx" \
           "$TMP/table/Table S6-${db}. Correlation regression FI Depression Hip.xlsx"
  elif [[ -f "$TAB/Table S8-${db}. Table3_Correlation_Regression_FI_Depression_Hip.xlsx" ]]; then
    cp_one "$TAB/Table S8-${db}. Table3_Correlation_Regression_FI_Depression_Hip.xlsx" \
           "$TMP/table/Table S6-${db}. Correlation regression FI Depression Hip.xlsx"
  elif [[ -f "$TAB/Table S8-${db}. Correlation regression FI Depression Hip.xlsx" ]]; then
    cp_one "$TAB/Table S8-${db}. Correlation regression FI Depression Hip.xlsx" \
           "$TMP/table/Table S6-${db}. Correlation regression FI Depression Hip.xlsx"
  fi
done
# 清旧 S8 corr 命名
rm -f "$TMP/table"/Table\ S8-*.\ Correlation\ regression*.xlsx 2>/dev/null || true

# S7 mediation（仅合并版；分库 Table S7-* 不进 summary）
if [[ -f "$TAB/Table S7. Longitudinal mediation Frailty Index→Depression→Hip fracture.xlsx" ]]; then
  cp_one "$TAB/Table S7. Longitudinal mediation Frailty Index→Depression→Hip fracture.xlsx" \
         "$TMP/table/Table S7. Longitudinal mediation Frailty Index→Depression→Hip fracture.xlsx"
elif [[ -f "$STUDY/phase3_long_Pooled/Tables/Table S7. Longitudinal mediation Frailty Index→Depression→Hip fracture.xlsx" ]]; then
  cp_one "$STUDY/phase3_long_Pooled/Tables/Table S7. Longitudinal mediation Frailty Index→Depression→Hip fracture.xlsx" \
         "$TMP/table/Table S7. Longitudinal mediation Frailty Index→Depression→Hip fracture.xlsx"
fi
# 明确丢弃分库 S7 / 旧 S6 mediation 命名
rm -f "$TMP/table"/Table\ S7-*.\ Longitudinal\ mediation*.xlsx 2>/dev/null || true
rm -f "$TMP/table"/Table\ S6-*.\ Longitudinal\ mediation*.xlsx 2>/dev/null || true
rm -f "$TAB"/Table\ S7-*.\ Longitudinal\ mediation*.xlsx 2>/dev/null || true

# （旧）分库 change 原始表仅作中间件，不进正式 S 编号
# Flowchart attrition：保留 phase 中间件，不进 summary 正式 S 编号
rm -f "$TMP/table"/Table\ S9-*.\ Flowchart\ attrition*.csv 2>/dev/null || true
rm -f "$TAB"/Table\ S9-*.\ Flowchart\ attrition*.csv 2>/dev/null || true

# S8 CLPN adjacency（真名行列；原 S10）
# 交叉滞后 CLPN：仅三库（不用 Pooled）
for db in CHARLS ELSA HRS; do
  if [[ -f "$STUDY/phase3_long_${db}/Tables/Table S8-${db}. CLPN adjacency.csv" ]]; then
    cp_one "$STUDY/phase3_long_${db}/Tables/Table S8-${db}. CLPN adjacency.csv" \
           "$TMP/table/Table S8-${db}. CLPN adjacency.csv"
  elif [[ -f "$STUDY/phase3_long_${db}/Tables/CLPN_adjacency.csv" ]]; then
    cp_one "$STUDY/phase3_long_${db}/Tables/CLPN_adjacency.csv" \
           "$TMP/table/Table S8-${db}. CLPN adjacency.csv"
  elif [[ -f "$TAB/Table S8-${db}. CLPN adjacency.csv" ]]; then
    cp_one "$TAB/Table S8-${db}. CLPN adjacency.csv" \
           "$TMP/table/Table S8-${db}. CLPN adjacency.csv"
  fi
done
rm -f "$TMP/table"/Table\ S8-Pooled*.csv 2>/dev/null || true
rm -f "$TAB"/Table\ S8-Pooled*.csv 2>/dev/null || true
rm -f "$TMP/table"/Table\ S10-*.\ CLPN\ adjacency.csv 2>/dev/null || true
rm -f "$TAB"/Table\ S10-*.\ CLPN\ adjacency.csv 2>/dev/null || true
rm -f "$TAB"/Table\ S9-*.\ CLPN\ adjacency.csv 2>/dev/null || true

# S9–S17.1 敏感性（仅收文件名含 Sensitivity 的正式表；拒收 Normality 等杂表）
# S9/S10/S12/S13/S15/S16 分库；S11/S11.1/S14/S14.1/S17/S17.1 合并 Change
_is_sens_table() {
  local b="$1"
  [[ "$b" == *Sensitivity* ]] || return 1
  case "$b" in
    Table\ S9-*|Table\ S10-*|Table\ S11*|Table\ S12-*|Table\ S13-*|Table\ S14*|Table\ S15-*|Table\ S16-*|Table\ S17*)
      return 0 ;;
    *) return 1 ;;
  esac
}
for f in \
  "$TAB"/Table\ S9-*.xlsx \
  "$TAB"/Table\ S10-*.xlsx \
  "$TAB"/Table\ S11*.xlsx \
  "$TAB"/Table\ S12-*.xlsx \
  "$TAB"/Table\ S13-*.xlsx \
  "$TAB"/Table\ S14*.xlsx \
  "$TAB"/Table\ S15-*.xlsx \
  "$TAB"/Table\ S16-*.xlsx \
  "$TAB"/Table\ S17*.xlsx
do
  [[ -f "$f" ]] || continue
  base=$(basename "$f")
  _is_sens_table "$base" || continue
  cp_one "$f" "$TMP/table/$base"
done
if [[ -d "$STUDY/sensitivity" ]]; then
  find "$STUDY/sensitivity" -type f -name 'Table S*.xlsx' -print0 2>/dev/null | while IFS= read -r -d '' f; do
    base=$(basename "$f")
    _is_sens_table "$base" || continue
    cp_one "$f" "$TMP/table/$base"
  done
fi
# ── FIGURES ──────────────────────────────────────────────────────────────────
# Fig1 flowchart
for db in CHARLS ELSA HRS Pooled; do
  cp_one "$FIG/Figure 1-${db}. Longitudinal inclusion exclusion flowchart.pdf" \
         "$TMP/figure/Figure 1-${db}. Longitudinal inclusion exclusion flowchart.pdf"
done

# Fig2 RCS（Pooled 在 phase3_post 常为 Figure 4，统一成 Figure 2-Pooled）
for db in CHARLS ELSA HRS; do
  found=""
  for cand in \
    "$FIG/Figure 2-${db}. RCS plot between FI and Hip Fracture.pdf" \
    "$FIG/Figure 2-${db}. RCS plot between Frailty Index and Hip Fracture.pdf" \
    "$STUDY/phase1_${db}_allages/Figures/Figure 2-${db}. RCS plot between Frailty Index and Hip Fracture.pdf" \
    "$STUDY/phase1_${db}_allages/Figures/Figure 2-${db}. RCS plot between FI and Hip Fracture.pdf" \
    "$FIG/Figure 2. RCS plot between Frailty Index and Hip Fracture-${db}.pdf" \
    "$STUDY/phase1_${db}_allages/Figures/Figure 2. RCS plot between Frailty Index and Hip Fracture.pdf"
  do
    if [[ -f "$cand" ]]; then found="$cand"; break; fi
  done
  if [[ -n "$found" ]]; then
    cp_one "$found" "$TMP/figure/Figure 2-${db}. RCS plot between Frailty Index and Hip Fracture.pdf"
  fi
done
# 多路候选 Pooled RCS
for cand in \
  "$FIG/Figure 2-Pooled. RCS plot between FI and Hip Fracture.pdf" \
  "$FIG/Figure 2-Pooled. RCS plot between Frailty Index and Hip Fracture.pdf" \
  "$FIG/Figure 4-Pooled. RCS plot between FI and Hip Fracture.pdf" \
  "$FIG/Figure 4-Pooled. RCS plot between Frailty Index and Hip Fracture.pdf" \
  "$STUDY/phase3_post_Pooled/Figures/Figure 4-Pooled. RCS plot between Frailty Index and Hip Fracture.pdf" \
  "$STUDY/phase3_post_Pooled/Figures/Figure 4-Pooled. RCS plot between FI and Hip Fracture.pdf" \
  "$STUDY/phase3_post_Pooled/Figures/Figure 3-Pooled. RCS plot between Frailty Index and Hip Fracture.pdf" \
  "$STUDY/phase3_post_Pooled/step04_rcs_incidence/Figures/Figure 4-Pooled. RCS plot between FI and Hip Fracture.pdf"
do
  if [[ -f "$cand" ]]; then
    cp_one "$cand" "$TMP/figure/Figure 2-Pooled. RCS plot between Frailty Index and Hip Fracture.pdf"
    break
  fi
done
if [[ -f "$TMP/figure/Figure 2-Pooled. RCS plot between Frailty Index and Hip Fracture.pdf" ]]; then
  cp -a "$TMP/figure/Figure 2-Pooled. RCS plot between Frailty Index and Hip Fracture.pdf" \
        "$FIG/Figure 2-Pooled. RCS plot between Frailty Index and Hip Fracture.pdf" 2>/dev/null || true
fi

# Fig3 subgroup：仅三单库（不要 Pooled）
for db in CHARLS ELSA HRS; do
  if [[ -f "$FIG/Figure 3-${db}. Subgroup Forest analyses of FI.pdf" ]]; then
    cp_one "$FIG/Figure 3-${db}. Subgroup Forest analyses of FI.pdf" \
           "$TMP/figure/Figure 3-${db}. Subgroup Forest analyses of FI.pdf"
  else
    for cand in \
      "$FIG/Figure 3. Subgroup Forest analyses of FI-${db}.pdf" \
      "$STUDY/phase1_${db}_allages/Figures/Figure 3. Subgroup Forest analyses of FI.pdf" \
      "$STUDY/phase1_${db}_allages/Figures/Figure 2. Subgroup Forest analyses of FI.pdf"
    do
      if [[ -f "$cand" ]]; then
        cp_one "$cand" "$TMP/figure/Figure 3-${db}. Subgroup Forest analyses of FI.pdf"
        break
      fi
    done
  fi
done
# 明确不收录 Pooled 亚组森林图
rm -f "$TMP/figure/Figure 3-Pooled. Subgroup Forest analyses of FI.pdf" \
      "$FIG/Figure 3-Pooled. Subgroup Forest analyses of FI.pdf" 2>/dev/null || true

# S1 CLPN edge-weight bootstrap（文献网络稳定性；取代旧 ROC 占用的 S1 号）
# S2 CLPN case-dropping stability（取代已废弃的 FI 箱线 S2）
for db in CHARLS ELSA HRS; do
  found_s1=""
  for cand in \
    "$FIG/Figure S1-${db}. CLPN edge weight bootstrap.pdf" \
    "$STUDY/phase3_long_${db}/Figures/Figure S1-${db}. CLPN edge weight bootstrap.pdf" \
    "$STUDY/summary_result/figure/Figure S1-${db}. CLPN edge weight bootstrap.pdf"
  do
    if [[ -f "$cand" ]]; then found_s1="$cand"; break; fi
  done
  if [[ -n "$found_s1" ]]; then
    cp_one "$found_s1" "$TMP/figure/Figure S1-${db}. CLPN edge weight bootstrap.pdf"
  fi

  found_s2=""
  for cand in \
    "$FIG/Figure S2-${db}. CLPN case-dropping stability.pdf" \
    "$STUDY/phase3_long_${db}/Figures/Figure S2-${db}. CLPN case-dropping stability.pdf" \
    "$STUDY/summary_result/figure/Figure S2-${db}. CLPN case-dropping stability.pdf"
  do
    if [[ -f "$cand" ]]; then found_s2="$cand"; break; fi
  done
  if [[ -n "$found_s2" ]]; then
    cp_one "$found_s2" "$TMP/figure/Figure S2-${db}. CLPN case-dropping stability.pdf"
  fi
done
# 旧 ROC / FI 箱线不再占 S1/S2
rm -f "$TMP"/figure/Figure\ S1-*.ROC* 2>/dev/null || true
rm -f "$TMP"/figure/Figure\ S2-*.Boxplot* 2>/dev/null || true
rm -f "$FIG"/Figure\ S2-*.Boxplot* 2>/dev/null || true

# S3 Mediation（覆盖原先与 Age 箱线冲突的 S3）
for db in CHARLS ELSA HRS Pooled; do
  cp_one "$FIG/Figure S3-${db}. Longitudinal mediation path diagram of FI and hip fracture.pdf" \
         "$TMP/figure/Figure S3-${db}. Longitudinal mediation path diagram of FI and hip fracture.pdf"
done

# S4 年×结局柱 / S5 国×结局柱 / Fig4 CLPN（文献式命名）
# S4 = 纵向 incidence 分析样本上 ever 入射分组，各调查年均值±SE（唯一的疾病组 FI 描述图）
for db in CHARLS ELSA HRS; do
  if [[ -f "$FIG/Figure S4-${db}. Mean FI by Year and Disease.pdf" ]]; then
    cp_one "$FIG/Figure S4-${db}. Mean FI by Year and Disease.pdf" \
           "$TMP/figure/Figure S4-${db}. Mean FI by Year and Disease.pdf"
  elif [[ -f "$STUDY/phase3_long_${db}/Figures/FigS4_Mean_FI_by_Year_Disease.pdf" ]]; then
    cp_one "$STUDY/phase3_long_${db}/Figures/FigS4_Mean_FI_by_Year_Disease.pdf" \
           "$TMP/figure/Figure S4-${db}. Mean FI by Year and Disease.pdf"
  fi
done

# Figure S5: 国×结局 FI 均值柱
if [[ -f "$FIG/Figure S5. Mean FI by Country and Disease.pdf" ]]; then
  cp_one "$FIG/Figure S5. Mean FI by Country and Disease.pdf" \
         "$TMP/figure/Figure S5. Mean FI by Country and Disease.pdf"
elif [[ -f "$STUDY/phase3_long_Pooled/Figures/FigS5_Mean_FI_by_Country_Disease.pdf" ]]; then
  cp_one "$STUDY/phase3_long_Pooled/Figures/FigS5_Mean_FI_by_Country_Disease.pdf" \
         "$TMP/figure/Figure S5. Mean FI by Country and Disease.pdf"
fi

# Figure 4: CLPN 网络（主文；非 RCS）
for db in CHARLS ELSA HRS; do
  if [[ -f "$FIG/Figure 4-${db}. CLPN network of frailty index items.pdf" ]]; then
    cp_one "$FIG/Figure 4-${db}. CLPN network of frailty index items.pdf" \
           "$TMP/figure/Figure 4-${db}. CLPN network of frailty index items.pdf"
  elif [[ -f "$STUDY/phase3_long_${db}/Figures/Fig4_CLPN_network_pub.pdf" ]]; then
    cp_one "$STUDY/phase3_long_${db}/Figures/Fig4_CLPN_network_pub.pdf" \
           "$TMP/figure/Figure 4-${db}. CLPN network of frailty index items.pdf"
  elif [[ -f "$STUDY/phase3_long_${db}/Figures/Fig_CLPN_network.pdf" ]]; then
    cp_one "$STUDY/phase3_long_${db}/Figures/Fig_CLPN_network.pdf" \
           "$TMP/figure/Figure 4-${db}. CLPN network of frailty index items.pdf"
  fi
done

# ROC 改挂 S11（不再占 S1）
for db in CHARLS ELSA HRS; do
  for cand in \
    "$FIG/Figure S1-${db}. ROC FI.pdf" \
    "$STUDY/phase1_${db}_allages/Figures/Figure S1-${db}. ROC Frailty Index.pdf" \
    "$STUDY/phase1_${db}_allages/Figures/Figure S1. ROC Frailty Index.pdf"
  do
    if [[ -f "$cand" ]]; then
      cp_one "$cand" "$TMP/figure/Figure S11-${db}. ROC FI.pdf"
      break
    fi
  done
done
if [[ -f "$FIG/Figure S5-Pooled. ROC FI.pdf" ]]; then
  cp_one "$FIG/Figure S5-Pooled. ROC FI.pdf" \
         "$TMP/figure/Figure S11-Pooled. ROC FI.pdf"
elif [[ -f "$STUDY/phase3_post_Pooled/Figures/Figure S5. ROC Frailty Index.pdf" ]]; then
  cp_one "$STUDY/phase3_post_Pooled/Figures/Figure S5. ROC Frailty Index.pdf" \
         "$TMP/figure/Figure S11-Pooled. ROC FI.pdf"
fi

# 箱线改编号，避免与 S4/S5 文献图抢号
for db in CHARLS ELSA HRS; do
  cp_one "$FIG/Figure S3-${db}. Boxplot Age by Disease Group.pdf" \
         "$TMP/figure/Figure S4b-${db}. Boxplot Age by Disease Group.pdf"
  cp_one "$FIG/Figure S4-${db}. Boxplot BMI by Disease Group.pdf" \
         "$TMP/figure/Figure S5b-${db}. Boxplot BMI by Disease Group.pdf"
done
cp_one "$FIG/Figure S7-Pooled. Boxplot Age by Disease Group.pdf" \
       "$TMP/figure/Figure S4b-Pooled. Boxplot Age by Disease Group.pdf"
cp_one "$FIG/Figure S8-Pooled. Boxplot BMI by Disease Group.pdf" \
       "$TMP/figure/Figure S5b-Pooled. Boxplot BMI by Disease Group.pdf"

# S6 Mean FI by year（原 L1 线型备档；正式 S4 为柱状版）
for db in CHARLS ELSA HRS Pooled; do
  cp_one "$FIG/Figure L1-${db}. Mean FI by Year and Disease.pdf" \
         "$TMP/figure/Figure S6-${db}. Mean FI by Year and Disease (line).pdf"
done

# S7 Country-Year 旧半小提琴备档
for db in CHARLS ELSA HRS Pooled; do
  cp_one "$FIG/Figure L2-${db}. FI by Country Year.pdf" \
         "$TMP/figure/Figure S7-${db}. FI by Country Year (legacy).pdf"
done

# 旧 L3 CLPN 若无 Figure 4 已收录则作备档
for db in CHARLS ELSA HRS; do
  if [[ ! -f "$TMP/figure/Figure 4-${db}. CLPN network of frailty index items.pdf" ]]; then
    cp_one "$FIG/Figure L3-${db}. CLPN network.pdf" \
           "$TMP/figure/Figure 4-${db}. CLPN network of frailty index items.pdf"
  fi
done

# S9 纵向二分森林（原 L4；与 Fig3 发病亚组不同）
for db in CHARLS ELSA HRS; do
  cp_one "$FIG/Figure L4-${db}. Subgroup Forest FI binary.pdf" \
         "$TMP/figure/Figure S9-${db}. Subgroup Forest FI binary.pdf"
done

# S10 Missing
for db in CHARLS ELSA HRS; do
  cp_one "$FIG/Figure Missing Value Overview-${db}.pdf" \
         "$TMP/figure/Figure S10-${db}. Missing Value Overview.pdf"
done

# 替换
rm -rf "$TAB" "$FIG"
mv "$TMP/table" "$TAB"
mv "$TMP/figure" "$FIG"
rmdir "$TMP" 2>/dev/null || rm -rf "$TMP"

{
  echo "summary_result — Hip fracture × Frailty (cross-lagged PMID 40595747)"
  echo "generated: $(date -Iseconds)"
  echo "naming: Table/Figure <num>-<DB>. <title>"
  echo "tables: T1 baseline | T2 logistic tertile ONLY | S1–S4 screen | S-XX RCS | S5 change(auto) | S5.1 change(all two_wave) | S6 corr(M1≠M2) | S7 mediation(merged) | S8 CLPN labeled | S9–S17.1 sensitivity"
  echo "figures: Fig1 flowchart | Fig2 RCS | Fig3 subgroup | Fig4 CLPN | S1 edge-boot | S2 case-drop | S3 mediation | S4–S5 FI desc | S6–S9 long panels | S10 missing | S11 ROC"
  echo "sensitivity: S9–S11.1 exclude chronic>=2; S12–S14.1 complete-case unimputed listwise (N may be <AfterMI); S15–S17.1 exclude event<=2y; competing_risk skipped"
  echo "excluded from summary: binary/quartile/quintile logistic GLM (not RCS S-XX); per-DB Youden/quintile change raw; baseline FI boxplot"
  echo "Table S5: auto design (2y=two_wave; ≥3y=three_plus). Table S5.1: force two_wave all cohorts"
  echo
  echo "=== figure ==="; ls -1 "$FIG" | sort
  echo; echo "=== table ==="; ls -1 "$TAB" | sort
} > "$OUT/MANIFEST.txt"

echo "Done."
echo "figure: $(ls -1 "$FIG" | wc -l)  table: $(ls -1 "$TAB" | wc -l)"
ls -1 "$FIG" | sort
echo "----"
ls -1 "$TAB" | sort
