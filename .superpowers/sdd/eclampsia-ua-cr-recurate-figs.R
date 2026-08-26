## 从 step 源 PDF 重建 UA_CR 定稿图序（不重跑模型）
Sys.setenv(
  MEDICAL_BLOCKS_ROOT = "E:/01block/01Block-new-Final",
  MEDICAL_BLOCKS_SKIP_WIN_R = "1"
)
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT")
study <- "G:/02block_result/27_eclampsia/small sample prediction_39780007"
source(file.path(root, "R/incidence_dual_batch_runner.R"))
source(file.path(root, "R/pub_figure_export.R"))
source(file.path(study, "config_ua_cr.R"))

index_root <- file.path(study, "by_index", "【success】UA_CR")
mimic <- file.path(index_root, "MIMIC_IV")
stopifnot(dir.exists(index_root), dir.exists(mimic))

## 权威源：各 step 原始图
src <- list(
  fig1 = file.path(mimic, "step35_attrition_flowchart/Figures/Figure 1. Flowchart.pdf"),
  fig2 = file.path(mimic, "step20_rcs_incidence/Figures/Figure 2-MIMIC IV-MIMIC IV. RCS plot between UA CR and Case.pdf"),
  fig3 = file.path(mimic, "step36_correlation/Figures/Figure Correlation Heatmap-MIMIC IV.pdf"),
  fig4 = file.path(mimic, "step29_performance_ml/Figures/Figure 3-MIMIC IV-MIMIC IV. ML performance combined 2x4.pdf"),
  fig5 = file.path(mimic, "step31_shap/Figures/Figure 4-MIMIC IV-MIMIC IV. SHAP.pdf"),
  fig6 = file.path(mimic, "step33_subgroup_incidence/Figures/Figure 5-MIMIC IV. Subgroup Forest analyses of UA CR.pdf")
)
for (nm in names(src)) {
  if (!file.exists(src[[nm]])) stop("missing source: ", nm, " -> ", src[[nm]])
}

tgt_names <- c(
  fig1 = "Figure 1. Flowchart.pdf",
  fig2 = "Figure 2. RCS plot between UA CR and Case.pdf",
  fig3 = "Figure 3. Correlation Heatmap.pdf",
  fig4 = "Figure 4. ML performance combined 2x4.pdf",
  fig5 = "Figure 5. SHAP.pdf",
  fig6 = "Figure 6. Subgroup Forest analyses of UA CR.pdf"
)

dirs <- c(
  file.path(mimic, "Figures"),
  file.path(index_root, "Figures"),
  file.path(index_root, "Figures", "pdf")
)
for (d in dirs) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  ## 清掉旧主图/乱名
  old <- list.files(d, pattern = "\\.pdf$", full.names = TRUE)
  drop <- old[grepl(
    "Flowchart|RCS|Correlation|combined 2x4|SHAP|Subgroup Forest|Figure [0-9]",
    basename(old),
    ignore.case = TRUE
  )]
  if (length(drop)) unlink(drop)
}

for (nm in names(src)) {
  for (d in dirs) {
    ok <- file.copy(src[[nm]], file.path(d, tgt_names[[nm]]), overwrite = TRUE)
    if (!isTRUE(ok)) stop("copy failed: ", nm, " -> ", d)
  }
}

## 走一遍 curate（应保持干净名）
incidence_batch_curate_ml_pub_figures_dir(file.path(mimic, "Figures"), cfg = config)
incidence_batch_curate_ml_pub_figures_dir(file.path(index_root, "Figures"), cfg = config)
incidence_batch_curate_ml_pub_figures_dir(file.path(index_root, "Figures", "pdf"), cfg = config)

## image_information（跳过栅格化失败不影响 md）
meta <- list(
  exposure = "UA_CR",
  outcome = "DN",
  databases = "nhanes",
  combined = FALSE,
  grouping = "quartile"
)
tryCatch(
  pub_figure_refresh_image_information(file.path(index_root, "Figures"), meta = meta, config = config),
  error = function(e) message("image_information: ", conditionMessage(e))
)

cat("\n==== MIMIC_IV/Figures ====\n")
print(sort(list.files(file.path(mimic, "Figures"), pattern = "\\.pdf$")))
cat("\n==== Figures/pdf ====\n")
print(sort(list.files(file.path(index_root, "Figures", "pdf"), pattern = "\\.pdf$")))
cat("\n==== image_information ====\n")
print(sort(list.files(file.path(index_root, "Figures", "image_information"), pattern = "\\.md$")))
cat("\nDONE\n")
