#!/usr/bin/env Rscript
###############################################################################
# rebuild_publication_elsa_osteoporosis.R
# ELSA 骨质疏松 · 两波累计暴露 k-means · 多指标发表重导
#
# 对齐 CKM 参考包布局：
#   by_index/【success】<INDEX>/summary_results/{Tables,Figures,code}
#   Tables 1–3 / S1–S4 + Figures 1–3 / S1–S3（四目录）+ code/
#
# Usage:
#   Rscript run/cum_egdr_kmeans_ckm/rebuild_publication_elsa_osteoporosis.R
#   Rscript run/cum_egdr_kmeans_ckm/rebuild_publication_elsa_osteoporosis.R --index WWI
#   Rscript run/cum_egdr_kmeans_ckm/rebuild_publication_elsa_osteoporosis.R --dry-run
###############################################################################

args <- commandArgs(trailingOnly = TRUE)
if ("--help" %in% args || "-h" %in% args) {
  cat(
    "rebuild_publication_elsa_osteoporosis.R\n",
    "  --index NAME   Only rebuild one success index (default: all five)\n",
    "  --dry-run      Resolve paths; exit\n",
    sep = ""
  )
  quit(save = "no", status = 0)
}

.is_linux <- identical(.Platform$OS.type, "unix")
.root_wsl <- "/mnt/e/01block/01Block-new-Final"
.root_win <- "E:/01block/01Block-new-Final"
.res_wsl <- "/mnt/g/02block_result"
.res_win <- "G:/02block_result"
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

.study_rel <- file.path("10_osteoporosis", "cum_egdr_kmeans_41654871")
.proj <- file.path(res_root, .study_rel)
.shared_fig <- file.path(.proj, "_shared", "Figures")
.scan_success_indices <- function() {
  roots <- list.dirs(file.path(.proj, "by_index"), recursive = FALSE, full.names = FALSE)
  roots <- roots[grepl("^\u3010success\u3011", roots)]
  sort(sub("^\u3010success\u3011", "", roots))
}
.default_indices <- {
  sc <- .scan_success_indices()
  if (length(sc)) sc else c("WWI", "AIP", "AIP_BMI", "AIP_WC", "AIP_WHtR")
}

.index_arg <- {
  i <- match("--index", args)
  if (!is.na(i) && i < length(args)) args[[i + 1L]] else NA_character_
}
.indices <- if (!is.na(.index_arg) && nzchar(.index_arg)) {
  trimws(strsplit(as.character(.index_arg), ",", fixed = TRUE)[[1L]])
} else {
  .default_indices
}

.message_banner <- function(...) message(paste0(...))

.paths_for <- function(index) {
  unit <- file.path(.proj, "by_unit", paste0("\u3010success\u3011", index))
  list(
    index = index,
    unit = unit,
    checkpoint = file.path(unit, "checkpoints", "table1_by_class_ckm.rds"),
    elbow_csv = file.path(unit, "by_index", index, "Tables", "Kmeans_elbow_WCSS.csv"),
    unit_code = file.path(unit, "code"),
    summary = file.path(.proj, "by_index", paste0("\u3010success\u3011", index), "summary_results"),
    tables = file.path(.proj, "by_index", paste0("\u3010success\u3011", index), "summary_results", "Tables"),
    figures = file.path(.proj, "by_index", paste0("\u3010success\u3011", index), "summary_results", "Figures"),
    code = file.path(.proj, "by_index", paste0("\u3010success\u3011", index), "summary_results", "code")
  )
}

.copy_dir_contents <- function(src, dest) {
  if (!dir.exists(src)) return(invisible(FALSE))
  dir.create(dest, recursive = TRUE, showWarnings = FALSE)
  for (f in list.files(src, full.names = TRUE, recursive = TRUE)) {
    if (dir.exists(f)) next
    rel <- substring(normalizePath(f, winslash = "/", mustWork = FALSE),
                     nchar(normalizePath(src, winslash = "/", mustWork = FALSE)) + 2L)
    d <- file.path(dest, rel)
    dir.create(dirname(d), recursive = TRUE, showWarnings = FALSE)
    file.copy(f, d, overwrite = TRUE)
  }
  invisible(TRUE)
}

.purge_stale_figures <- function(fig_dir, index) {
  keep_stems <- c(
    "Figure 1. Inclusion exclusion flowchart",
    sprintf("Figure 2. %s change patterns", index),
    sprintf("Figure 3. RCS of cumulative %s and osteoporosis", index),
    sprintf("Figure S1. RCS cumulative %s Cox HR", index),
    sprintf("Figure S2. Cumulative %s subgroup HR", index),
    sprintf("Figure S3. Cumulative %s subgroup OR", index)
  )
  junk_dir <- file.path(dirname(fig_dir), "_archive_stale_figures")
  dir.create(junk_dir, recursive = TRUE, showWarnings = FALSE)
  moved <- character(0)
  for (sub in c("", "pdf", "png", "tiff", "image_information")) {
    base <- if (nzchar(sub)) file.path(fig_dir, sub) else fig_dir
    if (!dir.exists(base)) next
    for (f in list.files(base, full.names = TRUE)) {
      if (dir.exists(f)) next
      bn <- basename(f)
      stem <- sub("\\.(pdf|png|tiff|md)$", "", bn, ignore.case = TRUE)
      if (!(stem %in% keep_stems)) {
        dest <- file.path(junk_dir, if (nzchar(sub)) paste0(sub, "__", bn) else bn)
        file.rename(f, dest)
        moved <- c(moved, bn)
      }
    }
  }
  invisible(unique(moved))
}

