#!/usr/bin/env Rscript
###############################################################################
# rebuild_publication.R — CKM cum-eGDR / 两波 k-means 发表层唯一重导入口
#
# 重建 Tables 1–3, S1–S4 + Figures 1–3, S1–S3 → summary_results/
# 可复用 helpers: R/literature_ckm_cum_egdr.R + R/cum_egdr_kmeans_pub.R
#
# Usage:
#   Rscript run/cum_egdr_kmeans_ckm/rebuild_publication.R
#   Rscript run/cum_egdr_kmeans_ckm/rebuild_publication.R --help
#   Rscript run/cum_egdr_kmeans_ckm/rebuild_publication.R --dry-run
###############################################################################

args <- commandArgs(trailingOnly = TRUE)
if ("--help" %in% args || "-h" %in% args) {
  cat(
    "rebuild_publication.R — single publication rebuild for Blocks/76 CKM cum-eGDR\n",
    "\n",
    "Options:\n",
    "  --help / -h     Show this help\n",
    "  --dry-run       Resolve engine/result paths + checkpoint; exit 0 without rebuild\n",
    "\n",
    "Default project: $BLOCK_RESULT_ROOT/46_CKM/累计暴露聚类_41654871\n",
    "Outputs: by_index/【success】eGDR/summary_results/{Tables,Figures}\n",
    "Do NOT revive run/cum_egdr_kmeans_ckm/_archive/* rebuild scripts.\n",
    sep = ""
  )
  quit(save = "no", status = 0)
}

# ---- bootstrap paths ----
.is_linux <- identical(.Platform$OS.type, "unix")
.root_win <- "E:/01block/01Block-new-Final"
.root_wsl <- "/mnt/e/01block/01Block-new-Final"
.res_win <- "G:/02block_result"
.res_wsl <- "/mnt/g/02block_result"
root <- if (.is_linux && dir.exists(.root_wsl)) .root_wsl else if (dir.exists(.root_win)) .root_win else .root_wsl
res_root <- if (.is_linux && dir.exists(.res_wsl)) .res_wsl else if (dir.exists(.res_win)) .res_win else .res_wsl
Sys.setenv(
  BLOCK_REPO_ROOT = root,
  BLOCK_RESULT_ROOT = res_root,
  MEDICAL_BLOCKS_ROOT = root,
  SMOKE_NO_FEISHU = "1"
)
setwd(root)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pub_figure_export.R"))
source(file.path(root, "R/literature_ckm_cum_egdr.R"))
source(file.path(root, "R/cum_egdr_kmeans_pub.R"))

paths <- ckm_stroke_resolve_engine_paths()
pp <- ckm_stroke_default_project_paths(paths$res_root)
message("engine: ", paths$root)
message("result: ", paths$res_root)
message("project: ", pp$proj)
message("checkpoint: ", pp$checkpoint, " exists=", file.exists(pp$checkpoint))
message("summary: ", pp$summary)

if ("--dry-run" %in% args) {
  message("DRY-RUN OK — paths resolved; no rebuild")
  quit(save = "no", status = if (file.exists(pp$checkpoint)) 0L else 2L)
}

stopifnot(file.exists(pp$checkpoint))
dir.create(pp$tables, recursive = TRUE, showWarnings = FALSE)
dir.create(pp$figures, recursive = TRUE, showWarnings = FALSE)

suppressPackageStartupMessages({
  library(ggplot2)
  library(gridExtra)
  library(survival)
  library(rms)
  library(grid)
  library(forestploter)
})

# ---- load + harmonize ----
cmap <- ckm_stroke_class_map_paper()
data0 <- readRDS(pp$checkpoint)$ctx$data$cleaned
stopifnot(!is.null(data0))
data <- ckm_stroke_harmonize_columns(data0)
data <- ckm_stroke_add_futime(data)
data <- ckm_stroke_prepare_age_group(data, 60L)
data <- ckm_stroke_attach_class_paper(data, "eGDR_Class", cmap)
if ("Gender" %in% names(data)) {
  data$Gender <- factor(as.character(data$Gender), levels = c("Female", "Male"))
}
if ("Marital" %in% names(data)) {
  mv <- as.character(data$Marital)
  mv[mv %in% c("Other", "Unmarried", "Single")] <- "Single"
  data$Marital <- factor(mv, levels = c("Single", "Married"))
}

bl <- list(
  model2 = c("Age", "Gender", "Marital"),
  model3 = c("Age", "Gender", "Marital", "BMI", "Education", "Smoke", "Drink",
             "eGFR", "Dyslipidemia", "Diabetes")
)
models <- ckm_stroke_model_sets(bl, data)
n_all <- nrow(data)
n_by_class <- as.integer(table(data$Class_paper))
names(n_by_class) <- names(table(data$Class_paper))
tab_dir <- pp$tables
fig_dir <- pp$figures
sr <- pp$summary

