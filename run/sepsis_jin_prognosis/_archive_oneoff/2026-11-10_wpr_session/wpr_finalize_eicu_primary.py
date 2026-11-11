#!/usr/bin/env python3
"""Prune WPR summary_results to Jin eICU-primary delivery set; refresh image_information."""
from __future__ import annotations

import shutil
from pathlib import Path

SR = Path("/mnt/g/02block_result/36_spesis/prediction_41194138/by_index/【success】WPR/summary_results")
WS = SR.parent / "summary_results_delivery_workspace"
TABLES = SR / "Tables"
PDF = SR / "Figures" / "pdf"
INFO = SR / "Figures" / "image_information"

KEEP_TABLES = {
    "Table 1-MIMIC. Baseline characteristics by WPR quartile.xlsx",
    "Table 1-eICU. Baseline characteristics by WPR quartile.xlsx",
    "Table 2-MIMIC. Cox proportional hazard models for in-hospital, 30-day, and 365-day all-cause mortality.xlsx",
    "Table 2-eICU. Cox proportional hazard models for in-hospital, 30-day, and 365-day all-cause mortality.xlsx",
    "Table S1-MIMIC. Subgroup analyses of cox proportional hazard models for in-hospital mortality.xlsx",
    "Table S1-eICU. Subgroup analyses of cox proportional hazard models for in-hospital mortality.xlsx",
    "Table S2-MIMIC. Subgroup analyses of cox proportional hazard models for 30-day mortality.xlsx",
    "Table S2-eICU. Subgroup analyses of cox proportional hazard models for 30-day mortality.xlsx",
    "Table S3-MIMIC. Subgroup analyses of cox proportional hazard models for 365-day mortality.xlsx",
    "Table S3-eICU. Subgroup analyses of cox proportional hazard models for 365-day mortality.xlsx",
}

KEEP_PDF = {
    "Figure 1. RCS of WPR by SOFA and mortality horizon in Sepsis.pdf",
    "Figure 2. Nomogram for in-hospital, 30-day and 365-day mortality.pdf",
    "Figure 3. SHAP summary and dependence for in-hospital, 30-day and 365-day mortality.pdf",
    "Figure 4. Mediation analysis of WPR via AnionGap.pdf",
    "Figure S1. Inclusion exclusion flowchart.pdf",
    "Figure S2. Kaplan-Meier curves of WPR Index SOFA Q and multi-horizon mortality.pdf",
    "Figure S3. Calibration bootstrap in-hospital mortality.pdf",
}

MD_SNIPS = {
    "Figure 1. RCS of WPR by SOFA and mortality horizon in Sepsis": (
        "## 图面说明\n\n"
        "双库拼图：上 **A. eICU**（主库）、下 **B. MIMIC**。每库为 SOFA×院内/30天/365天 RCS（2×3）。\n\n"
        "## 分析上下文\n\n"
        "暴露：WPR。结局：院内/30天/365天全因死亡。主库：eICU；次库：MIMIC。\n"
    ),
    "Figure 2. Nomogram for in-hospital, 30-day and 365-day mortality": (
        "## 图面说明\n\n"
        "双库 2×3 诺模图：上 **eICU**、下 **MIMIC**；列 A/B/C = 院内/30天/365天。"
        "特征（双库锁定）：WPR, SOFA, Age, RDW, Creatinine, Temperature, Weight, APSIII。\n\n"
        "## 分析上下文\n\n"
        "暴露：WPR。主库：eICU。特征与 Figure 3 SHAP 同源。\n"
    ),
    "Figure 3. SHAP summary and dependence for in-hospital, 30-day and 365-day mortality": (
        "## 图面说明\n\n"
        "双库拼图：上 **eICU**、下 **MIMIC**。A–C beeswarm，D–F 为 WPR 依赖图（按 SOFA 着色）。"
        "特征同 Figure 2（含 APSIII，无 Chloride）。xgboost+shapviz，n=200/时点。\n\n"
        "## 分析上下文\n\n"
        "解释对象：与诺模图相同的 8 特征逻辑回归模型（非无约束 best model）。主库：eICU。\n"
    ),
    "Figure 4. Mediation analysis of WPR via AnionGap": (
        "## 图面说明\n\n"
        "双库拼图：上 **A. eICU**、下 **B. MIMIC**。每库含概念路径图（WPR→AnionGap→Mortality）"
        "及院内/30天/365天间接(a×b)与直接(c′) Bootstrap 分布（B=1000）。\n\n"
        "## 分析上下文\n\n"
        "中介：AnionGap（双库 LM 重筛后锁定）。协变量：Age, Temperature。主库：eICU。\n"
    ),
    "Figure S1. Inclusion exclusion flowchart": (
        "## 图面说明\n\n"
        "单页双库纳排：上 **A. eICU**、下 **B. MIMIC**。提取→排除→分析队列；左四分位、右 WPR×SOFA 四组。\n\n"
        "## 分析上下文\n\n"
        "样本量：eICU N=13,635；MIMIC N=8,218。主库：eICU。\n"
    ),
    "Figure S2. Kaplan-Meier curves of WPR Index SOFA Q and multi-horizon mortality": (
        "## 图面说明\n\n"
        "单页双库 KM：上 **A. eICU**、下 **B. MIMIC**；每行三列院内/30天/365天 + Number at risk。\n\n"
        "## 分析上下文\n\n"
        "暴露：WPR×SOFA 四组。主库：eICU。\n"
    ),
    "Figure S3. Calibration bootstrap in-hospital mortality": (
        "## 图面说明\n\n"
        "双库拼图：上 **A. eICU**、下 **B. MIMIC**。诺模图院内死亡 bootstrap 校准（B=1000）。\n\n"
        "## 分析上下文\n\n"
        "与 Figure 2 同源 8 特征。主库：eICU。\n"
    ),
}

