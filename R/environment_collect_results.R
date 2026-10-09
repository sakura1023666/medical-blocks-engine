###############################################################################
#  environment_collect_results.R — DKD × 环境 VOC 流水线 Results_Summary 汇总
#
#  按 VOC 最终 Step 顺序，将 _shared / _tail / by_voc 下的 Table/Figure
#  复制到 <output_base>/Results_Summary/{Tables,Figures}，并写入 manifest.csv
###############################################################################

environment_collect_dkd_results <- function(
    result_root,
    disease = "DKD",
    project_root = NULL
) {
  result_root <- normalizePath(as.character(result_root)[1L], winslash = "/", mustWork = FALSE)
  disease     <- as.character(disease)[1L]

  if (!dir.exists(result_root)) {
    stop("结果目录不存在: ", result_root, call. = FALSE)
  }

  if (is.null(project_root) || !nzchar(project_root)) {
    project_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  }
  if (!nzchar(project_root)) {
    project_root <- getwd()
  }
  project_root <- normalizePath(project_root, winslash = "/")

  disp_path <- file.path(project_root, "R/environment_display_utils.R")
  if (file.exists(disp_path) &&
      !exists("environment_display_label", mode = "function")) {
    source(disp_path, local = FALSE)
  }

  voc_label <- function(voc) {
    if (exists("environment_display_label", mode = "function")) {
      environment_display_label(voc, NULL)
    } else {
      x <- gsub("_", " ", voc, fixed = TRUE)
      gsub("\\bAMC\\b", "AMCC", x, perl = TRUE)
    }
  }

  out_root    <- file.path(result_root, "Results_Summary")
  dir_tables  <- file.path(out_root, "Tables")
  dir_figs    <- file.path(out_root, "Figures")
  dir.create(dir_tables, recursive = TRUE, showWarnings = FALSE)
  dir.create(dir_figs,   recursive = TRUE, showWarnings = FALSE)

  # Windows 禁止 <>:"/\|?* ；历史标准名里的 p<0.05 会直接导致 file.copy Invalid argument
  sanitize_fs_name <- function(x) {
    x <- as.character(x)[1L]
    if (!nzchar(x) || is.na(x)) return(x)
    x <- gsub("[<>:\"/\\\\|?*]", "_", x, perl = TRUE)
    x <- gsub("[[:space:]]+", " ", x, perl = TRUE)
    trimws(x)
  }

  safe_copy <- function(src, dest) {
    if (!length(src) || !nzchar(src[1L]) || is.na(src[1L]) || !file.exists(src[1L])) {
      return(list(ok = FALSE, src = src[1L], dest = dest, note = "missing"))
    }
    dest_dir <- dirname(dest)
    dest_bn  <- sanitize_fs_name(basename(dest))
    dest     <- file.path(dest_dir, dest_bn)
    src_norm <- normalizePath(src[1L], winslash = "/", mustWork = FALSE)
    dest_norm <- tryCatch(
      normalizePath(dest, winslash = "/", mustWork = FALSE),
      error = function(e) dest
    )
    if (identical(src_norm, dest_norm)) {
      return(list(ok = TRUE, src = src_norm, dest = dest_norm, note = "same_file"))
    }
    if (!dir.exists(dest_dir)) dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
    ok <- isTRUE(suppressWarnings(file.copy(src[1L], dest, overwrite = TRUE)))
    if (!ok && !file.exists(dest)) {
      cli::cli_alert_warning("Results_Summary 复制失败: {basename(dest)}")
    }
    list(
      ok = ok,
      src = src_norm,
      dest = dest,
      note = if (ok) "copied" else "copy_failed"
    )
  }

  find_first <- function(..., exclude_pattern = NULL) {
    cands <- unlist(list(...), use.names = FALSE)
    cands <- cands[nzchar(cands)]
    for (pat in cands) {
      hits <- if (grepl("^/", pat) || grepl("^[A-Za-z]:/", pat)) {
        Sys.glob(pat)
      } else {
        Sys.glob(file.path(result_root, pat))
      }
      hits <- hits[file.exists(hits)]
      if (length(exclude_pattern)) {
        hits <- hits[!grepl(exclude_pattern, basename(hits), ignore.case = TRUE)]
      }
      if (length(hits)) return(normalizePath(hits[1L], winslash = "/"))
    }
    NA_character_
  }

  manifest <- data.frame(
    order = integer(0), kind = character(0), standard_id = character(0),
    standard_name = character(0), source = character(0), dest = character(0),
    status = character(0), stringsAsFactors = FALSE
  )

  add_row <- function(order, kind, id, name, src_path, dest_name) {
    dest_name <- sanitize_fs_name(dest_name)
    dest_path <- file.path(if (kind == "Table") dir_tables else dir_figs, dest_name)
    cp <- safe_copy(src_path, dest_path)
    status <- if (isTRUE(cp$ok)) {
      "copied"
    } else {
      as.character(cp$note %||% "copy_failed")[1L]
    }
    if (!nzchar(status) || is.na(status)) status <- "copy_failed"
    manifest <<- rbind(manifest, data.frame(
      order = as.integer(order)[1L],
      kind = as.character(kind)[1L],
      standard_id = as.character(id)[1L],
      standard_name = as.character(name)[1L],
      source = if (length(src_path) != 1L || is.na(src_path)) "" else as.character(src_path)[1L],
      dest = as.character(dest_path)[1L],
      status = status,
      stringsAsFactors = FALSE
    ))
  }

  # ── Tables（VOC 最终 Step02→Step12 顺序）──────────────────────────────────
  add_row(1L, "Table", "Table 1",
    paste0("Table 1. Baseline characteristics of participants by ", disease),
    find_first(
      "_shared/step06_baseline_nhanes/Tables/Table 1-NHANES*.xlsx",
      "_shared/Tables/Table 1-NHANES*.xlsx"
    ),
    paste0("Table 1. Baseline characteristics of participants by ", disease, ".xlsx"))

  add_row(2L, "Table", "Table S1",
    "Table S1. Characteristics of Environmental Contaminants or Metabolites",
    find_first(
      "_shared/step04_environment_lod_screen/Tables/Table S1*.xlsx",
      "_shared/Tables/Table S1. Characteristics*.xlsx",
      "_shared/Tables/Table_Environment_Characteristics.xlsx",
      "_shared/step18_environment_characteristics/Tables/Table_Environment_Characteristics.xlsx"
    ),
    "Table S1. Characteristics of Environmental Contaminants or Metabolites.xlsx")

  add_row(3L, "Table", "Table S2",
    "Table S2. Comparison of characteristics before and after multiple imputation",
    find_first(
      "_shared/step04_imputation/Tables/Table S1-NHANES*.xlsx",
      "_shared/Tables/Table S1-NHANES*.xlsx"
    ),
    "Table S2. Comparison of characteristics before and after multiple imputation.xlsx")

  add_row(4L, "Table", "Table S2-Normality",
    "Table S2-NHANES. Normality test results for continuous variables",
    find_first(
      "_shared/step06_baseline_nhanes/Tables/Table S2-NHANES*Normality*.xlsx",
      "_shared/step06_baseline_nhanes/Tables/*Normality*.xlsx"
    ),
    "Table S2-NHANES. Normality test results for continuous variables.xlsx")

  add_row(5L, "Table", "Table S3",
    paste0("Table S3. Univariate regression analysis (", disease, ")"),
    find_first(
      "_shared/step09_univariate_nhanes/Tables/Table S3-NHANES*.xlsx",
      "_shared/step07_univariate_nhanes/Tables/Table S3-NHANES*.xlsx",
      "_shared/Tables/Table S3-NHANES*.xlsx",
      exclude_pattern = "VOC"
    ),
    paste0("Table S3. Univariate regression analysis (", disease, ").xlsx"))

  add_row(6L, "Table", "Table S4-VIF-screen",
    "Table S4-NHANES. Weighted Multicollinearity Analysis (VIF, univariate p_0.05)",
    find_first(
      "_shared/step11_multicollinearity_nhanes_screen/Tables/Table S4-NHANES*.xlsx",
      "_shared/step08_multicollinearity_nhanes_screen/Tables/Table S4-NHANES*.xlsx",
      "_shared/Tables/Table S4-NHANES*.xlsx",
      exclude_pattern = "VOC"
    ),
    "Table S4-NHANES. Weighted Multicollinearity Analysis (VIF, univariate p_0.05).xlsx")

  add_row(7L, "Table", "Table S3-VOC",
    paste0("Table S3-NHANES-VOC. Univariate regression analysis (", disease, ", environmental toxicants)"),
    find_first(
      "_shared/Tables/Table S3-NHANES-VOC*.xlsx",
      "Tables/Table S3-NHANES-VOC*.xlsx"
    ),
    "Table S3-NHANES-VOC. Univariate Regression Analysis (Environmental Toxicants).xlsx")

  add_row(8L, "Table", "Table S4-VOC-VIF",
    "Table S4-NHANES-VOC. Weighted Multicollinearity Analysis (VIF, univariate p_0.05 screen)",
    find_first(
      "_shared/Tables/Table S4-NHANES-VOC*Weighted Multicollinearity*.xlsx",
      "_shared/Tables/Table S4-NHANES-VOC*VIF*.xlsx",
      "_shared/step11_multicollinearity_nhanes_screen/Tables/Table S4-NHANES-VOC*.xlsx",
      "Tables/Table S4-NHANES-VOC*Weighted Multicollinearity*.xlsx",
      exclude_pattern = "Univariate|Regression"
    ),
    "Table S4-NHANES-VOC. Weighted Multicollinearity Analysis (VIF, univariate p_0.05 screen).xlsx")

  add_row(9L, "Table", "Table S5-VOC-Screen",
    "Table S5. Environmental VOC screening summary (univariate p_0.05, VIF_4, r_0.7)",
    find_first(
      "_shared/step10_environment_voc_clinical_gate/Tables/Table_Environment_VOC_Screen_Summary.csv",
      "_shared/Tables/Table_Environment_VOC_Screen_Summary.csv"
    ),
    "Table S5. Environmental VOC screening summary.csv")

  add_row(10L, "Table", "Table S7-LASSO",
    paste0("Table S7. Association between Environmental Toxicants and ", disease),
    find_first(
      "_shared/step15_lasso_environment_voc/Tables/Table S7*.xlsx",
      "_shared/step15_lasso_environment_voc/Tables/*Association*.xlsx",
      "_shared/step15_lasso_environment_voc/Tables/Table_Lasso_Univariate_Screen.xlsx",
      "_shared/step13_lasso_environment_voc/Tables/Table S7*.xlsx",
      "_shared/step13_lasso_environment_voc/Tables/*Association*.xlsx",
      "_shared/Tables/Table S7*Association*.xlsx",
      "_shared/Tables/Table_Lasso_Univariate_Screen.xlsx",
      exclude_pattern = "Multicollinearity|VIF"
    ),
    paste0("Table S7. Association between Environmental Toxicants and ", disease, ".xlsx"))

  add_row(11L, "Table", "Table S8-GLM",
    "Table S8. Selection of Environmental exposure variables for GLM",
    find_first(
      "_shared/step16_glm_environment_quartile/Tables/Table S8*.xlsx",
      "_shared/step14_glm_environment_quartile/Tables/Table S8*.xlsx",
      "_shared/Tables/Table S8*.xlsx",
      "_shared/Tables/Table_S4_GLM_Environment_Selection.xlsx"
    ),
    "Table S8. Selection of Environmental exposure variables for GLM.xlsx")

  add_row(12L, "Table", "Table S9-WQS",
    paste0("Table S9. Associations of WQS regression index with ", disease),
    find_first(
      "_shared/step19_wqs_environment/Tables/Table S9*.xlsx",
      "_shared/step15_wqs_environment/Tables/Table S9*.xlsx",
      "_shared/Tables/Table S9*.xlsx",
      "_shared/Tables/Table_S5_WQS_DKD.xlsx"
    ),
    paste0("Table S9. Associations of WQS regression index with ", disease, ".xlsx"))

  add_row(13L, "Table", "Table S10-BKMR",
    paste0("Table S10. PIP values in BKMR model in ", disease),
    find_first(
      "_shared/step21_bkmr_analysis/Tables/Table S10*.xlsx",
      "_shared/step18_bkmr_analysis/Tables/Table S10*.xlsx",
      "_shared/step17_bkmr_analysis/Tables/Table S10*.xlsx",
      "_shared/Tables/Table S10*.xlsx",
      "_shared/Tables/Table_S6_BKMR_PIP_DKD.xlsx"
    ),
    paste0("Table S10. PIP values in BKMR model in ", disease, ".xlsx"))

  add_row(14L, "Table", "Table S11-Mediation",
    paste0("Table S11. Mediation effects in the associations of Environmental Toxicants with ", disease),
    find_first(
      "_tail/step23_mediation_ers_environment/Tables/Table S11*.xlsx",
      "_tail/step22_mediation_ers_environment/Tables/Table S11*.xlsx",
      "_tail/step19_mediation_ers_environment/Tables/Table S11*.xlsx",
      "_tail/Tables/Table S11*.xlsx",
      "_tail/step23_mediation_ers_environment/Tables/Table_S7_Mediation_DKD.xlsx",
      "_tail/step19_mediation_ers_environment/Tables/Table_S7_Mediation_DKD.xlsx",
      "_tail/Tables/Table_S7_Mediation_DKD.xlsx"
    ),
    paste0("Table S11. Mediation effects in the associations of Environmental Toxicants with ", disease, ".xlsx"))

  add_row(13L, "Table", "Table S12-Subgroup-Gender",
    paste0("Table S12. Subgroup analysis stratified by Gender (", disease, ")"),
    find_first(
      "_tail/*/Tables/Table_S*Subgroup*Gender*.xlsx",
      "_tail/Tables/Table_S*Subgroup*Gender*.xlsx"
    ),
    paste0("Table S12. Subgroup analysis stratified by Gender (", disease, ").xlsx"))

  add_row(14L, "Table", "Table S13-Subgroup-Race",
    paste0("Table S13. Subgroup analysis stratified by Race (", disease, ")"),
    find_first(
      "_tail/*/Tables/Table_S*Subgroup*Race*.xlsx",
      "_tail/Tables/Table_S*Subgroup*Race*.xlsx",
      "Tables/Table_S9_Subgroup_Race*.xlsx"
    ),
    paste0("Table S13. Subgroup analysis stratified by Race (", disease, ").xlsx"))

  add_row(15L, "Table", "Table S14-Subgroup-PIR",
    paste0("Table S14. Subgroup analysis stratified by PIR (", disease, ")"),
    find_first(
      "_tail/*/Tables/Table_S*Subgroup*PIR*.xlsx",
      "_tail/Tables/Table_S*Subgroup*PIR*.xlsx",
      "Tables/Table_S10_Subgroup_PIR*.xlsx"
    ),
    paste0("Table S14. Subgroup analysis stratified by PIR (", disease, ").xlsx"))

  add_row(16L, "Table", "Table S15-Subgroup-Smoked",
    paste0("Table S15. Subgroup analysis stratified by Smoking (", disease, ")"),
    find_first(
      "_tail/*/Tables/Table_S*Subgroup*Smok*.xlsx",
      "_tail/Tables/Table_S*Subgroup*Smok*.xlsx",
      "Tables/Table_S11_Subgroup_Smoking*.xlsx"
    ),
    paste0("Table S15. Subgroup analysis stratified by Smoking (", disease, ").xlsx"))

  add_row(17L, "Table", "Table S19-Qgcomp",
    paste0("Table S19. Associations of Environmental Toxicants with ", disease, " by using Quantile g-Computation"),
    find_first(
      "_tail/step22_qgcomp_environment/Tables/Table S19*.csv",
      "_tail/step19_qgcomp_environment/Tables/Table S19*.csv",
      "_tail/*/Tables/Table S19*.csv",
      "_tail/Tables/Table S19*.csv",
      "_tail/Tables/Table S12*.csv"
    ),
    paste0("Table S19. Associations of Environmental Toxicants with ", disease, " by using Quantile g-Computation.csv"))

  # FDR 表已由 environment_build_*_fdr 直接写入 Results_Summary（病名用空格）；
  # collect 侧 dest 必须同口径，否则会复制出 Female_Infertility 重复件。
  disease_fdr <- gsub("_", " ", disease, fixed = TRUE)

  add_row(18L, "Table", "Table S20-FDR-GLM",
    paste0("Table S20. FDR-adjusted GLM continuous associations of Environmental Toxicants with ", disease_fdr, " (full population)"),
    find_first(
      "Results_Summary/Tables/Table S20. FDR-adjusted GLM*.xlsx",
      "Results_Summary/Tables/*FDR-adjusted GLM*.xlsx"
    ),
    paste0("Table S20. FDR-adjusted GLM continuous associations of Environmental Toxicants with ", disease_fdr, " (full population).xlsx"))

  add_row(19L, "Table", "Table S21-FDR-WQS",
    paste0("Table S21. FDR-adjusted WQS index association with ", disease_fdr, " (full population)"),
    find_first(
      "Results_Summary/Tables/Table S21. FDR-adjusted WQS*.xlsx",
      "Results_Summary/Tables/*FDR-adjusted WQS*.xlsx"
    ),
    paste0("Table S21. FDR-adjusted WQS index association with ", disease_fdr, " (full population).xlsx"))

  add_row(20L, "Table", "Table S22-FDR-BKMR",
    paste0("Table S22. FDR-adjusted BKMR PIP for Environmental Toxicants with ", disease_fdr, " (full population)"),
    find_first(
      "Results_Summary/Tables/Table S22. FDR-adjusted BKMR*.xlsx",
      "Results_Summary/Tables/*FDR-adjusted BKMR*.xlsx"
    ),
    paste0("Table S22. FDR-adjusted BKMR PIP for Environmental Toxicants with ", disease_fdr, " (full population).xlsx"))

  add_row(21L, "Table", "Table S23-FDR-QGC",
    paste0("Table S23. FDR-adjusted Quantile g-Computation associations with ", disease_fdr, " (full population)"),
    find_first(
      "Results_Summary/Tables/Table S23. FDR-adjusted Quantile*.xlsx",
      "Results_Summary/Tables/*FDR-adjusted Quantile*.xlsx"
    ),
    paste0("Table S23. FDR-adjusted Quantile g-Computation associations with ", disease_fdr, " (full population).xlsx"))

  add_row(22L, "Table", "Table S12-KEGG",
    "Table S12. Results of KEGG Enrichment Analysis",
    find_first("_tail/**/Table S12*.xlsx", "Tables/Table S12*.xlsx"),
    "Table S12. Results of KEGG Enrichment Analysis.xlsx")

  add_row(23L, "Table", "Table S13-GO-BP",
    "Table S13. Results of GO-BP Enrichment Analysis",
    find_first("_tail/**/Table S13*.xlsx", "Tables/Table S13*.xlsx"),
    "Table S13. Results of GO-BP Enrichment Analysis.xlsx")

  add_row(24L, "Table", "Table S14-GO-CC",
    "Table S14. Results of GO-CC Enrichment Analysis",
    find_first("_tail/**/Table S14*.xlsx", "Tables/Table S14*.xlsx"),
    "Table S14. Results of GO-CC Enrichment Analysis.xlsx")

  add_row(25L, "Table", "Table S15-GO-MF",
    "Table S15. Results of GO-MF Enrichment Analysis",
    find_first("_tail/**/Table S15*.xlsx", "Tables/Table S15*.xlsx"),
    "Table S15. Results of GO-MF Enrichment Analysis.xlsx")

  # ── Figures ───────────────────────────────────────────────────────────────
  add_row(30L, "Figure", "Figure S1",
    "Figure S1. Variable missing value overview",
    find_first(
      "_shared/step05_imputation/Figures/Figure Missing Value Overview.pdf",
      "_shared/step04_imputation/Figures/Figure Missing Value Overview.pdf",
      "_shared/Figures/Figure Missing Value Overview.pdf"
    ),
    "Figure S1. Variable missing value overview.pdf")

  add_row(31L, "Figure", "Figure 2",
    "Figure 2. Selection of Environmental exposure variables for Lasso regression",
    find_first(
      "_shared/step15_lasso_environment_voc/Figures/Figure 2*.pdf",
      "_shared/step13_lasso_environment_voc/Figures/Figure 2*.pdf",
      "_shared/Figures/pdf/Figure 2*.pdf",
      "_shared/Figures/Figure 2*.pdf"
    ),
    "Figure 2. Selection of Environmental exposure variables for Lasso regression.pdf")

  add_row(32L, "Figure", "Figure S2-VOC",
    "Figure S2. Correlation of Environmental Toxicants (Spearman)",
    find_first(
      "_shared/step12_environment_voc_corrplot/Figures/Figure Corrplot VOC.pdf",
      "_shared/Figures/pdf/Figure Corrplot VOC.pdf",
      "_shared/Figures/Figure Corrplot VOC.pdf"
    ),
    "Figure S2. Correlation of Environmental Toxicants.pdf")

  add_row(33L, "Figure", "Figure S2-Baseline",
    "Figure S2. Correlation of baseline covariates (Spearman)",
    find_first(
      "_shared/step12_environment_voc_corrplot/Figures/Figure Corrplot Baseline.pdf",
      "_shared/Figures/pdf/Figure Corrplot Baseline.pdf",
      "_shared/Figures/Figure Corrplot Baseline.pdf"
    ),
    "Figure S2. Correlation of baseline covariates.pdf")

  add_row(34L, "Figure", "Figure 3",
    paste0("Figure 3. The WQS model weights of screened Environmental Toxicants on ", disease),
    find_first(
      "_shared/step19_wqs_environment/Figures/Figure_WQS_Weights.pdf",
      "_shared/step16_wqs_environment/Figures/Figure_WQS_Weights.pdf",
      "_shared/step15_wqs_environment/Figures/Figure_WQS_Weights.pdf",
      "_shared/Figures/pdf/Figure_WQS_Weights.pdf",
      "_shared/Figures/Figure_WQS_Weights.pdf",
      "Figures/Figure_WQS_Weights.pdf"
    ),
    paste0("Figure 3. The WQS model weights of screened Environmental Toxicants on ", disease, ".pdf"))

  add_row(35L, "Figure", "Figure 4",
    paste0("Figure 4. The combined effect of Environmental Toxicants on ", disease, " risk"),
    find_first(
      "_shared/step21_bkmr_analysis/Figures/Figure_BKMR_Overall.pdf",
      "_shared/step18_bkmr_analysis/Figures/Figure_BKMR_Overall.pdf",
      "_shared/step17_bkmr_analysis/Figures/Figure_BKMR_Overall.pdf",
      "_shared/Figures/pdf/Figure_BKMR_Overall.pdf",
      "_shared/Figures/Figure_BKMR_Overall.pdf"
    ),
    paste0("Figure 4. The combined effect of Environmental Toxicants on ", disease, " risk.pdf"))

  add_row(36L, "Figure", "Figure 5",
    paste0("Figure 5. Association of individual Environmental Toxicants with ", disease),
    find_first(
      "_shared/step21_bkmr_analysis/Figures/Figure_BKMR_SingVar.pdf",
      "_shared/step18_bkmr_analysis/Figures/Figure_BKMR_SingVar.pdf",
      "_shared/step17_bkmr_analysis/Figures/Figure_BKMR_SingVar.pdf",
      "_shared/Figures/pdf/Figure_BKMR_SingVar.pdf",
      "_shared/Figures/Figure_BKMR_SingVar.pdf"
    ),
    paste0("Figure 5. Association of individual Environmental Toxicants with ", disease, ".pdf"))

  add_row(37L, "Figure", "Figure 6",
    paste0("Figure 6. Dose-response of individual Environmental Toxicants with ", disease),
    find_first(
      "_shared/step21_bkmr_analysis/Figures/Figure_BKMR_DoseResponse.pdf",
      "_shared/step18_bkmr_analysis/Figures/Figure_BKMR_DoseResponse.pdf",
      "_shared/step17_bkmr_analysis/Figures/Figure_BKMR_DoseResponse.pdf",
      "_shared/Figures/pdf/Figure_BKMR_DoseResponse.pdf",
      "_shared/Figures/Figure_BKMR_DoseResponse.pdf"
    ),
    paste0("Figure 6. Dose-response of individual Environmental Toxicants with ", disease, ".pdf"))

  add_row(40L, "Figure", "Figure 8",
    paste0("Figure 8. QGC model weights of screened Environmental Toxicants on ", disease),
    find_first(
      "_tail/step22_qgcomp_environment/Figures/Figure_QGComp_Weights.pdf",
      "_tail/step19_qgcomp_environment/Figures/Figure_QGComp_Weights.pdf",
      "_tail/*/Figures/Figure_QGComp_Weights.pdf",
      "_tail/Figures/pdf/Figure_QGComp_Weights.pdf",
      "_tail/Figures/Figure_QGComp_Weights.pdf"
    ),
    paste0("Figure 8. QGC model weights of screened Environmental Toxicants on ", disease, ".pdf"))

  # FDR 配套图：复用主文 Figure 3/4/5/8 同款图面（WQS / BKMR overall / BKMR singvar / QGC）
  disease_fdr_fig <- gsub("_", " ", disease, fixed = TRUE)
  add_row(42L, "Figure", "Figure 9-FDR-WQS",
    paste0("Figure 9. WQS model weights with FDR tables (", disease_fdr_fig, "; full population)"),
    find_first(
      "Results_Summary/Figures/**/Figure 9. WQS model weights with FDR*.pdf",
      "Results_Summary/Figures/pdf/Figure 9. WQS model weights with FDR*.pdf",
      "Results_Summary/Figures/Figure 9. WQS model weights with FDR*.pdf"
    ),
    paste0("Figure 9. WQS model weights with FDR tables (", disease_fdr_fig, "; full population).pdf"))
  add_row(43L, "Figure", "Figure 10-FDR-BKMR-Overall",
    paste0("Figure 10. BKMR overall mixture effect with FDR tables (", disease_fdr_fig, "; full population)"),
    find_first(
      "Results_Summary/Figures/**/Figure 10. BKMR overall mixture effect with FDR*.pdf",
      "Results_Summary/Figures/pdf/Figure 10. BKMR overall mixture effect with FDR*.pdf",
      "Results_Summary/Figures/Figure 10. BKMR overall mixture effect with FDR*.pdf"
    ),
    paste0("Figure 10. BKMR overall mixture effect with FDR tables (", disease_fdr_fig, "; full population).pdf"))
  add_row(44L, "Figure", "Figure 11-FDR-BKMR-SingVar",
    paste0("Figure 11. BKMR single-variable effect with FDR tables (", disease_fdr_fig, "; full population)"),
    find_first(
      "Results_Summary/Figures/**/Figure 11. BKMR single-variable effect with FDR*.pdf",
      "Results_Summary/Figures/pdf/Figure 11. BKMR single-variable effect with FDR*.pdf",
      "Results_Summary/Figures/Figure 11. BKMR single-variable effect with FDR*.pdf"
    ),
    paste0("Figure 11. BKMR single-variable effect with FDR tables (", disease_fdr_fig, "; full population).pdf"))
  add_row(45L, "Figure", "Figure 12-FDR-QGC",
    paste0("Figure 12. QGC model weights with FDR tables (", disease_fdr_fig, "; full population)"),
    find_first(
      "Results_Summary/Figures/**/Figure 12. QGC model weights with FDR*.pdf",
      "Results_Summary/Figures/pdf/Figure 12. QGC model weights with FDR*.pdf",
      "Results_Summary/Figures/Figure 12. QGC model weights with FDR*.pdf"
    ),
    paste0("Figure 12. QGC model weights with FDR tables (", disease_fdr_fig, "; full population).pdf"))
  add_row(46L, "Figure", "Figure 13-FDR-BKMR-Dose",
    paste0("Figure 13. BKMR dose-response with FDR tables (", disease_fdr_fig, "; full population)"),
    find_first(
      "Results_Summary/Figures/**/Figure 13. BKMR dose-response with FDR*.pdf",
      "Results_Summary/Figures/pdf/Figure 13. BKMR dose-response with FDR*.pdf",
      "Results_Summary/Figures/Figure 13. BKMR dose-response with FDR*.pdf"
    ),
    paste0("Figure 13. BKMR dose-response with FDR tables (", disease_fdr_fig, "; full population).pdf"))

  add_row(41L, "Figure", "Figure 9A",
    "Figure 9A. Venn Plot",
    find_first("_tail/**/Figure 9A*.pdf", "Figures/Figure 9A*.pdf"),
    "Figure 9A. Venn Plot.pdf")

  voc_dirs <- list.dirs(file.path(result_root, "by_voc"), recursive = FALSE, full.names = FALSE)
  voc_dirs <- sort(voc_dirs[nzchar(voc_dirs)])
  for (i in seq_along(voc_dirs)) {
    voc <- voc_dirs[i]
    voc_lbl <- voc_label(voc)
    fig_title <- paste0("Figure 7. RCS plot between ", voc_lbl, " and ", disease)
    fig_file  <- paste0(fig_title, ".pdf")
    src <- find_first(
      paste0("by_voc/", voc, "/step22_rcs_nhanes/Figures/Figure 7-NHANES. RCS plot between ", voc, " and Female Infertility.pdf"),
      paste0("by_voc/", voc, "/Figures/pdf/Figure 1-NHANES. RCS plot between ", voc, " and Female Infertility.pdf"),
      paste0("by_voc/", voc, "/Figures/", fig_file),
      paste0("by_voc/", voc, "/*/Figures/Figure 7*.pdf"),
      paste0("by_voc/", voc, "/Figures/pdf/*.pdf")
    )
    add_row(37L + i, "Figure", paste0("Figure 7 (", voc, ")"), fig_title, src, fig_file)
  }

  med_figs <- list.files(
    result_root, pattern = "^Figure 9\\. Mediation plot for .+\\.pdf$",
    recursive = TRUE, full.names = TRUE
  )
  med_figs <- sort(med_figs[file.exists(med_figs)])
  for (i in seq_along(med_figs)) {
    bn <- basename(med_figs[i])
    add_row(50L + i, "Figure", paste0("Figure 9 (", i, ")"), bn, med_figs[i], bn)
  }

  manifest <- manifest[order(manifest$order, manifest$standard_id), , drop = FALSE]
  manifest_path <- file.path(out_root, "manifest.csv")
  utils::write.csv(manifest, manifest_path, row.names = FALSE, fileEncoding = "UTF-8")

  n_ok   <- sum(manifest$status == "copied")
  n_miss <- sum(manifest$status != "copied")

  list(
    result_root   = result_root,
    out_root      = out_root,
    dir_tables    = dir_tables,
    dir_figures   = dir_figs,
    manifest_path = manifest_path,
    manifest      = manifest,
    n_ok          = n_ok,
    n_total       = nrow(manifest),
    n_missing     = n_miss
  )
}