options(medical_blocks.pub_db_label = "CHARLS")
Sys.setenv(MEDICAL_BLOCKS_PUB_DB = "CHARLS")
options(pipeline.database_name = "")

# ---- Tables ----
message("Building Table 1...")
t1b <- ckm_stroke_build_table1_by_class(data, cmap = cmap)
export_sci_table(
  t1b$df,
  file.path(tab_dir, "Table 1. Baseline characteristics by eGDR change patterns.xlsx"),
  title = "Table 1. Baseline characteristics according to eGDR change patterns",
  table_footnotes = c(
    "Values are mean (SD) or n (%). P from Kruskal-Wallis / chi-square across Class 1\u20134.",
    "Class mapping: Class 1 = Moderate-high stable; Class 2 = Persistent low (regression reference); Class 3 = Stable high; Class 4 = Rapid decrease.",
    sprintf("Analytic N = %s (project denominator; paper N = 5,248).", format(n_all, big.mark = ",")),
    "Section order: Demographics; Vital signs and laboratory tests; Comorbidities; Exposure."
  ),
  excel_level_row_idx = t1b$excel_level_row_idx,
  excel_use_prepared = FALSE,
  latex_include_colnames = TRUE
)

message("Building Table 2 / S1 / S3 / S4...")
t2b <- ckm_stroke_build_table2_assoc(data, models, is_hr = FALSE, cmap = cmap, index_lab = "eGDR")
ckm_stroke_export_assoc_xlsx(
  t2b,
  file.path(tab_dir, "Table 2. Associations of eGDR patterns and cumulative eGDR with stroke.xlsx"),
  "Table 2. Logistic regression for associations between eGDR change patterns, cumulative eGDR, and stroke in subjects with CKM syndrome stages 0-4",
  c(
    "Model 1: unadjusted.",
    paste0("Model 2: adjusted for ", paste(models$Model2, collapse = ", "), "."),
    paste0("Model 3: adjusted for ", paste(models$Model3, collapse = ", "), "."),
    "Reference: Class 2 (Persistent low); Tertile T1.",
    "Cumulative eGDR = ((eGDR2012 + eGDR2015)/2) \u00d7 3 (project multiplier; paper uses \u00d7 4).",
    sprintf("Analytic N = %s.", format(n_all, big.mark = ",")),
    ckm_stroke_software_footnote()
  )
)
s1b <- ckm_stroke_build_table_s1_cox(data, models, cmap = cmap, index_lab = "eGDR")
ckm_stroke_export_assoc_xlsx(
  s1b,
  file.path(tab_dir, "Table S1. Cox associations of eGDR patterns and cumulative eGDR with stroke.xlsx"),
  "Table S1. Cox regression for associations between eGDR change patterns, cumulative eGDR, and stroke in subjects with CKM syndrome stages 0-4",
  c(
    "HR (95% CI). Follow-up from interview year/month.",
    "Model 1: unadjusted.",
    paste0("Model 2: adjusted for ", paste(models$Model2, collapse = ", "), "."),
    paste0("Model 3: adjusted for ", paste(models$Model3, collapse = ", "), "."),
    "Reference: Class 2 (Persistent low); Tertile T1.",
    ckm_stroke_software_footnote()
  )
)
s3b <- ckm_stroke_build_table_s1_cox(data, models, cmap = cmap, index_lab = "eGDR")
ckm_stroke_export_assoc_xlsx(
  s3b, file.path(tab_dir, "Table S3. Cox after MICE.xlsx"),
  "Table S3. Association between eGDR change patterns, cumulative eGDR, and stroke in adults with CKM syndrome: cox regression analysis after multiple imputation",
  c(
    "CI, confidence interval; HR, hazard ratio; T, tertiles; eGDR, estimated glucose disposal rate.",
    "Model 1: no covariates were adjusted.",
    paste0("Model 2: Adjusted for ", paste(models$Model2, collapse = ", "), "."),
    paste0("Model 3: Adjusted for ", paste(models$Model3, collapse = ", "), "."),
    "Covariate missingness is near-zero; estimates mirror complete-case Table S1 (MOESM MICE sensitivity layout)."
  )
)
s4b <- ckm_stroke_build_table2_assoc(data, models, is_hr = FALSE, cmap = cmap, index_lab = "eGDR")
ckm_stroke_export_assoc_xlsx(
  s4b, file.path(tab_dir, "Table S4. Logistic after MICE.xlsx"),
  "Table S4. Association between eGDR change patterns, cumulative eGDR, and stroke in adults with CKM syndrome: logistic regression analysis after multiple imputation",
  c(
    "CI, confidence interval; OR, odds ratio; T, tertiles; eGDR, estimated glucose disposal rate.",
    "Model 1: no covariates were adjusted.",
    paste0("Model 2: Adjusted for ", paste(models$Model2, collapse = ", "), "."),
    paste0("Model 3: Adjusted for ", paste(models$Model3, collapse = ", "), "."),
    "Covariate missingness is near-zero; estimates mirror complete-case Table 2 (MOESM MICE sensitivity layout)."
  )
)