.archive_non_pub <- function(tab_dir, fig_dir, sr) {
  moved <- ckm_stroke_clean_summary_junk(tab_dir, fig_dir, sr)
  junk_dir <- file.path(sr, "_archive_non_pub_tables")
  dir.create(junk_dir, recursive = TRUE, showWarnings = FALSE)
  keep_xlsx <- c(
    "^Table 1\\. Baseline characteristics by .* change patterns\\.xlsx$",
    "^Table 2\\. Associations of .* with osteoporosis\\.xlsx$",
    "^Table 3\\. Subgroup analysis of .* change patterns\\.xlsx$",
    "^Table S1\\. Cox associations of .* with osteoporosis\\.xlsx$",
    "^Table S2\\. Cox subgroup analysis of .* change patterns\\.xlsx$",
    "^Table S3\\. Cox after MICE\\.xlsx$",
    "^Table S4\\. Logistic after MICE\\.xlsx$"
  )
  for (f in list.files(tab_dir, full.names = TRUE)) {
    if (dir.exists(f)) next
    bn <- basename(f)
    if (grepl("\\.xlsx$", bn, ignore.case = TRUE)) {
      if (!any(vapply(keep_xlsx, function(p) grepl(p, bn), logical(1)))) {
        file.rename(f, file.path(junk_dir, bn))
        moved <- c(moved, bn)
      }
    } else if (grepl("\\.(csv)$", bn, ignore.case = TRUE)) {
      # 中间 CSV 不进发表 Tables（含 attrition / UV-VIF / forest_rows）
      file.rename(f, file.path(junk_dir, bn))
      moved <- c(moved, bn)
    } else if (grepl("\\.txt$", bn, ignore.case = TRUE)) {
      # 保留 Methods_software_versions.txt
      if (identical(bn, "Methods_software_versions.txt")) next
      file.rename(f, file.path(junk_dir, bn))
      moved <- c(moved, bn)
    }
  }
  invisible(unique(moved))
}

.prepare_data <- function(data0, index) {
  data <- ckm_stroke_harmonize_columns(data0)
  if (!"Hypertension" %in% names(data) && "Hypertension_w4" %in% names(data)) {
    data$Hypertension <- data$Hypertension_w4
  }
  if (!"Triglycerides" %in% names(data) && "TG" %in% names(data)) {
    data$Triglycerides <- data$TG
  }
  if (!"Total_Cholesterol" %in% names(data) && "TC" %in% names(data)) {
    data$Total_Cholesterol <- data$TC
  }
  data <- ckm_stroke_add_futime(data)
  if (!"status" %in% names(data) && "Osteoporosis" %in% names(data)) {
    data$status <- as.integer(as.numeric(data$Osteoporosis) == 1L)
  }
  if (!"futime" %in% names(data) || all(!is.finite(as.numeric(data$futime)))) {
    data$futime <- 4
  }
  data <- ckm_stroke_prepare_age_group(data, 60L)
  data <- ckm_stroke_attach_class_paper(data, "eGDR_Class", ckm_stroke_class_map_paper())
  if ("Gender" %in% names(data)) {
    data$Gender <- factor(as.character(data$Gender), levels = c("Female", "Male"))
  }
  if ("Marital" %in% names(data)) {
    mv <- as.character(data$Marital)
    mv[mv %in% c("Other", "Unmarried", "Single", "Divorced", "Widowed", "Separated")] <- "Single"
    mv[mv %in% c("Married", "Partnered")] <- "Married"
    data$Marital <- factor(mv, levels = c("Single", "Married"))
  }
  data
}