environment_batch_collect_results_summary <- function(config, root = NULL) {
  bc <- config$environment_batch %||% list()
  if (!isTRUE(bc$collect_results_summary %||% TRUE)) {
    cli::cli_alert_info("Results_Summary 汇总已关闭（environment_batch$collect_results_summary = FALSE）")
    return(invisible(NULL))
  }

  result_root <- bc$output_base %||% config$project$output_dir
  if (!nzchar(result_root)) {
    cli::cli_alert_warning("Results_Summary 汇总跳过：output_base 未配置")
    return(invisible(NULL))
  }
  result_root <- normalizePath(as.character(result_root)[1L], winslash = "/", mustWork = FALSE)

  disease <- as.character(config$project$disease %||% "DKD")[1L]
  proj_root <- root %||% bc$project_root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())

  fdr_src <- file.path(proj_root, "R/environment_sensitivity_fdr.R")
  if (file.exists(fdr_src) &&
      !exists("environment_build_full_population_fdr_table", mode = "function")) {
    tryCatch(source(fdr_src, local = FALSE), error = function(e) NULL)
  }
  if (exists("environment_build_full_population_fdr_table", mode = "function")) {
    tryCatch(
      environment_build_full_population_fdr_table(
        config = config,
        result_root = result_root,
        project_root = proj_root
      ),
      error = function(e) {
        cli::cli_alert_warning("全人群方法 FDR 表生成失败: {e$message}")
        NULL
      }
    )
  }
  if (exists("environment_build_sensitivity_method_fdr_tables", mode = "function")) {
    tryCatch(
      environment_build_sensitivity_method_fdr_tables(
        config = config,
        result_root = result_root,
        project_root = proj_root
      ),
      error = function(e) {
        cli::cli_alert_warning("敏感性方法 FDR 表生成失败: {e$message}")
        NULL
      }
    )
  }

  cli::cli_h2("Results_Summary 汇总")
  res <- tryCatch(
    environment_collect_dkd_results(
      result_root  = result_root,
      disease      = disease,
      project_root = proj_root
    ),
    error = function(e) {
      cli::cli_alert_danger("Results_Summary 汇总失败: {e$message}")
      NULL
    }
  )
  if (is.null(res)) return(invisible(NULL))

  # collect 若仍写出下划线病名 FDR 副本，收尾再清一次
  sum_tables <- file.path(result_root, "Results_Summary", "Tables")
  if (exists("environment_fdr_dedupe_underscore_twins", mode = "function")) {
    environment_fdr_dedupe_underscore_twins(sum_tables)
    sens_tables <- file.path(result_root, "Sensitivity", "Tables")
    if (dir.exists(sens_tables)) environment_fdr_dedupe_underscore_twins(sens_tables)
  }

  cli::cli_alert_success(
    "Results_Summary: {res$n_ok}/{res$n_total} 已复制 -> {.file {res$out_root}}"
  )
  if (res$n_missing > 0L) {
    miss <- res$manifest[res$manifest$status != "copied",
                         c("standard_id", "standard_name", "status")]
    cli::cli_alert_warning("缺失 {res$n_missing} 项（见 manifest.csv）")
    if (nrow(miss) <= 10L) {
      apply(miss, 1L, function(r) {
        cli::cli_alert_info("  {r[['standard_id']]}: {r[['status']]}")
      })
    }
  }
  cli::cli_alert_info("manifest: {.file {res$manifest_path}}")
  invisible(res)
}