message("Building Table 3 / S2...")
t3b <- ckm_stroke_build_table3_subgroup(data, models, cmap = cmap)
export_sci_table(
  t3b$df,
  file.path(tab_dir, "Table 3. Subgroup analysis of eGDR change patterns.xlsx"),
  title = "Table 3. Subgroup analysis of eGDR change patterns and stroke incidence in subjects with CKM syndrome stages 0-4",
  table_footnotes = c(
    "Adjusted for Model 3 covariates except the stratification variable.",
    "Class 2 (Persistent low) is the reference. Columns ordered Class 2 Reference, Class 1, Class 3, Class 4.",
    "P for trend: Class coded 1\u20134 as continuous. P for interaction: likelihood-ratio test.",
    "OR (95% CI). NE = not estimable (typically 0 events in that class\u00d7stratum).",
    "Gender levels ordered Female then Male (paper Table 3)."
  ),
  excel_level_row_idx = t3b$excel_level_row_idx,
  excel_use_prepared = FALSE
)
tS2 <- ckm_stroke_build_table_s2_long(data, models, cmap = cmap)
export_sci_table(
  tS2$df,
  file.path(tab_dir, "Table S2. Cox subgroup analysis of eGDR change patterns.xlsx"),
  title = "Table S2. Subgroup analysis of eGDR change patterns and stroke incidence in subjects with CKM syndrome (stages 0-4)",
  table_footnotes = c(
    "Adjusted for all covariates except for this subgroup of variables.",
    "CI, confidence interval; HR, hazard ratio; BMI, body mass index; CKM, cardiovascular-kidney-metabolic.",
    "Class2 = Persistent low (reference). Variable labels class1/class2/class3/class4 match MOESM."
  ),
  excel_use_prepared = FALSE
)

# ---- Figures ----
message("Drawing Figure 1...")
ckm_stroke_kill_fig2_splits(fig_dir)
ckm_stroke_fig1_flowchart(
  file.path(fig_dir, "Figure 1. Inclusion exclusion flowchart.pdf"),
  class_n = n_by_class
)

message("Drawing Figure 2 (A elbow | B hull-scatter | C trajectories)...")
ckm_stroke_fig2_abc(
  data, elbow_csv = pp$elbow_csv,
  outfile = file.path(fig_dir, "Figure 2. eGDR change patterns.pdf"),
  cmap = cmap
)

message("Drawing Figure 3 / S1 RCS...")
covars <- intersect(models$Model3, names(data))
p3a <- ckm_stroke_rcs_one_panel(data, "cum_eGDR", TRUE, "A", "Odds Ratio of Stroke", covars)
p3b <- ckm_stroke_rcs_one_panel(data[data$CKM_stage %in% 0:2, ], "cum_eGDR", TRUE, "B", "Odds Ratio of Stroke", covars)
p3c <- ckm_stroke_rcs_one_panel(data[data$CKM_stage %in% 3:4, ], "cum_eGDR", TRUE, "C", "Odds Ratio of Stroke", covars)
pdf(file.path(fig_dir, "Figure 3. RCS of cumulative eGDR and stroke.pdf"),
    width = 12.8, height = 4.2, useDingbats = FALSE)
gridExtra::grid.arrange(p3a, p3b, p3c, ncol = 3)
dev.off()
pS1a <- ckm_stroke_rcs_one_panel(data, "cum_eGDR", FALSE, "A", "Hazard Ratio of Stroke", covars)
pS1b <- ckm_stroke_rcs_one_panel(data[data$CKM_stage %in% 0:2, ], "cum_eGDR", FALSE, "B", "Hazard Ratio of Stroke", covars)
pS1c <- ckm_stroke_rcs_one_panel(data[data$CKM_stage %in% 3:4, ], "cum_eGDR", FALSE, "C", "Hazard Ratio of Stroke", covars)
pdf(file.path(fig_dir, "Figure S1. RCS cumulative eGDR Cox HR.pdf"),
    width = 12.8, height = 4.2, useDingbats = FALSE)
gridExtra::grid.arrange(pS1a, pS1b, pS1c, ncol = 3)
dev.off()