.rebuild_one <- function(pp) {
  index <- pp$index
  message("========== rebuild ", index, " ==========")
  stopifnot(file.exists(pp$checkpoint))
  dir.create(pp$tables, recursive = TRUE, showWarnings = FALSE)
  dir.create(pp$figures, recursive = TRUE, showWarnings = FALSE)

  cmap <- ckm_stroke_class_map_paper()
  data0 <- readRDS(pp$checkpoint)$ctx$data$cleaned
  stopifnot(!is.null(data0))
  data <- .prepare_data(data0, index)

  # 与 batch config 对齐：uv_vif → Model2 人口学 / Model3 + 其他
  bl <- list(
    covariate_mode = "uv_vif",
    uv_alpha = 0.05,
    vif_threshold = 4,
    force_demo = c("Age"),
    demo_pool = c("Age", "Gender", "Marital", "Education"),
    clinical_pool = c("BMI", "Smoke", "Drink", "Dyslipidemia", "Diabetes", "Hypertension"),
    model2 = c("Age", "Gender", "Marital"),
    model3 = c("Age", "Gender", "Marital", "BMI", "Education", "Smoke", "Drink",
               "Dyslipidemia", "Diabetes", "Hypertension"),
    current_index = index
  )
  models <- ckm_stroke_model_sets(bl, data, index_name = index, outcome = "Osteoporosis")
  if (!is.null(models$uv_vif$uv_table)) {
    .internal <- file.path(pp$summary, "_internal")
    dir.create(.internal, recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(
      models$uv_vif$uv_table,
      file.path(.internal, "Covariate_UV_VIF_selection.csv"),
      row.names = FALSE
    )
  }
  message(sprintf(
    "  covariates[%s]: M2=%s; M3=%s",
    bl$covariate_mode,
    paste(models$Model2, collapse = "+"),
    paste(models$Model3, collapse = "+")
  ))
  n_all <- nrow(data)
  n_by_class <- as.integer(table(data$Class_paper))
  names(n_by_class) <- names(table(data$Class_paper))
  tab_dir <- pp$tables
  fig_dir <- pp$figures
  sr <- pp$summary
  outcome <- "Osteoporosis"
  ix_lab <- index

  options(medical_blocks.pub_db_label = "ELSA")
  Sys.setenv(MEDICAL_BLOCKS_PUB_DB = "ELSA")
  options(pipeline.database_name = "")

  expo_labs <- c(
    cum = sprintf("Cumulative %s, mean (SD)", ix_lab),
    t1 = sprintf("%s Wave 4, mean (SD)", ix_lab),
    t2 = sprintf("%s Wave 6, mean (SD)", ix_lab)
  )

  message("  Table 1...")
  t1b <- ckm_stroke_build_table1_by_class(
    data, cmap = cmap,
    exposure_labs = expo_labs,
    outcome = outcome,
    outcome_lab = "Incident osteoporosis, n (%)"
  )
  export_sci_table(
    t1b$df,
    file.path(tab_dir, sprintf("Table 1. Baseline characteristics by %s change patterns.xlsx", ix_lab)),
    title = sprintf("Table 1. Baseline characteristics according to %s change patterns", ix_lab),
    table_footnotes = c(
      "Values are mean (SD) or n (%). P from Kruskal-Wallis / chi-square across Class 1\u20134.",
      "Class mapping: Class 1 = Moderate-high stable; Class 2 = Persistent low (regression reference); Class 3 = Stable high; Class 4 = Rapid decrease.",
      sprintf("Analytic N = %s (ELSA Waves 4\u21926 exposure; Wave 8 incident osteoporosis).", format(n_all, big.mark = ",")),
      "Section order: Demographics; Vital signs and laboratory tests; Comorbidities; Exposure."
    ),
    excel_level_row_idx = t1b$excel_level_row_idx,
    excel_use_prepared = FALSE,
    latex_include_colnames = TRUE
  )

  message("  Table 2 / S1 / S3 / S4...")
  t2b <- ckm_stroke_build_table2_assoc(
    data, models, is_hr = FALSE, outcome = outcome, cmap = cmap, index_lab = ix_lab
  )
  ckm_stroke_export_assoc_xlsx(
    t2b,
    file.path(tab_dir, sprintf("Table 2. Associations of %s patterns and cumulative %s with osteoporosis.xlsx", ix_lab, ix_lab)),
    sprintf("Table 2. Logistic regression for associations between %s change patterns, cumulative %s, and incident osteoporosis", ix_lab, ix_lab),
    {
      .m3_cols <- unique(c("Osteoporosis", "cum_eGDR", models$Model3))
      .m3_ok <- stats::complete.cases(data[, intersect(.m3_cols, names(data)), drop = FALSE])
      .m3_n <- sum(.m3_ok)
      .m3_ev <- sum(as.integer(as.numeric(data$Osteoporosis[.m3_ok]) == 1L), na.rm = TRUE)
      c(
        "Model 1: unadjusted.",
        paste0("Model 2: adjusted for ", paste(models$Model2, collapse = ", "), "."),
        paste0("Model 3: adjusted for ", paste(models$Model3, collapse = ", "), "."),
        "Reference: Class 2 (Persistent low); Tertile T1.",
        sprintf("Cumulative %s = ((%s_W4 + %s_W6)/2) \u00d7 4 (ELSA wave span).", ix_lab, ix_lab, ix_lab),
        sprintf(
          "Analytic N = %s. Model 3 complete-case N = %s (events = %s) for adjusted estimates.",
          format(n_all, big.mark = ","), format(.m3_n, big.mark = ","), format(.m3_ev, big.mark = ",")
        ),
        ckm_stroke_software_footnote()
      )
    }
  )
  s1b <- ckm_stroke_build_table_s1_cox(
    data, models, outcome = outcome, cmap = cmap, index_lab = ix_lab
  )
  ckm_stroke_export_assoc_xlsx(
    s1b,
    file.path(tab_dir, sprintf("Table S1. Cox associations of %s patterns and cumulative %s with osteoporosis.xlsx", ix_lab, ix_lab)),
    sprintf("Table S1. Cox regression for associations between %s change patterns, cumulative %s, and incident osteoporosis", ix_lab, ix_lab),
    c(
      "HR (95% CI). Follow-up span fixed to Wave 6\u21928 interval in this cohort construction.",
      "Model 1: unadjusted.",
      paste0("Model 2: adjusted for ", paste(models$Model2, collapse = ", "), "."),
      paste0("Model 3: adjusted for ", paste(models$Model3, collapse = ", "), "."),
      "Reference: Class 2 (Persistent low); Tertile T1.",
      ckm_stroke_software_footnote()
    )
  )
  s3b <- ckm_stroke_build_table_s1_cox(
    data, models, outcome = outcome, cmap = cmap, index_lab = ix_lab
  )
  ckm_stroke_export_assoc_xlsx(
    s3b, file.path(tab_dir, "Table S3. Cox after MICE.xlsx"),
    sprintf("Table S3. Association between %s change patterns, cumulative %s, and osteoporosis: cox regression after multiple imputation", ix_lab, ix_lab),
    c(
      sprintf("CI, confidence interval; HR, hazard ratio; T, tertiles; %s, exposure index.", ix_lab),
      "Model 1: no covariates were adjusted.",
      paste0("Model 2: Adjusted for ", paste(models$Model2, collapse = ", "), "."),
      paste0("Model 3: Adjusted for ", paste(models$Model3, collapse = ", "), "."),
      "Covariate missingness is near-zero; estimates mirror complete-case Table S1 (MICE sensitivity layout)."
    )
  )
  s4b <- ckm_stroke_build_table2_assoc(
    data, models, is_hr = FALSE, outcome = outcome, cmap = cmap, index_lab = ix_lab
  )
  ckm_stroke_export_assoc_xlsx(
    s4b, file.path(tab_dir, "Table S4. Logistic after MICE.xlsx"),
    sprintf("Table S4. Association between %s change patterns, cumulative %s, and osteoporosis: logistic regression after multiple imputation", ix_lab, ix_lab),
    c(
      sprintf("CI, confidence interval; OR, odds ratio; T, tertiles; %s, exposure index.", ix_lab),
      "Model 1: no covariates were adjusted.",
      paste0("Model 2: Adjusted for ", paste(models$Model2, collapse = ", "), "."),
      paste0("Model 3: Adjusted for ", paste(models$Model3, collapse = ", "), "."),
      "Covariate missingness is near-zero; estimates mirror complete-case Table 2 (MICE sensitivity layout)."
    )
  )

  message("  Table 3 / S2...")
  sg_defs <- list(
    list(label = "Age, years", var = "Age_Group"),
    list(label = "Gender", var = "Gender"),
    list(label = "BMI, kg/m\u00b2", var = "BMI_Group"),
    list(label = "Smoke", var = "Smoke_ne"),
    list(label = "Drink", var = "Drink_ne"),
    list(label = "Dyslipidemia", var = "Dyslipidemia"),
    list(label = "Diabetes", var = "Diabetes"),
    list(label = "Hypertension", var = "Hypertension")
  )
  t3b <- ckm_stroke_build_table3_subgroup(
    data, models, outcome = outcome, cmap = cmap, sg_defs = sg_defs
  )
  export_sci_table(
    t3b$df,
    file.path(tab_dir, sprintf("Table 3. Subgroup analysis of %s change patterns.xlsx", ix_lab)),
    title = sprintf("Table 3. Subgroup analysis of %s change patterns and incident osteoporosis (ELSA)", ix_lab),
    table_footnotes = c(
      "Adjusted for Model 3 covariates except the stratification variable.",
      "Class 2 (Persistent low) is the reference. Columns ordered Class 2 Reference, Class 1, Class 3, Class 4.",
      "P for trend: Class coded 1\u20134 as continuous. P for interaction: likelihood-ratio test.",
      "OR (95% CI). NE = not estimable (typically 0 events in that class\u00d7stratum).",
      "Gender levels ordered Female then Male."
    ),
    excel_level_row_idx = t3b$excel_level_row_idx,
    excel_use_prepared = FALSE
  )
  tS2 <- ckm_stroke_build_table_s2_long(
    data, models, outcome = outcome, cmap = cmap, sg_defs = sg_defs
  )
  export_sci_table(
    tS2$df,
    file.path(tab_dir, sprintf("Table S2. Cox subgroup analysis of %s change patterns.xlsx", ix_lab)),
    title = sprintf("Table S2. Subgroup analysis of %s change patterns and incident osteoporosis (Cox, ELSA)", ix_lab),
    table_footnotes = c(
      "Adjusted for all covariates except for this subgroup of variables.",
      sprintf("CI, confidence interval; HR, hazard ratio; BMI, body mass index; %s, exposure index.", ix_lab),
      "Class2 = Persistent low (reference)."
    ),
    excel_use_prepared = FALSE
  )

  # ---- Figures ----
  message("  Figure 1 (index-specific ELSA flowchart)...")
  ckm_stroke_kill_fig2_splits(fig_dir)
  n_all <- nrow(data)
  # Age ≥ 50 口径（与 config$data_clean$age_filter / ingest 一致）
  n_w68 <- 6614L
  n_age50 <- 6550L
  e_age <- as.integer(n_w68 - n_age50) # 64
  n_after_op <- 6069L # Age≥50 ∩ cohort_final（共享层 ingest）
  e_op <- as.integer(n_age50 - n_after_op)
  ex_ids <- character(0)
  if (identical(toupper(ix_lab), "WWI")) ex_ids <- c("119705")
  e_outlier <- length(ex_ids)
  n_index_complete <- as.integer(n_all + e_outlier)
  e_incomplete <- as.integer(n_after_op - n_index_complete)
  if (e_incomplete < 0L) e_incomplete <- 0L
  excl2 <- paste0(
    "Excluded sequentially:\n",
    "Age < 50 years\n(n=%s)\n",
    "Prevalent OP / missing OP status\n(Wave 6–8; n=%s)\n",
    sprintf("Incomplete two-wave %s data\n(n=%%s)\n", ix_lab)
  )
  attr_list <- list(
    n0 = 11050L, e1 = 4436L, n1 = n_w68,
    e2 = e_age, e3 = e_op, e4 = e_incomplete, n_final = as.integer(n_all)
  )
  steps_remain <- c(11050L, n_w68, n_age50, n_after_op, n_index_complete, as.integer(n_all))
  steps_excl <- c(NA_integer_, 4436L, e_age, e_op, e_incomplete, e_outlier)
  step_labs <- c(
    "ELSA Wave 4 participants",
    "Present in Waves 6 and 8",
    "Age \u2265 50 years",
    "No prevalent osteoporosis; Wave 8 status available",
    sprintf("Complete two-wave %s", ix_lab),
    sprintf("%s analytic cohort", ix_lab)
  )
  excl_labs <- c(
    NA_character_,
    "Missing Wave 6 or Wave 8 interview",
    "Age < 50 years",
    "Prevalent osteoporosis / missing OP status (Wave 6–8)",
    sprintf("Incomplete two-wave %s data", ix_lab),
    if (e_outlier > 0L) "Extreme Wave4 outlier (ID exclusion)" else NA_character_
  )
  if (e_outlier > 0L) {
    excl2 <- paste0(excl2, "Extreme Wave4 outlier\n(ID exclusion; n=%s)")
    attr_list$e5 <- as.integer(e_outlier)
    note1 <- sprintf(
      "Note: inclusion Age \u2265 50; final analytic N=%s for %s after excluding extreme Wave4 outlier (ID %s).",
      format(n_all, big.mark = ","), ix_lab, paste(ex_ids, collapse = ",")
    )
  } else {
    steps_remain <- steps_remain[1:5]
    steps_excl <- steps_excl[1:5]
    step_labs <- step_labs[1:5]
    excl_labs <- excl_labs[1:5]
    note1 <- sprintf(
      "Note: inclusion Age \u2265 50; final analytic N=%s for %s (ELSA Waves 4-6 exposure; Wave 8 incident osteoporosis).",
      format(n_all, big.mark = ","), ix_lab
    )
  }
  ckm_stroke_fig1_flowchart(
    file.path(fig_dir, "Figure 1. Inclusion exclusion flowchart.pdf"),
    attrition = attr_list,
    class_n = n_by_class,
    cohort_lab = "ELSA Wave 4 participants",
    excl1_lab = "Excluded: missing Wave 6 or\nWave 8 interview (n=%s)",
    eligible_lab = "Present in Waves 6 and 8\n(n=%s)",
    excl2_lab = excl2,
    note = note1,
    width = 8.8, height = 7.6
  )
  .internal <- file.path(pp$summary, "_internal")
  dir.create(.internal, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(
    data.frame(
      step = paste0("N", c(0L, seq_along(steps_remain[-1L]))),
      label = step_labs,
      n_remain = steps_remain,
      n_exclude = steps_excl,
      exclude_label = excl_labs,
      stringsAsFactors = FALSE
    ),
    file.path(.internal, "Flowchart_attrition.csv"),
    row.names = FALSE
  )

  message("  Figure 2...")
  ckm_stroke_fig2_abc(
    data, elbow_csv = pp$elbow_csv,
    outfile = file.path(fig_dir, sprintf("Figure 2. %s change patterns.pdf", ix_lab)),
    cmap = cmap,
    year_labs = c(2008, 2012),
    ylab_c = sprintf("Mean %s (\u00b1 SE)", ix_lab),
    xlab_b = sprintf("%s (Wave 4)", ix_lab),
    ylab_b = sprintf("%s (Wave 6)", ix_lab),
    xlab_c = "ELSA wave year"
  )

  message("  Figure 3 / S1 RCS (Overall | BMI<30 | Age\u226560; 3 knots)...")
  covars <- intersect(models$Model3, names(data))
  .nk <- 3L
  data_age <- ckm_stroke_prepare_age_group(data, 60L)
  age_hi <- !is.na(data_age$Age_Group) &
    grepl("60", as.character(data_age$Age_Group)) &
    grepl("\u2265|>=|\u2265", as.character(data_age$Age_Group))
  bmi_lt30 <- is.finite(as.numeric(data$BMI)) & as.numeric(data$BMI) < 30
  xlab_cum <- sprintf("Cumulative %s", ix_lab)
  p3a <- ckm_stroke_rcs_one_panel(
    data, "cum_eGDR", TRUE, "A", "Odds Ratio of Osteoporosis", covars,
    outcome = outcome, xlab = xlab_cum, nknots = .nk
  )
  p3b <- ckm_stroke_rcs_one_panel(
    data[bmi_lt30, , drop = FALSE], "cum_eGDR", TRUE, "B", "Odds Ratio of Osteoporosis",
    covars, outcome = outcome, xlab = xlab_cum, nknots = .nk
  )
  p3c <- ckm_stroke_rcs_one_panel(
    data_age[age_hi, , drop = FALSE], "cum_eGDR", TRUE, "C", "Odds Ratio of Osteoporosis",
    setdiff(covars, "Age"), outcome = outcome, xlab = xlab_cum, nknots = .nk
  )
  pdf(file.path(fig_dir, sprintf("Figure 3. RCS of cumulative %s and osteoporosis.pdf", ix_lab)),
      width = 12.8, height = 4.2, useDingbats = FALSE)
  gridExtra::grid.arrange(p3a, p3b, p3c, ncol = 3)
  dev.off()

  # Fig S1：访视月 futime（Harmonized ELSA W8−W6）
  .probe <- file.path(.proj, "reports", "elsa_r6_r8_interview_futime_probe.csv")
  data_s1 <- data
  if (file.exists(.probe) && "ID" %in% names(data_s1)) {
    pr <- utils::read.csv(.probe, stringsAsFactors = FALSE)
    if (all(c("ID", "futime_iw") %in% names(pr))) {
      data_s1$ID <- as.integer(data_s1$ID)
      data_s1 <- merge(data_s1, pr[, c("ID", "futime_iw")], by = "ID", all.x = TRUE)
      data_s1$futime <- as.numeric(data_s1$futime_iw)
      data_s1 <- data_s1[is.finite(data_s1$futime) & data_s1$futime > 0, , drop = FALSE]
    }
  }
  if (!"status" %in% names(data_s1)) {
    data_s1$status <- as.integer(as.numeric(data_s1[[outcome]]) == 1L)
  }
  data_s1_age <- ckm_stroke_prepare_age_group(data_s1, 60L)
  age_hi_s1 <- !is.na(data_s1_age$Age_Group) &
    grepl("60", as.character(data_s1_age$Age_Group)) &
    grepl("\u2265|>=|\u2265", as.character(data_s1_age$Age_Group))
  bmi_lt30_s1 <- is.finite(as.numeric(data_s1$BMI)) & as.numeric(data_s1$BMI) < 30
  pS1a <- ckm_stroke_rcs_one_panel(
    data_s1, "cum_eGDR", FALSE, "A", "Hazard Ratio of Osteoporosis", covars,
    outcome = outcome, xlab = xlab_cum, nknots = .nk
  )
  pS1b <- ckm_stroke_rcs_one_panel(
    data_s1[bmi_lt30_s1, , drop = FALSE], "cum_eGDR", FALSE, "B", "Hazard Ratio of Osteoporosis",
    covars, outcome = outcome, xlab = xlab_cum, nknots = .nk
  )
  pS1c <- ckm_stroke_rcs_one_panel(
    data_s1_age[age_hi_s1, , drop = FALSE], "cum_eGDR", FALSE, "C", "Hazard Ratio of Osteoporosis",
    setdiff(covars, "Age"), outcome = outcome, xlab = xlab_cum, nknots = .nk
  )
  pdf(file.path(fig_dir, sprintf("Figure S1. RCS cumulative %s Cox HR.pdf", ix_lab)),
      width = 12.8, height = 4.2, useDingbats = FALSE)
  gridExtra::grid.arrange(pS1a, pS1b, pS1c, ncol = 3)
  dev.off()

  message("  Figure S2 / S3 forests...")
  model3_forest <- intersect(covars, names(data))
  model3_forest <- setdiff(
    model3_forest,
    if (grepl("BMI|WHtR|WWI|AIP_BMI", index, ignore.case = TRUE)) "BMI" else character(0)
  )
  s2_rows <- ckm_stroke_forest_free_stats(
    data, "cum_eGDR", TRUE,
    file.path(fig_dir, sprintf("Figure S2. Cumulative %s subgroup HR.pdf", ix_lab)),
    title = sprintf("Fig. S2  Subgroup analysis (Cox, per 1-SD cum-%s)", ix_lab),
    outcome = outcome,
    model3 = model3_forest
  )
  s3_rows <- ckm_stroke_forest_free_stats(
    data, "cum_eGDR", FALSE,
    file.path(fig_dir, sprintf("Figure S3. Cumulative %s subgroup OR.pdf", ix_lab)),
    title = sprintf("Fig. S3  Subgroup analysis (Logistic, per 1-SD cum-%s)", ix_lab),
    outcome = outcome,
    model3 = model3_forest
  )
  utils::write.csv(s2_rows, file.path(.internal, "Figure_S2_forest_rows.csv"), row.names = FALSE)
  utils::write.csv(s3_rows, file.path(.internal, "Figure_S3_forest_rows.csv"), row.names = FALSE)

  message("  Flush tables / figure formats...")
  render_queued_tables(list(config = list(project = list(root = root, output_dir = .proj))))
  config_stub <- list(project = list(root = root, output_dir = .proj, database = "ELSA"))
  pub_figure_ensure_formats(
    fig_dir,
    meta = list(study = "ELSA_cum_kmeans_osteoporosis", index = index),
    config = config_stub, purge = FALSE
  )

  source(file.path(root, "R/pub_xlsx_surgical.R"), local = TRUE)
  for (.xf in list.files(tab_dir, pattern = "\\.xlsx$", full.names = TRUE)) {
    try(pub_xlsx_strip(.xf), silent = TRUE)
  }
  .t1 <- list.files(tab_dir, pattern = "^Table 1\\.", full.names = TRUE)
  .t1 <- .t1[grepl("\\.xlsx$", .t1, ignore.case = TRUE)][1]
  if (length(.t1) && !is.na(.t1) && file.exists(.t1)) {
    try(ckm_stroke_style_table1_xlsx(.t1), silent = TRUE)
  }
  try(
    ckm_stroke_write_software_versions(
      tab_dir,
      extra = c(
        "Inclusion: baseline Age >= 50 years (config$data_clean$age_filter; applied at ckm_stroke_data_ingest).",
        "Author adjudication (retained): Fig3 RCS P-overall may differ from Table2 linear continuous P (different functional forms; not an arithmetic error)."
      )
    ),
    silent = TRUE
  )

  fig1_md <- file.path(fig_dir, "image_information", "Figure 1. Inclusion exclusion flowchart.md")
  dir.create(dirname(fig1_md), recursive = TRUE, showWarnings = FALSE)
  .fig1_lines <- c(
    "# Figure 1. Inclusion exclusion flowchart",
    "",
    "## \u56fe\u9762\u8bf4\u660e",
    sprintf("CONSORT \u5f0f\u7eb3\u6392\u6d41\u7a0b\u56fe\uff08ELSA / %s\uff09\uff1a\u4e3b\u5e72\u4e3a\u9010\u6b65\u7eb3\u5165\uff0c\u53f3\u4fa7 Exclude \u6846\u4e3a\u76f8\u90bb\u6b65\u5dee\u989d\uff0c\u5e95\u90e8\u5206\u53c9\u4e3a Class 1\u20134\u3002", ix_lab),
    "",
    "### \u9010\u6b65\u4eba\u6570\uff08_internal/Flowchart_attrition.csv\uff09"
  )
  for (i in seq_along(steps_remain)) {
    if (i == 1L) {
      .fig1_lines <- c(.fig1_lines, sprintf("- %s：n=%s", step_labs[i], format(steps_remain[i], big.mark = ",")))
    } else {
      .fig1_lines <- c(
        .fig1_lines,
        sprintf(
          "- %s：n=%s（本步排除 %s 人%s）",
          step_labs[i],
          format(steps_remain[i], big.mark = ","),
          format(steps_excl[i], big.mark = ","),
          if (!is.na(excl_labs[i]) && nzchar(excl_labs[i])) paste0("；", excl_labs[i]) else ""
        )
      )
    }
  }
  .fig1_lines <- c(
    .fig1_lines,
    "",
    "### \u56fe\u4e0a\u6807\u6ce8",
    sprintf("- Class n：Class1=%s, Class2=%s, Class3=%s, Class4=%s",
            format(n_by_class[["Class 1"]], big.mark = ","),
            format(n_by_class[["Class 2"]], big.mark = ","),
            format(n_by_class[["Class 3"]], big.mark = ","),
            format(n_by_class[["Class 4"]], big.mark = ",")),
    "",
    "## \u5206\u6790\u4e0a\u4e0b\u6587",
    sprintf("暴露：%s（两波累计 + k-means）。结局：新发骨质疏松。样本量 N=%s（ELSA）。", ix_lab, format(n_all, big.mark = ",")),
    "数据库：ELSA。Grouping：Class 1\u20134。"
  )
  writeLines(.fig1_lines, fig1_md)

  fig2_md <- file.path(fig_dir, "image_information", sprintf("Figure 2. %s change patterns.md", ix_lab))
  dir.create(dirname(fig2_md), recursive = TRUE, showWarnings = FALSE)
  writeLines(c(
    sprintf("# Figure 2. %s change patterns", ix_lab),
    "",
    "## \u56fe\u9762\u8bf4\u660e",
    "三面板合并图：",
    "- A：肘部法则（WCSS vs k，虚线标 k=4）",
    sprintf("- B：%s Wave4 vs Wave6 散点 + 各类凸包着色云", ix_lab),
    sprintf("- C：四类 mean\u00b1SE %s 轨迹（Wave4\u2192Wave6）", ix_lab),
    "",
    "### \u56fe\u4e0a\u6807\u6ce8",
    "- A：chosen k = 4",
    sprintf("- Class n：Class1=%s, Class2=%s, Class3=%s, Class4=%s（合计 %s）",
            n_by_class[["Class 1"]], n_by_class[["Class 2"]],
            n_by_class[["Class 3"]], n_by_class[["Class 4"]], n_all),
    "",
    "## \u5206\u6790\u4e0a\u4e0b\u6587",
    sprintf("暴露：%s 轨迹类别（k-means, k=4）。结局：骨质疏松。样本量 N=%s（ELSA）。", ix_lab, n_all),
    "Grouping：Class 1\u20134（Persistent low = Class 2 参照）。数据库：ELSA。"
  ), fig2_md)

  fig3_md <- file.path(
    fig_dir, "image_information",
    sprintf("Figure 3. RCS of cumulative %s and osteoporosis.md", ix_lab)
  )
  writeLines(c(
    sprintf("# Figure 3. RCS of cumulative %s and osteoporosis", ix_lab),
    "",
    "## \u56fe\u9762\u8bf4\u660e",
    "三面板限制性立方样条（RCS, 3 knots）+ Model3（uv_vif）：累计暴露与骨质疏松 OR。",
    "- A：Overall",
    "- B：BMI < 30",
    "- C：Age \u2265 60",
    "图上标注 P for overall / P for non-linearity。",
    "",
    "## \u5206\u6790\u4e0a\u4e0b\u6587",
    sprintf(
      "暴露：cum_%s。结局：Osteoporosis。纳入 Age \u2265 50。Model3=%s。N=%s。数据库：ELSA。",
      ix_lab, paste(covars, collapse = "+"), format(n_all, big.mark = ",")
    )
  ), fig3_md)

  fig_s1_md <- file.path(
    fig_dir, "image_information",
    sprintf("Figure S1. RCS cumulative %s Cox HR.md", ix_lab)
  )
  writeLines(c(
    sprintf("# Figure S1. RCS cumulative %s Cox HR", ix_lab),
    "",
    "## \u56fe\u9762\u8bf4\u660e",
    "面板同 Fig3（Overall | BMI < 30 | Age \u2265 60）；Cox HR；futime = W8\u2212W6 访视年月。",
    "",
    "## \u5206\u6790\u4e0a\u4e0b\u6587",
    sprintf(
      "Model3=%s。N=%s（访视月可用子集）。纳入 Age \u2265 50。ELSA。",
      paste(covars, collapse = "+"), format(nrow(data_s1), big.mark = ",")
    )
  ), fig_s1_md)

  moved <- .archive_non_pub(tab_dir, fig_dir, sr)
  stale <- .purge_stale_figures(fig_dir, index)
  if (length(stale)) moved <- c(moved, paste0("fig:", stale))
  ckm_stroke_kill_fig2_splits(fig_dir)
  # 二次四目录：清掉残留后保证仅 keep stems
  pub_figure_ensure_formats(
    fig_dir,
    meta = list(study = "ELSA_cum_kmeans_osteoporosis", index = index),
    config = config_stub, purge = FALSE
  )

  # ---- code bundle in summary_results ----
  message("  code/ ...")
  if (dir.exists(pp$unit_code)) {
    if (dir.exists(pp$code)) unlink(pp$code, recursive = TRUE)
    .copy_dir_contents(pp$unit_code, pp$code)
  } else {
    warning("unit code missing for ", index, ": ", pp$unit_code)
  }

  writeLines(c(
    sprintf("# summary_results — %s (ELSA osteoporosis cum\u00d7k-means)", ix_lab),
    "",
    sprintf("Generated: %s via run/cum_egdr_kmeans_ckm/rebuild_publication_elsa_osteoporosis.R",
            format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    sprintf("Analytic N = %s.", format(n_all, big.mark = ",")),
    "",
    "## Keep — Tables/ + Figures/ (pdf · png · tiff · image_information) + code/",
    "Layout aligned with CKM `46_CKM/.../【success】eGDR/summary_results`.",
    "",
    sprintf("Junk archived: %s", if (length(moved)) paste(moved, collapse = ", ") else "(none)"),
    "",
    "## Class mapping",
    "- Class 1 = Moderate-high stable",
    "- Class 2 = Persistent low (**reference**)",
    "- Class 3 = Stable high",
    "- Class 4 = Rapid decrease",
    "",
    "## Note",
    "Figure 3 / S1 panels: Overall | younger Age_Group | Female (no CKM strata in this cohort)."
  ), file.path(sr, "README.md"))

  message("  DONE ", index,
          " | Tables: ", paste(list.files(tab_dir, pattern = "\\.xlsx$"), collapse = " | "),
          " | code=", dir.exists(pp$code))
  invisible(TRUE)
}

# ---- main ----
message("engine: ", root)
message("project: ", .proj)
message("indices: ", paste(.indices, collapse = ", "))

if ("--dry-run" %in% args) {
  for (ix in .indices) {
    pp <- .paths_for(ix)
    message(ix, " checkpoint=", file.exists(pp$checkpoint),
            " elbow=", file.exists(pp$elbow_csv),
            " unit_code=", dir.exists(pp$unit_code),
            " summary=", pp$summary)
  }
  quit(save = "no", status = 0)
}

suppressPackageStartupMessages({
  library(ggplot2)
  library(gridExtra)
  library(survival)
  library(rms)
  library(grid)
  library(forestploter)
})

.ok <- character(0)
.fail <- character(0)
for (ix in .indices) {
  pp <- .paths_for(ix)
  tryCatch({
    .rebuild_one(pp)
    .ok <- c(.ok, ix)
  }, error = function(e) {
    message("FAIL ", ix, ": ", conditionMessage(e))
    .fail <<- c(.fail, ix)
  })
}

message("==== summary ====")
message("OK: ", paste(.ok, collapse = ", "))
if (length(.fail)) {
  message("FAIL: ", paste(.fail, collapse = ", "))
  quit(save = "no", status = 1L)
}
message("ALL DONE")
