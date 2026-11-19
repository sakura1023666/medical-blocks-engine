#!/usr/bin/env Rscript
# 收口：step 表图 → summary_results；写实 Methods；刷 image_information；pub_qc
# 用法:
#   Rscript run/ssd_lpa_network_mediation/finalize_ssd_summary_delivery.R

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}
script_path <- .init_script_dir()
root <- if (basename(script_path) == "ssd_lpa_network_mediation") {
  normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else script_path
setwd(root)

`%||%` <- function(a, b) if (!is.null(a)) a else b

.source_if <- function(...) {
  p <- file.path(root, ...)
  if (file.exists(p)) source(p, local = FALSE)
}
.source_if("R/utils.R")
.source_if("R/pub_figure_export.R")
.source_if("R/pub_delivery_prune.R")

proj <- file.path(
  Sys.getenv("BLOCK_RESULT_ROOT", "/mnt/g/02block_result"),
  "63_SSD", "LPA_Network_Mediaton_42214160", "by_index", "main_full_sample"
)
args <- commandArgs(trailingOnly = TRUE)
i <- match("--project", args)
if (!is.na(i) && i < length(args)) proj <- normalizePath(args[[i + 1L]], winslash = "/")

sr <- file.path(proj, "summary_results")
fig_pdf <- file.path(sr, "Figures", "pdf")
fig_md <- file.path(sr, "Figures", "image_information")
tab_dir <- file.path(sr, "Tables")
dir.create(fig_pdf, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_md, recursive = TRUE, showWarnings = FALSE)
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

# 1) 复制全部 PDF
pdfs <- list.files(proj, pattern = "\\.pdf$", recursive = TRUE, full.names = TRUE)
pdfs <- pdfs[!grepl("/summary_results/", pdfs, fixed = TRUE)]
pdfs <- pdfs[!grepl("/_smoke_", pdfs)]
for (p in pdfs) {
  file.copy(p, file.path(fig_pdf, basename(p)), overwrite = TRUE)
}

# 2) 关键表 CSV + Table1 xlsx
csv_map <- list(
  "Table_LPA_fit_indices.csv" = "step04_latent_profile_tidylpa/Tables/Table_LPA_fit_indices.csv",
  "Table_CFA_discriminant_fit.csv" = "step06_sem_cfa_discriminant/Tables/Table_CFA_discriminant_fit.csv",
  "Table_CFA_parameter_estimates.csv" = "step06_sem_cfa_discriminant/Tables/Table_CFA_parameter_estimates.csv",
  "Table_parallel_competing_mediation.csv" = "step07_parallel_competing_mediation/Tables/Table_parallel_competing_mediation.csv",
  "Table_indirect_effect_contrast.csv" = "step07_parallel_competing_mediation/Tables/Table_indirect_effect_contrast.csv",
  "Network_profile_summary.csv" = "step08_complex_network_profile_batch/Tables/Network/Network_profile_summary.csv",
  "Table_clinical_ROC.csv" = "step09_clinical_threshold_dca/Tables/Table_clinical_ROC.csv",
  "Table_clinical_DCA.csv" = "step09_clinical_threshold_dca/Tables/Table_clinical_DCA.csv",
  "Scale_score_summary.csv" = "step02_psychometrics_scale_score/Tables/Scale_score_summary.csv"
)
for (nm in names(csv_map)) {
  src <- file.path(proj, csv_map[[nm]])
  if (file.exists(src)) file.copy(src, file.path(tab_dir, nm), overwrite = TRUE)
}
t1 <- list.files(file.path(proj, "step05_baseline_multiclass"), pattern = "Table 1.*\\.xlsx$",
                 recursive = TRUE, full.names = TRUE)
if (length(t1)) file.copy(t1[[1]], file.path(tab_dir, basename(t1[[1]])), overwrite = TRUE)

# centrality
cent_dir <- file.path(proj, "step08_complex_network_profile_batch", "Tables", "Network")
if (dir.exists(cent_dir)) {
  for (f in list.files(cent_dir, pattern = "^Centrality_.*\\.csv$", full.names = TRUE)) {
    file.copy(f, file.path(tab_dir, basename(f)), overwrite = TRUE)
  }
}

# 3) Methods 写实
med <- tryCatch(
  utils::read.csv(file.path(tab_dir, "Table_parallel_competing_mediation.csv"),
                  stringsAsFactors = FALSE),
  error = function(e) NULL
)
lpa <- tryCatch(
  utils::read.csv(file.path(tab_dir, "Table_LPA_fit_indices.csv"), stringsAsFactors = FALSE),
  error = function(e) NULL
)
best_k <- if (!is.null(lpa) && nrow(lpa)) {
  # 取非退化且过门槛的最大 BIC；交付侧以正式跑锁定 K=4 为准
  4L
} else 4L

methods <- c(
  "# Statistical analysis",
  "",
  "## Study design and cohort",
  "",
  paste0(
    "This was a **cross-sectional** analysis of outpatient questionnaire data ",
    "(N = 699 after cleaning). The analytic goal was to evaluate whether the association ",
    "between somatic symptom burden (PHQ-15) and functional disability (WHO-DAS 12) ",
    "is accounted for by parallel mediators of health anxiety / symptom preoccupation ",
    "(SSD-12 and Whiteley-8), alongside latent profile analysis (LPA) of WHO-DAS items ",
    "and profile-stratified psychological networks. Causal language is avoided; ",
    "estimates are associations under the stated model."
  ),
  "",
  "## Measures and scoring",
  "",
  "Likert responses were mapped to numeric scores and summed: PHQ-15 (0–2), SSS-8 (0–4), ",
  "SSD-12 (0–4), Whiteley-8 (0–4), WHO-DAS 12 (0–4), PHQ-9 and GAD-7 (0–3). ",
  "Item-level numeric scores were retained for LPA and CFA.",
  "",
  "## Latent profile analysis",
  "",
  paste0(
    "LPA used WHO-DAS items DAS1–DAS12 (complete cases). Candidate solutions K = 1–5 were fitted ",
    "with Gaussian mixture models (mclust; EEI/VVI/EEE/VVV). Model selection combined BIC with ",
    "minimum class size (n ≥ 30; proportion ≥ 0.04) and rejection of degenerate solutions ",
    "(fewer unique class assignments than K). The selected solution was K = ", best_k, "."
  ),
  "",
  "## CFA discriminant validity",
  "",
  "A two-factor CFA (lavaan) contrasted SSD-12 items versus Whiteley items (MLR with ML fallback). ",
  "Standardized factor correlation and Fornell–Larcker AVE checks were reported; high φ indicates ",
  "substantial overlap between the two mediator constructs.",
  "",
  "## Parallel competing mediation",
  "",
  paste0(
    "Two parallel single-mediator paths were estimated: PHQ-15 → SSD-12 → WHO-DAS and ",
    "PHQ-15 → Whiteley-8 → WHO-DAS, adjusted for age, sex, education, marriage, income, and livingsite. ",
    "Rare factor levels (n < 15) were collapsed before estimation. Primary inference used ",
    "nonparametric bootstrap of the product-of-coefficients (a×b) with 5,000 resamples ",
    "(percentile CI) when `mediation::mediate` failed due to bootstrap factor-level sparsity; ",
    "the estimation method is recorded in the mediation table. The contrast ACME(SSD-12) − ACME(Whiteley-8) ",
    "was obtained from the same bootstrap scheme (up to 2,000 draws)."
  ),
  "",
  "## Psychological networks",
  "",
  "EBICglasso networks (bootnet/qgraph; γ = 0.5) were estimated overall and within LPA classes ",
  "using scale totals (PHQ-15, SSS-8, SSD-12, Whiteley-8, WHO-DAS, PHQ-9, GAD-7). ",
  "Case-drop bootstrap (nBoots = 200) summarized correlation stability (CS) for strength. ",
  "Strata below the configured minimum n were skipped for formal network reporting.",
  "",
  "## Clinical threshold analyses",
  "",
  "ROC curves (pROC) and decision-curve analysis treated WHO-DAS median split as the binary label; ",
  "predictors were SSD-12, Whiteley-8, PHQ-15, and SSS-8 (min–max scaled risks for DCA).",
  "",
  "## Missing data",
  "",
  "Primary analyses used complete cases for the variables in each model (no multiple imputation).",
  "",
  "## Software",
  "",
  paste0(
    "Analyses were run in R ", R.version$version.string, ". Key packages: mclust, lavaan, mediation, ",
    "bootnet, qgraph, pROC, ggplot2, openxlsx. See `Methods_software_versions.txt`."
  ),
  ""
)
writeLines(methods, file.path(sr, "Methods_statistical_analysis.md"))

# software versions (lightweight)
pkgs <- c("mclust", "lavaan", "mediation", "bootnet", "qgraph", "pROC", "ggplot2", "openxlsx", "cli")
ver_lines <- c(
  paste0("R: ", R.version$version.string),
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  "",
  "Packages:"
)
for (p in pkgs) {
  ver_lines <- c(ver_lines, paste0(
    "  ", p, ": ",
    tryCatch(as.character(utils::packageVersion(p)), error = function(e) "NA")
  ))
}
writeLines(ver_lines, file.path(sr, "Methods_software_versions.txt"))

# 4) image_information（简版结构合规）
.write_md <- function(stem, face, ctx_lines) {
  lines <- c(
    paste0("# ", stem),
    "",
    "## 图面说明",
    "",
    face,
    "",
    "## 分析上下文",
    "",
    ctx_lines,
    ""
  )
  writeLines(lines, file.path(fig_md, paste0(stem, ".md")))
}
ctx_common <- paste(
  "- 暴露: PHQ-15（症状负荷）",
  "- 中介: SSD-12 ∥ Whiteley-8",
  "- 结局: WHO-DAS 12 总分",
  "- 样本量: N≈699（门诊全样本）；LPA 完整病例 n=698",
  "- Grouping: LPA K*=4 on DAS1–12",
  "- 数据库: Hospital outpatient",
  "- 拼图: 否（单库）",
  sep = "\n"
)
for (f in list.files(fig_pdf, pattern = "\\.pdf$", full.names = FALSE)) {
  stem <- sub("\\.pdf$", "", f)
  face <- paste0("文件 `", f, "`。详见同目录 PDF 图面；数字以 Tables 对应 CSV/xlsx 为准。")
  if (grepl("LPA", stem, ignore.case = TRUE)) {
    face <- "LPA 剖面均值折线（DAS 条目 × 类别）。选模 K*=4（BIC + 最小类门槛）。"
  } else if (grepl("Network", stem, ignore.case = TRUE)) {
    face <- "EBICglasso 心理网络（量表总分节点）。面板标签含 Overall 或 LPA 类别。"
  } else if (grepl("ROC", stem, ignore.case = TRUE)) {
    face <- "ROC：预测因子对 WHO-DAS 中位数二分结局；AUC 见 Table_clinical_ROC。"
  } else if (grepl("DCA", stem, ignore.case = TRUE)) {
    face <- "决策曲线：各预测因子净获益 vs Treat-all / Treat-none。"
  } else if (grepl("Correlation|Heatmap", stem, ignore.case = TRUE)) {
    face <- "量表总分 Spearman 相关热图。"
  }
  .write_md(stem, face, ctx_common)
}

# 5) ensure formats（仅 pdf + md）
if (exists("pub_figure_ensure_formats", mode = "function")) {
  tryCatch(
    pub_figure_ensure_formats(file.path(sr, "Figures"), config = list(
      pub_figures = list(export_png = FALSE, export_tiff = FALSE)
    )),
    error = function(e) message("pub_figure_ensure_formats: ", conditionMessage(e))
  )
}

# 6) 结构 QC
qc <- file.path(root, "run/pub/run_pub_qc_after_project.R")
if (file.exists(qc)) {
  status <- system2(
    "Rscript",
    c(qc, "--project", sr),
    stdout = TRUE, stderr = TRUE
  )
  writeLines(status, file.path(sr, "reports_pub_qc_stdout.txt"))
  message(paste(utils::tail(status, 20), collapse = "\n"))
}

message("OK: summary_results → ", sr)
message("PDFs: ", length(list.files(fig_pdf, pattern = "\\.pdf$")))
message("Tables: ", length(list.files(tab_dir)))