METHODS = """# Statistical analysis

## Study design and cohort

This was a dual-database prognostic study of adults with sepsis. For the WPR index delivery, **eICU was the primary (development) database** and MIMIC-IV was the secondary (external) database; dual-panel figures place eICU above (panel A) and MIMIC below (panel B). Analytic samples follow the inclusion–exclusion flowchart (Figure S1). The exposure was the composite index WPR (white blood cell count / platelet count). Mortality endpoints were in-hospital death (`fustatus`) and landmark deaths at 30 and 365 days.

## Missing data

Missing covariates were handled with multiple imputation by chained equations (MICE; m = 5). Inferential Cox estimates in association tables were pooled with Rubin's rules. Operational steps (Table 1, nomogram fitting, SHAP, KM/RCS plots, mediation path diagrams) used the first completed dataset.

## Covariate selection (Model II)

Shared clinical candidates available in both databases were screened with univariate Cox models for in-hospital death (P < 0.05 in each database). The dual-database intersection, plus forced Age and Gender, formed the full UV∩ set. Table 2 and Tables S1–S3 Model II used a compact clinical core of that intersection: Age, Gender, APSIII, BUN, OASIS, Temperature, AnionGap, Charlson, SpO2, MAP, Creatinine, RDW, and Ventilation. Model I was unadjusted. SOFA was dichotomized at 5 for stratum/combined exposures and was not entered as a Model II covariate.

## Association analyses

Associations of WPR with mortality used Cox models across in-hospital, 30-day, and 365-day horizons (Table 2): WPR quartiles, SOFA Low/High, and combined Index×SOFA strata. Restricted cubic splines described WPR–mortality relationships stratified by SOFA (Figure 1). Subgroup analyses of Index_SOFA_Q strata are reported in Tables S1–S3. Estimates were pooled across m = 5 imputations by Rubin's rules.

## Nomogram and SHAP (Figures 2–3)

A multivariable logistic nomogram was built for in-hospital, 30-day, and 365-day mortality (Figure 2). Features were re-locked from the fresh UV∩ Model II clinical pool (Chloride removed; APSIII added): WPR, SOFA, Age, RDW, Creatinine, Temperature, Weight, and APSIII (`selection = none` so both databases and all three horizons used the same eight predictors). Figure 2 is a dual-panel 2×3 layout (eICU above, MIMIC below; columns A/B/C = three horizons).

SHAP summaries and WPR dependence plots colored by SOFA (Figure 3) explained the same locked eight-feature set as Figure 2 (xgboost + shapviz; n = 200 explained observations per horizon). Calibration of the nomogram used bootstrap (B = 1000; Figure S3).

## Mediation

Mediators were re-screened by dual-database LM association (laboratory pool; Model1 ∩ Model2, P < 0.05 in both databases). The locked significant intersection included RBC, Neutrophil_Count, Lymphocytes, RDW, BUN, Creatinine, Chloride, and AnionGap; the dual-database path diagram aligned on **AnionGap** as the best shared mediator. Path diagrams (Figure 4) report effects with mediation covariates Age and Temperature. Bootstrap densitites use B = 1000.

## Software

Analyses were performed in R. Key packages included mice, survival, rms (nomogram), xgboost/shapviz (SHAP), ggplot2, and forestploter. Exact versions are listed in Methods_software_versions.txt. Publication tables use SCI three-line xlsx formatting; figure display labels omit programming underscores.
"""


def main() -> None:
    junk = WS / f"_prune_junk"
    junk.mkdir(parents=True, exist_ok=True)

    # Restore Jin tables if missing
    BK = sorted(WS.glob("tables_pre_eicu_primary_*"))[-1]
    for name in KEEP_TABLES:
        dst = TABLES / name
        if not dst.exists():
            if name.startswith("Table 1"):
                src = BK / name
            elif name.startswith("Table 2"):
                src = Path("/tmp/wpr_table2_jin") / name
            else:
                src = Path("/tmp/wpr_table_s123_fmt_fresh") / name
            if src.exists():
                shutil.copy2(src, dst)

    for p in list(TABLES.glob("*.xlsx")):
        if p.name not in KEEP_TABLES:
            shutil.move(str(p), junk / p.name)

    for p in list(PDF.glob("*.pdf")):
        if p.name not in KEEP_PDF:
            shutil.move(str(p), junk / p.name)

    missing_pdf = [n for n in KEEP_PDF if not (PDF / n).exists()]
    missing_tab = [n for n in KEEP_TABLES if not (TABLES / n).exists()]

    INFO.mkdir(parents=True, exist_ok=True)
    for stem, body in MD_SNIPS.items():
        (INFO / f"{stem}.md").write_text(f"# {stem}\n\n{body}", encoding="utf-8")

    (SR / "Methods_statistical_analysis.md").write_text(METHODS, encoding="utf-8")

    # drop non-whitelist root clutter
    for p in SR.iterdir():
        if p.name in {"Figures", "Tables", "Methods_statistical_analysis.md", "Methods_software_versions.txt"}:
            continue
        if p.suffix.lower() == ".pdf" and "中期" in p.name:
            continue
        if p.is_file():
            shutil.move(str(p), junk / p.name)

    print("tables", sorted(x.name for x in TABLES.glob("*.xlsx")))
    print("pdfs", sorted(x.name for x in PDF.glob("*.pdf")))
    print("missing_pdf", missing_pdf)
    print("missing_tab", missing_tab)
    print("OK" if not missing_pdf and not missing_tab else "INCOMPLETE")


if __name__ == "__main__":
    main()