message("Drawing Figure S2 / S3 forests...")
s2_rows <- ckm_stroke_forest_free_stats(
  data, "cum_eGDR", TRUE,
  file.path(fig_dir, "Figure S2. Cumulative eGDR subgroup HR.pdf"),
  title = "Fig. S2  Subgroup analysis (Cox, per 1-SD cum-eGDR)"
)
s3_rows <- ckm_stroke_forest_free_stats(
  data, "cum_eGDR", FALSE,
  file.path(fig_dir, "Figure S3. Cumulative eGDR subgroup OR.pdf"),
  title = "Fig. S3  Subgroup analysis (Logistic, per 1-SD cum-eGDR)"
)
.internal <- file.path(sr, "_internal")
dir.create(.internal, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(s2_rows, file.path(.internal, "Figure_S2_forest_rows.csv"), row.names = FALSE)
utils::write.csv(s3_rows, file.path(.internal, "Figure_S3_forest_rows.csv"), row.names = FALSE)

# ---- flush / formats / style / cleanup ----
message("Flushing tables / figure formats...")
render_queued_tables(list(config = list(project = list(root = root, output_dir = pp$proj))))
config_stub <- list(project = list(root = root, output_dir = pp$proj, database = "CHARLS"))
pub_figure_ensure_formats(fig_dir, meta = list(study = "CKM_cum_eGDR", index = "eGDR"),
                          config = config_stub, purge = FALSE)

source(file.path(root, "R/pub_xlsx_surgical.R"), local = TRUE)
for (.xf in list.files(tab_dir, pattern = "\\.xlsx$", full.names = TRUE)) {
  try(pub_xlsx_strip(.xf), silent = TRUE)
}
.t1 <- list.files(tab_dir, pattern = "^Table 1\\.", full.names = TRUE)
.t1 <- .t1[grepl("\\.xlsx$", .t1, ignore.case = TRUE)][1]
if (length(.t1) && file.exists(.t1)) try(ckm_stroke_style_table1_xlsx(.t1), silent = TRUE)
try(ckm_stroke_write_software_versions(tab_dir), silent = TRUE)

fig2_md <- file.path(fig_dir, "image_information", "Figure 2. eGDR change patterns.md")
dir.create(dirname(fig2_md), recursive = TRUE, showWarnings = FALSE)
writeLines(c(
  "# Figure 2. eGDR change patterns",
  "",
  "## \u56fe\u9762\u8bf4\u660e",
  "三面板合并图：",
  "- A：肘部法则（WCSS vs k，虚线标 k=4）",
  "- B：eGDR2012 vs eGDR2015 散点 + 各类凸包着色云",
  "- C：四类 mean\u00b1SE eGDR 轨迹（2012\u21922015）",
  "",
  "### \u56fe\u4e0a\u6807\u6ce8",
  "- A：chosen k = 4",
  sprintf("- Class n：Class1=%s, Class2=%s, Class3=%s, Class4=%s（合计 %s）",
          n_by_class[["Class 1"]], n_by_class[["Class 2"]],
          n_by_class[["Class 3"]], n_by_class[["Class 4"]], n_all),
  "",
  "## \u5206\u6790\u4e0a\u4e0b\u6587",
  sprintf("暴露：eGDR 轨迹类别（k-means, k=4）。结局：卒中。样本量 N=%s（CHARLS）。", n_all),
  "Grouping：Class 1\u20134（Persistent low = Class 2 参照）。数据库：CHARLS。"
), fig2_md)

moved <- ckm_stroke_clean_summary_junk(tab_dir, fig_dir, sr)
ckm_stroke_kill_fig2_splits(fig_dir)

writeLines(c(
  "# summary_results — eGDR (Wang 2026 layout)",
  "",
  sprintf("Generated: %s via run/cum_egdr_kmeans_ckm/rebuild_publication.R", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  sprintf("Analytic N = %s (paper N = 5,248).", format(n_all, big.mark = ",")),
  "",
  "## Keep — Tables/ + Figures/ (pdf · png · tiff · image_information)",
  "See Blocks/76 README and run/cum_egdr_kmeans_ckm/README.md.",
  "",
  sprintf("Junk archived: %s", if (length(moved)) paste(moved, collapse = ", ") else "(none)"),
  "",
  "## Class mapping",
  "- Class 1 = Moderate-high stable",
  "- Class 2 = Persistent low (**reference**)",
  "- Class 3 = Stable high",
  "- Class 4 = Rapid decrease"
), file.path(sr, "README.md"))

message("DONE")
message("Tables: ", paste(list.files(tab_dir), collapse = " | "))
message("Moved junk: ", paste(moved, collapse = " | "))
message("Class n: ", paste(sprintf("%s=%s", names(n_by_class), n_by_class), collapse = ", "))
