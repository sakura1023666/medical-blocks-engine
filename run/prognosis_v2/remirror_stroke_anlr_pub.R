#!/usr/bin/env Rscript
# 卒中 ANLR prognosis_v2 双库收口：统一 Model3、补图、S7→S8→Fig6、Methods

suppressPackageStartupMessages({
  library(data.table)
  library(survival)
  library(ggplot2)
  library(grid)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.engine <- if (dir.exists("/mnt/e/01block/01Block-new-Final")) {
  "/mnt/e/01block/01Block-new-Final"
} else "E:/01block/01Block-new-Final"
setwd(.engine)
source(file.path(.engine, "run/prognosis_v2/stroke_anlr_env.R"), local = FALSE)
source(file.path(.engine, "R/utils.R"), local = FALSE)
source(file.path(.engine, "R/pv2_pub_names.R"), local = FALSE)
source(file.path(.engine, "R/quantile_scheme_cascade.R"), local = FALSE)
source(file.path(.engine, "R/pv2_literature_pub_tables.R"), local = FALSE)
source(file.path(.engine, "run/prognosis_v2/pv2_mi_cox.R"), local = FALSE)
source(file.path(.engine, "R/pub_figure_export.R"), local = FALSE)
source(file.path(.engine, "R/subgroup_forest_plot.R"), local = FALSE)

.proj <- stroke_anlr_proj()
.out <- stroke_anlr_out(.proj)
.days <- stroke_anlr_days()
.day_lab <- stroke_anlr_day_lab()
.endpoint <- stroke_anlr_endpoint_phrase()
.tab <- file.path(.out, "Tables")
.fig <- file.path(.out, "Figures", "pdf")
dir.create(.fig, recursive = TRUE, showWarnings = FALSE)

IDX <- "ANLR"
dbs <- readRDS(file.path(.tab, "imputed_dbs.rds"))
mids_list <- readRDS(file.path(.tab, "imputed_mids.rds"))
.lock <- readRDS(file.path(.tab, "quantile_scheme_resolved.rds"))
m3_by <- readRDS(file.path(.tab, "Model3_by_database.rds"))
m3_shared <- Reduce(intersect, m3_by)
message("Harmonized Model3: ", paste(m3_shared, collapse = " + "))

fmt_p <- function(p) ifelse(!is.finite(p), "", ifelse(p < 0.001, "<0.001", sprintf("%.3f", p)))
hr_cell <- function(hr, lo, hi) {
  ifelse(!is.finite(hr) | !is.finite(lo) | !is.finite(hi), "",
         sprintf("%.3f (%.3f-%.3f)", hr, lo, hi))
}

# ---- 全表按 Hip summary_results 版式重写（双库各一份）----
message("Tables via _rebuild_stroke_anlr_tables_hip_layout.R")
sys.source(
  file.path(.engine, "run/prognosis_v2/_rebuild_stroke_anlr_tables_hip_layout.R"),
  envir = new.env(parent = globalenv())
)
# refresh handles after table prune/rebuild
dbs <- readRDS(file.path(.tab, "imputed_dbs.rds"))
mids_list <- readRDS(file.path(.tab, "imputed_mids.rds"))
m3_by <- readRDS(file.path(.tab, "Model3_by_database.rds"))
m3_shared <- Reduce(intersect, m3_by)

# ---- Fig2 / Fig3：对齐 Hip（A–D 四面板；1−KM 累积发病率+风险表）；双库共享特征 ----
message("Fig2/Fig3 via _fix_stroke_anlr_fig2_fig3.R (shared feature pool)")
sys.source(
  file.path(.engine, "run/prognosis_v2/_fix_stroke_anlr_fig2_fig3.R"),
  envir = new.env(parent = globalenv())
)

# ---- Fig3 days；Fig4–7 对齐 Hip（Fig4 不加协变量；Fig5 ROC；Fig6 路径图；Fig7 森林）----
message("Fig3 via _fix_stroke_anlr_fig3_fig4.R (ends with Fig4-7 Hip redraw)")
sys.source(
  file.path(.engine, "run/prognosis_v2/_fix_stroke_anlr_fig3_fig4.R"),
  envir = new.env(parent = globalenv())
)

# ---- Methods ----
methods <- c(
  "# Statistical analysis",
  "",
  paste0("We analysed adults aged 18 years or older with ischemic stroke in MIMIC and eICU under an equal-footing dual-database design. The primary endpoint was ", .endpoint, " after ICU admission."),
  "The exposure was ANLR (albumin / [neutrophil count / lymphocyte count]) from the first available components. Indices entered models as continuous variables (per 1 SD) and as the locked grouping from an engine-level cascade (quartile → tertile → binary; pass_rule = all). The locked grouping for this study was quartile (Q4 vs Q1). Cut-points were estimated within each database; the scheme (number of levels) was shared.",
  "Covariates were restricted to columns available in both databases. Model 1 was unadjusted. Model 2 was adjusted for Age and Gender. Model 3 used a dual-DB harmonized set: Age, Gender, and variables retained after Boruta/SHAP screening and VIF within the shared pool (intersection across databases). SOFA was reserved as the mediator and was not entered in Model 3. ANLR component variables were excluded from regression covariates.",
  "Missing covariates were handled with MICE (cart, m = 5). Exposure, follow-up time and death status were not imputed. Inferential Cox models were fit on each completed dataset and pooled by Rubin's rules. Descriptive tables, figures and Boruta used the first completed dataset.",
  "Person-time and crude mortality rates were summarised by exposure group (Table 2). Kaplan–Meier curves used the locked grouping with log-rank tests. Restricted cubic splines on the per-1-SD scale were plotted without covariate adjustment (Figure 4) and reported P-linear and P-nonlinear. Discrimination used ROC curves of the Cox linear predictor and Youden indices (Table S4 / Figure 5).",
  "Subgroup analyses estimated Q4 versus Q1 contrasts on the full analytic sample after collapsing middle quartiles (unadjusted within strata), with likelihood-ratio P values for exposure×stratum interactions (Figure 7).",
  "Mediation followed the prognosis routine: Table S7 first reported associations of ANLR with shared laboratory/severity indicators; Table S8 and Figure 6 then evaluated SOFA as mediator with path models adjusted as in Table 3 Model 2 (Age, Gender). Path a was the linear coefficient of ANLR (per 1 SD) on standardized SOFA; path b and the Direct effect were Cox log-hazard coefficients. Proportion mediated used bootstrap confidence intervals. Association tables and path diagrams were co-gated.",
  "Sensitivity analysis redefined the endpoint as in-hospital all-cause mortality (Table S5) using the same Model 1–Model 3 structure and the same exposure grouping scheme. Proportional-hazards assumptions were assessed with Schoenfeld tests (Table S9).",
  "",
  "## Software",
  "",
  "Analyses were performed in R. Key packages: mice, survival, rms, Boruta, pROC, ggplot2, openxlsx, car."
)
writeLines(methods, file.path(.out, "Methods_statistical_analysis.md"))
writeLines(c(
  paste0("R version: ", R.version.string),
  "mice, survival, rms, Boruta, pROC, ggplot2, openxlsx, car, xgboost (optional SHAP)"
), file.path(.out, "Methods_software_versions.txt"))

# ---- figure formats ----
tryCatch({
  pub_figure_ensure_formats(file.path(.out, "Figures"), config = list(
    pub_figures = list(export_png = FALSE, export_tiff = FALSE)
  ))
}, error = function(e) message("ensure_formats: ", e$message))

# inventory check
message("==== inventory ====")
tabs <- list.files(.tab, pattern = "\\.xlsx$")
figs <- list.files(.fig, pattern = "\\.pdf$")
print(tabs); print(figs)
message("remirror done: ", .out)
