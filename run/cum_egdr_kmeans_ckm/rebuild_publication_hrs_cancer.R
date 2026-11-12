#!/usr/bin/env Rscript
###############################################################################
# rebuild_publication_hrs_cancer.R
# HRS 新发癌症 · 两波累计暴露 k-means · 多指标发表重导
#
# 对齐 HRS/癌症 cum_egdr_kmeans 布局：
#   by_index/【success】<INDEX>/summary_results/{Tables,Figures}
#   Tables 1–3 / S1–S4 + Figures 1–3 / S1–S3
#
# Usage:
#   Rscript run/cum_egdr_kmeans_ckm/rebuild_publication_hrs_cancer.R
#   Rscript run/cum_egdr_kmeans_ckm/rebuild_publication_hrs_cancer.R --index ABSI
#   Rscript run/cum_egdr_kmeans_ckm/rebuild_publication_hrs_cancer.R --project cum_egdr_kmeans_hrs_cancer_4wave
#   Rscript run/cum_egdr_kmeans_ckm/rebuild_publication_hrs_cancer.R --dry-run
###############################################################################

args <- commandArgs(trailingOnly = TRUE)
if ("--help" %in% args || "-h" %in% args) {
  cat(
    "rebuild_publication_hrs_cancer.R\n",
    "  --index NAME     Only rebuild one success index (default: all success)\n",
    "  --project NAME   Under 58_cancer/ (default: cum_egdr_kmeans_hrs_cancer)\n",
    "  --dry-run        Resolve paths; exit\n",
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

.project_arg <- {
  i <- match("--project", args)
  if (!is.na(i) && i < length(args)) trimws(args[[i + 1L]]) else "cum_egdr_kmeans_hrs_cancer"
}
.study_rel <- file.path("58_cancer", .project_arg)
.proj <- file.path(res_root, .study_rel)
.shared_fig <- file.path(.proj, "_shared", "Figures")
.scan_success_indices <- function() {
  roots <- list.dirs(file.path(.proj, "by_index"), recursive = FALSE, full.names = FALSE)
  roots <- roots[grepl("^\u3010success\u3011", roots)]
  sort(sub("^\u3010success\u3011", "", roots))
}
.default_indices <- {
  sc <- .scan_success_indices()
  if (length(sc)) sc else c(
    "BMI", "WHtR", "WWI", "ABSI", "BRI",
    "NHHR", "NHDL", "TC_HDL", "eGDR", "HbA1c_HDL_C", "CRP_HDL"
  )
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

.ix_display <- function(index) {
  if (exists("pipeline_display_label", mode = "function")) {
    as.character(pipeline_display_label(index))[1L]
  } else {
    gsub("_", " ", as.character(index)[1L], fixed = TRUE)
  }
}

.purge_stale_figures <- function(fig_dir, index) {
  ix_lab <- .ix_display(index)
  keep_stems <- c(
    "Figure 1. Inclusion exclusion flowchart",
    sprintf("Figure 2. %s change patterns", ix_lab),
    sprintf("Figure 3. RCS of cumulative %s and cancer", ix_lab),
    sprintf("Figure S1. RCS cumulative %s Cox HR", ix_lab),
    sprintf("Figure S2. Cumulative %s subgroup HR", ix_lab),
    sprintf("Figure S3. Cumulative %s subgroup OR", ix_lab)
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
    "^Table 2\\. Associations of .* with cancer\\.xlsx$",
    "^Table 3\\. Subgroup analysis of .* change patterns\\.xlsx$",
    "^Table S1\\. Cox associations of .* with cancer\\.xlsx$",
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
  if (!"Drink" %in% names(data) && "Alcohol_drinking" %in% names(data)) {
    data$Drink <- data$Alcohol_drinking
  }
  if (!"Triglycerides" %in% names(data) && "TG" %in% names(data)) {
    data$Triglycerides <- data$TG
  }
  if (!"Total_Cholesterol" %in% names(data) && "TC" %in% names(data)) {
    data$Total_Cholesterol <- data$TC
  }
  data <- ckm_stroke_add_futime(data)
  # HRS workers may drop/blank status; always rebuild from Cancer
  stopifnot("Cancer" %in% names(data))
  data$status <- as.integer(as.numeric(data$Cancer) == 1L)
  if (!"futime" %in% names(data) || all(!is.finite(as.numeric(data$futime)))) {
    data$futime <- 4
  } else {
    data$futime <- as.numeric(data$futime)
    data$futime[!is.finite(data$futime) | data$futime <= 0] <- 4
  }
  data <- ckm_stroke_prepare_age_group(data, 60L)
  data <- ckm_stroke_attach_class_paper(data, "eGDR_Class", ckm_stroke_class_map_paper())
  if ("Gender" %in% names(data)) {
    data$Gender <- factor(as.character(data$Gender), levels = c("Female", "Male"))
  }
  # Prefer Marital_Status when Marital was collapsed to a single level
  mv_src <- if ("Marital_Status" %in% names(data)) {
    as.character(data$Marital_Status)
  } else if ("Marital" %in% names(data)) {
    as.character(data$Marital)
  } else {
    character(0)
  }
  if (length(mv_src)) {
    mv <- tolower(trimws(mv_src))
    out <- ifelse(
      is.na(mv_src) | !nzchar(mv_src), NA_character_,
      ifelse(grepl("unmarried|single|divorced|widowed|separated|other", mv), "Single",
        ifelse(grepl("^married|partner", mv), "Married", "Single"))
    )
    data$Marital <- factor(out, levels = c("Single", "Married"))
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
  models <- ckm_stroke_model_sets(bl, data, index_name = index, outcome = "Cancer")
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
  class_disp <- ckm_stroke_class_display_labels(
    data, t1_col = "eGDR_t1", t2_col = "eGDR_t2", cmap = cmap
  )
  ref_disp <- class_disp$summary$display[class_disp$summary$class == cmap$ref_class][1L]
  tert_cuts <- stats::quantile(as.numeric(data$cum_eGDR), probs = c(1/3, 2/3), na.rm = TRUE, names = FALSE)
  n_all <- nrow(data)
  n_by_class <- as.integer(table(data$Class_paper))
  names(n_by_class) <- names(table(data$Class_paper))
  tab_dir <- pp$tables
  fig_dir <- pp$figures
  sr <- pp$summary
  outcome <- "Cancer"
  ix_lab <- .ix_display(index)

  options(medical_blocks.pub_db_label = "HRS")
  Sys.setenv(MEDICAL_BLOCKS_PUB_DB = "HRS")
  options(pipeline.database_name = "")

  expo_labs <- c(
    cum = sprintf("Cumulative %s, mean (SD)", ix_lab),
    t1 = sprintf("%s 2012, mean (SD)", ix_lab),
    t2 = sprintf("%s 2016, mean (SD)", ix_lab)
  )

  message("  Table 1...")
  t1b <- ckm_stroke_build_table1_by_class(
    data, cmap = cmap,
    exposure_labs = expo_labs,
    outcome = outcome,
    outcome_lab = "Incident cancer, n (%)"
  )
  export_sci_table(
    t1b$df,
    file.path(tab_dir, sprintf("Table 1. Baseline characteristics by %s change patterns.xlsx", ix_lab)),
    title = sprintf("Table 1. Baseline characteristics according to %s change patterns", ix_lab),
    table_footnotes = c(
      "Values are mean (SD) or n (%). P from Kruskal-Wallis / chi-square across Class 1\u20134.",
      "Percentages use the non-missing denominator for that variable.",
      class_disp$footnote,
      sprintf("Analytic N = %s (HRS 2012\u20132016 exposure; 2020 incident cancer).", format(n_all, big.mark = ",")),
      "Section order: Demographics; Vital signs and laboratory tests; Comorbidities; Exposure."
    ),
    excel_level_row_idx = t1b$excel_level_row_idx,
    excel_use_prepared = FALSE,
    latex_include_colnames = TRUE
  )

  message("  Table 2 / S1 / S3 / S4...")
  .ud <- ckm_stroke_cont_unit_delta(ix_lab)
  .ud_lab <- ckm_stroke_unit_delta_label(.ud)
  .cum_sd <- stats::sd(as.numeric(data$cum_eGDR), na.rm = TRUE)
  if (!isTRUE(all.equal(.ud, 1))) {
    data$cum_eGDR_udelta <- as.numeric(data$cum_eGDR) / .ud
  }
  t2b <- ckm_stroke_build_table2_assoc(
    data, models, is_hr = FALSE, outcome = outcome, cmap = cmap, index_lab = ix_lab,
    unit_delta = .ud
  )
  ckm_stroke_export_assoc_xlsx(
    t2b,
    file.path(tab_dir, sprintf("Table 2. Associations of %s patterns and cumulative %s with cancer.xlsx", ix_lab, ix_lab)),
    sprintf("Table 2. Logistic regression for associations between %s change patterns, cumulative %s, and incident cancer", ix_lab, ix_lab),
    {
      .m3_cols <- unique(c("Cancer", "cum_eGDR", models$Model3))
      .m3_ok <- stats::complete.cases(data[, intersect(.m3_cols, names(data)), drop = FALSE])
      .m3_n <- sum(.m3_ok)
      .m3_ev <- sum(as.integer(as.numeric(data$Cancer[.m3_ok]) == 1L), na.rm = TRUE)
      c(
        "Model 1: unadjusted. Odds ratios are printed to 3 decimals.",
        paste0("Model 2: adjusted for ", paste(models$Model2, collapse = ", "), "."),
        paste0(
          "Model 3: adjusted for ", paste(models$Model3, collapse = ", "),
          ". Candidates (Age forced) were screened at univariate P<0.05, then VIF<4."
        ),
        if (identical(toupper(ix_lab), "WWI")) {
          "Waist circumference, weight, and BMI were kept out of the model because they are the components, or the immediate adiposity substitute, of WWI. Model 3 is not fully adjusted; residual confounding remains."
        } else {
          "Exposure-component variables were removed from the candidate set before screening. Model 3 is not fully adjusted; residual confounding remains."
        },
        paste0("Reference: Class 2 (", ref_disp, "); Tertile T1."),
        class_disp$footnote,
        sprintf("Tertile cuts of cumulative %s: %.3f and %.3f.", ix_lab, tert_cuts[1], tert_cuts[2]),
        "Incident cancer = HRS 2020 cancer status equal to 1. The risk set requires cancer-free at/before 2016. Dual-wave exposures are 2012 and 2016.",
        sprintf("Cumulative %s = ((%s_2012 + %s_2016)/2) \u00d7 4 (HRS wave span).", ix_lab, ix_lab, ix_lab),
        if (!isTRUE(all.equal(.ud, 1))) {
          sprintf(
            "Continuous cumulative %s OR is per %s increase (analytic SD of cumulative %s = %.3f).",
            ix_lab, .ud_lab, ix_lab, .cum_sd
          )
        } else {
          sprintf("Continuous cumulative %s OR is per 1-unit increase.", ix_lab)
        },
        sprintf(
          "Analytic N = %s. Model 3 complete-case N = %s (events = %s) for adjusted estimates.",
          format(n_all, big.mark = ","), format(.m3_n, big.mark = ","), format(.m3_ev, big.mark = ",")
        ),
        ckm_stroke_software_footnote()
      )
    }
  )
  s1b <- ckm_stroke_build_table_s1_cox(
    data, models, outcome = outcome, cmap = cmap, index_lab = ix_lab,
    unit_delta = .ud
  )
  ckm_stroke_export_assoc_xlsx(
    s1b,
    file.path(tab_dir, sprintf("Table S1. Cox associations of %s patterns and cumulative %s with cancer.xlsx", ix_lab, ix_lab)),
    sprintf("Table S1. Cox regression for associations between %s change patterns, cumulative %s, and incident cancer", ix_lab, ix_lab),
    c(
      "HR (95% CI). Follow-up is a fixed 2016 to 2020 interval (4 years) in the main Cox tables and Figure S1, so this is an interval check of a binary outcome rather than continuous-time survival.",
      "Model 1: unadjusted. Hazard ratios are printed to 3 decimals.",
      paste0("Model 2: adjusted for ", paste(models$Model2, collapse = ", "), "."),
      paste0(
        "Model 3: adjusted for ", paste(models$Model3, collapse = ", "),
        ". Candidates (Age forced) were screened at univariate P<0.05, then VIF<4."
      ),
      if (identical(toupper(ix_lab), "WWI")) {
        "Waist circumference, weight, and BMI stay out of the model (WWI components or the immediate adiposity substitute). Model 3 is not fully adjusted."
      } else {
        "Exposure-component variables were removed before screening. Model 3 is not fully adjusted."
      },
      paste0("Reference: Class 2 (", ref_disp, "); Tertile T1."),
      class_disp$footnote,
      sprintf("Tertile cuts of cumulative %s: %.3f and %.3f.", ix_lab, tert_cuts[1], tert_cuts[2]),
      if (!isTRUE(all.equal(.ud, 1))) {
        sprintf(
          "Continuous cumulative %s HR is per %s increase (analytic SD of cumulative %s = %.3f).",
          ix_lab, .ud_lab, ix_lab, .cum_sd
        )
      } else {
        sprintf("Continuous cumulative %s HR is per 1-unit increase.", ix_lab)
      },
      "k-means: unstandardized 2012 and 2016 values; nstart=25; seed=2026; iter.max=100; k from the elbow plot with a visual cap of 4.",
      ckm_stroke_software_footnote()
    )
  )
  .write_cont_precision <- function(built, stem) {
    cf <- built$cont_fits
    if (is.null(cf)) return(invisible(NULL))
    prec <- do.call(rbind, lapply(names(cf), function(mn) {
      r <- cf[[mn]]
      if (is.null(r) || !nrow(r)) return(NULL)
      data.frame(model = mn, r, stringsAsFactors = FALSE)
    }))
    if (is.null(prec) || !nrow(prec)) return(invisible(NULL))
    dir.create(.internal, recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(prec, file.path(.internal, paste0(stem, "_continuous_full_precision.csv")), row.names = FALSE)
  }
  .write_cont_precision(t2b, "Table2")
  .write_cont_precision(s1b, "TableS1")

  message("  MICE Rubin pool for S3/S4...")
  .mice_need <- unique(c(
    outcome, "futime", "status", "eGDR_Class", "cum_eGDR",
    if (!isTRUE(all.equal(.ud, 1))) "cum_eGDR_udelta" else NULL,
    "eGDR_tertile", models$Model3
  ))
  .mice_need <- intersect(.mice_need, names(data))
  .mice_md <- data[, .mice_need, drop = FALSE]
  .mice_md$eGDR_Class <- stats::relevel(factor(.mice_md$eGDR_Class), ref = cmap$ref_semantic)
  .mice_md$eGDR_tertile <- stats::relevel(factor(.mice_md$eGDR_tertile), ref = "T1")
  .mice_md$T_num <- as.integer(.mice_md$eGDR_tertile)
  .mice_impute <- setdiff(
    names(.mice_md),
    c(outcome, "futime", "status", "eGDR_Class", "cum_eGDR", "cum_eGDR_udelta",
      "eGDR_tertile", "T_num")
  )
  .mice_prep <- ckm_stroke_prepare_mice(.mice_md, .mice_impute, m = 5L, maxit = 5L, seed = 2026L)
  if (is.null(.mice_prep)) {
    message("  skip Table S3/S4: Model3 covariates have no missingness (no MICE shell).")
    dir.create(.internal <- file.path(pp$summary, "_internal"), recursive = TRUE, showWarnings = FALSE)
    writeLines(
      c(
        "Table S3/S4 omitted.",
        "Reason: after UV-VIF, Model 3 covariates have zero missingness in the analytic set.",
        "Per cum_egdr_kmeans iron rule, MICE tables are not mirrored from complete-case."
      ),
      file.path(.internal, "MICE_S3S4_omitted.txt")
    )
    # drop any stale S3/S4 from prior drafts
    for (.stale in c("Table S3. Cox after MICE.xlsx", "Table S4. Logistic after MICE.xlsx")) {
      .sp <- file.path(tab_dir, .stale)
      if (file.exists(.sp)) file.remove(.sp)
    }
  } else {
    .mice_row <- function(is_hr) {
      function(dd, expo, cov) {
        ckm_stroke_mice_fit_row(.mice_prep$imp, expo, cov, is_hr = is_hr, outcome = outcome)
      }
    }
    .mice_trend <- function(is_hr) {
      function() {
        vapply(c("Model1", "Model2", "Model3"), function(mn) {
          row <- ckm_stroke_mice_fit_row(
            .mice_prep$imp, "T_num", models[[mn]], is_hr = is_hr, outcome = outcome
          )
          if (is.null(row) || !nrow(row)) return("")
          ckm_stroke_fmt_p(row$P[1L])
        }, character(1))
      }
    }
    .mice_fn <- c(
      sprintf("Multiple imputation with mice, m=5, maxit=5, seed=2026. Imputed covariates: %s.",
              paste(.mice_prep$imputed, collapse = ", ")),
      "The outcome and the exposures are predictors in the imputation model and are not themselves imputed. Coefficients are combined with Rubin's rules (mice::pool).",
      "Model 1 has no covariates, so its imputed-data estimate can match the complete-case crude estimate. Model 2 and Model 3 must not.",
      paste0("Reference: Class 2 (", ref_disp, "); Tertile T1."),
      class_disp$footnote
    )
    s3b <- ckm_stroke_build_table_s1_cox(
      data, models, outcome = outcome, cmap = cmap, index_lab = ix_lab,
      unit_delta = .ud,
      row_fit = .mice_row(TRUE), trend_p = .mice_trend(TRUE)
    )
    ckm_stroke_assert_mice_not_shell(s1b$df, s3b$df)
    ckm_stroke_export_assoc_xlsx(
      s3b, file.path(tab_dir, "Table S3. Cox after MICE.xlsx"),
      sprintf("Table S3. Association between %s change patterns, cumulative %s, and cancer: Cox regression after multiple imputation", ix_lab, ix_lab),
      .mice_fn
    )
    s4b <- ckm_stroke_build_table2_assoc(
      data, models, is_hr = FALSE, outcome = outcome, cmap = cmap, index_lab = ix_lab,
      unit_delta = .ud,
      row_fit = .mice_row(FALSE), trend_p = .mice_trend(FALSE)
    )
    ckm_stroke_assert_mice_not_shell(t2b$df, s4b$df)
    ckm_stroke_export_assoc_xlsx(
      s4b, file.path(tab_dir, "Table S4. Logistic after MICE.xlsx"),
      sprintf("Table S4. Association between %s change patterns, cumulative %s, and cancer: logistic regression after multiple imputation", ix_lab, ix_lab),
      .mice_fn
    )
  }

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
    title = sprintf("Table 3. Subgroup analysis of %s change patterns and incident cancer (HRS)", ix_lab),
    table_footnotes = c(
      "Adjusted for Model 3 covariates except the stratification variable.",
      paste0("Class 2 (", ref_disp, ") is the reference. Columns ordered Class 2 Reference, Class 1, Class 3, Class 4."),
      class_disp$footnote,
      "k-means classes are nominal, so this table has no P for trend across Class 1 to 4. Tertile trend stays in Table 2. P for interaction is a likelihood-ratio test, and is omitted when only one level remains estimable.",
      "Levels with no estimable class contrast (typically 0 events in the reference class) are omitted.",
      "Education strata for the continuous exposure are in Figure S2 (Cox) and Figure S3 (logistic), not in this class table.",
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
    title = sprintf("Table S2. Subgroup analysis of %s change patterns and incident cancer (Cox, HRS)", ix_lab),
    table_footnotes = c(
      "Adjusted for Model 3 covariates except the stratification variable.",
      "Each stratum N counts non-missing values only. Missing values are not assigned to both levels.",
      "k-means classes are nominal. This table does not report a P for trend across Class 1 to 4.",
      "NE marks a contrast that is not estimable. Its P value is an em dash.",
      paste0("Class 2 (", ref_disp, ") is the reference."),
      class_disp$footnote
    ),
    excel_use_prepared = FALSE
  )

  # ---- Figures ----
  message("  Figure 1 (index-specific HRS flowchart)...")
  ckm_stroke_kill_fig2_splits(fig_dir)
  n_all <- nrow(data)
  # Age≥50 @ 2016 interview → cancer-free → 2020 status → dual BMI → dual index
  # 数字来自 hrs_cancer_cum_kmeans_analysis_wide.csv（Age 列 ≥50）
  n0 <- 15585L
  e_prev <- 2820L
  n_free <- 12765L
  e_fu <- 3338L
  n_fu <- 9427L
  e_bmi <- 203L
  n_bmi <- 9224L
  e_index <- as.integer(n_bmi - n_all)
  if (e_index < 0L) e_index <- 0L
  excl2 <- paste0(
    "Excluded sequentially:\n",
    "Missing cancer status at 2020\n(n=%s)\n",
    "Incomplete two-wave BMI\n(n=%s)\n",
    sprintf("Incomplete two-wave %s\n(n=%%s)", ix_lab)
  )
  attr_list <- list(
    n0 = n0, e1 = e_prev, n1 = n_free,
    e2 = e_fu, e3 = e_bmi, e4 = e_index, n_final = as.integer(n_all)
  )
  steps_remain <- c(n0, n_free, n_fu, n_bmi, as.integer(n_all))
  steps_excl <- c(NA_integer_, e_prev, e_fu, e_bmi, e_index)
  step_labs <- c(
    "HRS Age \u2265 50 with 2016 interview",
    "No cancer at/before 2016 (risk origin)",
    "Cancer status at 2020 available",
    "Complete two-wave BMI",
    sprintf("Complete two-wave %s (analytic)", ix_lab)
  )
  excl_labs <- c(
    NA_character_,
    "Prevalent cancer at/before 2016",
    "Missing cancer status at 2020",
    "Incomplete two-wave BMI",
    sprintf("Incomplete two-wave %s", ix_lab)
  )
  note1 <- sprintf(
    "Note: inclusion Age \u2265 50; final analytic N=%s for %s (HRS 2012\u20132016 exposure; 2020 incident cancer).",
    format(n_all, big.mark = ","), ix_lab
  )
  ckm_stroke_fig1_flowchart(
    file.path(fig_dir, "Figure 1. Inclusion exclusion flowchart.pdf"),
    attrition = attr_list,
    class_n = n_by_class,
    cohort_lab = "HRS Age \u2265 50 with 2016 interview",
    excl1_lab = "Excluded: prevalent cancer\nat/before 2016 (n=%s)",
    eligible_lab = "Cancer-free at 2016 risk origin\n(n=%s)",
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
    year_labs = c(2012, 2016),
    ylab_c = sprintf("Mean %s (\u00b1 SE)", ix_lab),
    xlab_b = sprintf("%s (2012)", ix_lab),
    ylab_b = sprintf("%s (2016)", ix_lab),
    xlab_c = "HRS wave year",
    cluster_labels = class_disp$labels
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
    data, "cum_eGDR", TRUE, "A  Overall", "Odds Ratio of Cancer", covars,
    outcome = outcome, xlab = xlab_cum, nknots = .nk
  )
  p3b <- ckm_stroke_rcs_one_panel(
    data[bmi_lt30, , drop = FALSE], "cum_eGDR", TRUE, "B  BMI < 30", "Odds Ratio of Cancer",
    covars, outcome = outcome, xlab = xlab_cum, nknots = .nk
  )
  p3c <- ckm_stroke_rcs_one_panel(
    data_age[age_hi, , drop = FALSE], "cum_eGDR", TRUE, "C  Age \u2265 60", "Odds Ratio of Cancer",
    setdiff(covars, "Age"), outcome = outcome, xlab = xlab_cum, nknots = .nk
  )
  .fig3_path <- file.path(fig_dir, sprintf("Figure 3. RCS of cumulative %s and cancer.pdf", ix_lab))
  if (exists("pipeline_pdf_device", mode = "function")) {
    pipeline_pdf_device(.fig3_path, width = 12.8, height = 4.2)
  } else {
    grDevices::pdf(.fig3_path, width = 12.8, height = 4.2, useDingbats = FALSE, family = "Times")
  }
  gridExtra::grid.arrange(p3a, p3b, p3c, ncol = 3)
  grDevices::dev.off()

  # Fig S1：主分析固定 2016→2020 间隔（4 年）；无单独访视月 probe
  data_s1 <- data
  data_s1$status <- as.integer(as.numeric(data_s1[[outcome]]) == 1L)
  data_s1$futime <- 4
  data_s1_age <- ckm_stroke_prepare_age_group(data_s1, 60L)
  age_hi_s1 <- !is.na(data_s1_age$Age_Group) &
    grepl("60", as.character(data_s1_age$Age_Group)) &
    grepl("\u2265|>=|\u2265", as.character(data_s1_age$Age_Group))
  bmi_lt30_s1 <- is.finite(as.numeric(data_s1$BMI)) & as.numeric(data_s1$BMI) < 30
  pS1a <- ckm_stroke_rcs_one_panel(
    data_s1, "cum_eGDR", FALSE, "A  Overall", "Hazard Ratio of Cancer", covars,
    outcome = outcome, xlab = xlab_cum, nknots = .nk
  )
  pS1b <- ckm_stroke_rcs_one_panel(
    data_s1[bmi_lt30_s1, , drop = FALSE], "cum_eGDR", FALSE, "B  BMI < 30", "Hazard Ratio of Cancer",
    covars, outcome = outcome, xlab = xlab_cum, nknots = .nk
  )
  pS1c <- ckm_stroke_rcs_one_panel(
    data_s1_age[age_hi_s1, , drop = FALSE], "cum_eGDR", FALSE, "C  Age \u2265 60", "Hazard Ratio of Cancer",
    setdiff(covars, "Age"), outcome = outcome, xlab = xlab_cum, nknots = .nk
  )
  .figs1_path <- file.path(fig_dir, sprintf("Figure S1. RCS cumulative %s Cox HR.pdf", ix_lab))
  if (exists("pipeline_pdf_device", mode = "function")) {
    pipeline_pdf_device(.figs1_path, width = 12.8, height = 4.2)
  } else {
    grDevices::pdf(.figs1_path, width = 12.8, height = 4.2, useDingbats = FALSE, family = "Times")
  }
  gridExtra::grid.arrange(pS1a, pS1b, pS1c, ncol = 3)
  grDevices::dev.off()

  message("  Figure S2 / S3 forests...")
  model3_forest <- intersect(covars, names(data))
  model3_forest <- setdiff(
    model3_forest,
    if (grepl("BMI|WHtR|WWI|AIP_BMI", index, ignore.case = TRUE)) "BMI" else character(0)
  )
  s2_rows <- ckm_stroke_forest_free_stats(
    data, "cum_eGDR", TRUE,
    file.path(fig_dir, sprintf("Figure S2. Cumulative %s subgroup HR.pdf", ix_lab)),
    title = sprintf("Fig. S2  Subgroup analysis (Cox, per %s cum-%s)", .ud_lab, ix_lab),
    outcome = outcome,
    expo_lab = paste("cumulative", ix_lab),
    index_lab = ix_lab,
    model3 = model3_forest,
    scale = "unit",
    unit_delta = .ud,
    mice_keep = unique(c(outcome, "futime", "status", "eGDR_Class", "cum_eGDR", "eGDR_tertile", model3_forest)),
    mice_impute = model3_forest
  )
  s3_rows <- ckm_stroke_forest_free_stats(
    data, "cum_eGDR", FALSE,
    file.path(fig_dir, sprintf("Figure S3. Cumulative %s subgroup OR.pdf", ix_lab)),
    title = sprintf("Fig. S3  Subgroup analysis (Logistic, per %s cum-%s)", .ud_lab, ix_lab),
    outcome = outcome,
    expo_lab = paste("cumulative", ix_lab),
    index_lab = ix_lab,
    model3 = model3_forest,
    scale = "unit",
    unit_delta = .ud,
    mice_keep = unique(c(outcome, "futime", "status", "eGDR_Class", "cum_eGDR", "eGDR_tertile", model3_forest)),
    mice_impute = model3_forest
  )
  utils::write.csv(s2_rows, file.path(.internal, "Figure_S2_forest_rows.csv"), row.names = FALSE)
  utils::write.csv(s3_rows, file.path(.internal, "Figure_S3_forest_rows.csv"), row.names = FALSE)

  message("  Flush tables / figure formats...")
  render_queued_tables(list(config = list(project = list(root = root, output_dir = .proj))))
  config_stub <- list(project = list(root = root, output_dir = .proj, database = "HRS"))
  pub_figure_ensure_formats(
    fig_dir,
    meta = list(study = "HRS_cum_kmeans_cancer", index = index),
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
        "Study title: association of trajectory clusters and cumulative exposure with incident cancer (logistic, Cox, and restricted cubic splines). This is not a predictive model and not an artificial-intelligence analysis.",
        "Inclusion: baseline age at least 50 years, applied at data ingest.",
        "Incident cancer equals HRS 2020 cancer status = 1. The risk set requires cancer-free at/before 2016.",
        "k-means uses unstandardized 2012 and 2016 values, nstart 25, seed 2026, iter.max 100. k is the elbow choice with a visual cap of 4.",
        "Class display names are taken from the observed mean trajectory. A decline is called rapid only when the absolute mean change is at least 25 percent of the between-class 2012 range.",
        "Model 3 candidates are screened at univariate P<0.05 and VIF<4. Age is forced into the candidate set. Component variables of the exposure stay out. The model is not fully adjusted.",
        "Multiple imputation tables use mice with m=5 and Rubin's rules. They are not copies of the complete-case tables.",
        "Author adjudication (retained): Figure 3 RCS P-overall may differ from the Table 2 linear continuous P, because the functional forms differ."
      )
    ),
    silent = TRUE
  )
  .methods_txt <- file.path(tab_dir, "Methods_software_versions.txt")
  if (file.exists(.methods_txt)) {
    file.copy(.methods_txt, file.path(sr, "Methods_software_versions.txt"), overwrite = TRUE)
  }

  fig1_md <- file.path(fig_dir, "image_information", "Figure 1. Inclusion exclusion flowchart.md")
  dir.create(dirname(fig1_md), recursive = TRUE, showWarnings = FALSE)
  .fig1_lines <- c(
    "# Figure 1. Inclusion exclusion flowchart",
    "",
    "## \u56fe\u9762\u8bf4\u660e",
    sprintf("CONSORT \u5f0f\u7eb3\u6392\u6d41\u7a0b\u56fe\uff08HRS / %s\uff09\uff1a\u4e3b\u5e72\u4e3a\u9010\u6b65\u7eb3\u5165\uff0c\u53f3\u4fa7 Exclude \u6846\u4e3a\u76f8\u90bb\u6b65\u5dee\u989d\uff0c\u5e95\u90e8\u5206\u53c9\u4e3a Class 1\u20134\u3002", ix_lab),
    "",
    "### \u9010\u6b65\u4eba\u6570"
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
    sprintf("暴露：%s（两波累计 + k-means）。结局：新发癌症。样本量 N=%s（HRS）。", ix_lab, format(n_all, big.mark = ",")),
    "数据库：HRS。Grouping：Class 1\u20134。"
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
    sprintf("- B：%s 2012 vs 2016 散点 + 各类凸包着色云", ix_lab),
    sprintf("- C：四类 mean\u00b1SE %s 轨迹（2012\u21922016）", ix_lab),
    "",
    "### \u56fe\u4e0a\u6807\u6ce8",
    "- A：chosen k = 4",
    sprintf("- Class n：Class1=%s, Class2=%s, Class3=%s, Class4=%s（合计 %s）",
            n_by_class[["Class 1"]], n_by_class[["Class 2"]],
            n_by_class[["Class 3"]], n_by_class[["Class 4"]], n_all),
    "",
    "## \u5206\u6790\u4e0a\u4e0b\u6587",
    sprintf("暴露：%s 轨迹类别（k-means, k=4）。结局：癌症。样本量 N=%s（HRS）。", ix_lab, format(n_all, big.mark = ",")),
    class_disp$footnote,
    "数据库：HRS。"
  ), fig2_md)

  .ckm_rcs_p <- function(p, nm) {
    v <- attr(p, nm)
    if (is.null(v) || !is.finite(as.numeric(v)[1L])) return("未收获")
    if (identical(nm, "rcs_ref")) return(sprintf("%.2f", as.numeric(v)[1L]))
    pv <- as.numeric(v)[1L]
    if (pv < 0.001) "<0.001" else sprintf("%.3f", pv)
  }
  fig3_md <- file.path(
    fig_dir, "image_information",
    sprintf("Figure 3. RCS of cumulative %s and cancer.md", ix_lab)
  )
  writeLines(c(
    sprintf("# Figure 3. RCS of cumulative %s and cancer", ix_lab),
    "",
    "## \u56fe\u9762\u8bf4\u660e",
    "三面板限制性立方样条（RCS, 3 knots）+ Model 3：累计暴露与癌症 OR。",
    "- A：Overall",
    "- B：BMI < 30",
    "- C：Age \u2265 60",
    "三块面板的非线性检验都不显著，主叙述跟全分析集的总体关联，B 和 C 是分层稳健性。",
    sprintf("- A Overall：P for overall = %s；P for non-linearity = %s；Ref. point = %s",
            .ckm_rcs_p(p3a, "rcs_p_overall"), .ckm_rcs_p(p3a, "rcs_p_nonlin"), .ckm_rcs_p(p3a, "rcs_ref")),
    sprintf("- B BMI < 30：P for overall = %s；P for non-linearity = %s；Ref. point = %s",
            .ckm_rcs_p(p3b, "rcs_p_overall"), .ckm_rcs_p(p3b, "rcs_p_nonlin"), .ckm_rcs_p(p3b, "rcs_ref")),
    sprintf("- C Age ≥ 60：P for overall = %s；P for non-linearity = %s；Ref. point = %s",
            .ckm_rcs_p(p3c, "rcs_p_overall"), .ckm_rcs_p(p3c, "rcs_p_nonlin"), .ckm_rcs_p(p3c, "rcs_ref")),
    "",
    "## \u5206\u6790\u4e0a\u4e0b\u6587",
    sprintf(
      "暴露：累计 %s。结局：新发癌症。纳入年龄至少 50 岁。Model 3 = %s。N=%s。数据库：HRS。面板 A 为全分析集，B 为 BMI < 30，C 为年龄至少 60 岁。",
      ix_lab, paste(covars, collapse = ", "), format(n_all, big.mark = ",")
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
    "面板同 Fig3（Overall | BMI < 30 | Age \u2265 60）；Cox HR；futime = 固定 4 年（2016\u21922020）。",
    "三块面板的非线性检验都不显著。主叙述跟全分析集的总体关联。",
    sprintf("- A Overall：P for overall = %s；P for non-linearity = %s；Ref. point = %s",
            .ckm_rcs_p(pS1a, "rcs_p_overall"), .ckm_rcs_p(pS1a, "rcs_p_nonlin"), .ckm_rcs_p(pS1a, "rcs_ref")),
    sprintf("- B BMI < 30：P for overall = %s；P for non-linearity = %s；Ref. point = %s",
            .ckm_rcs_p(pS1b, "rcs_p_overall"), .ckm_rcs_p(pS1b, "rcs_p_nonlin"), .ckm_rcs_p(pS1b, "rcs_ref")),
    sprintf("- C Age ≥ 60：P for overall = %s；P for non-linearity = %s；Ref. point = %s",
            .ckm_rcs_p(pS1c, "rcs_p_overall"), .ckm_rcs_p(pS1c, "rcs_p_nonlin"), .ckm_rcs_p(pS1c, "rcs_ref")),
    "",
    "## \u5206\u6790\u4e0a\u4e0b\u6587",
    sprintf(
      "Model 3 = %s。N=%s。纳入年龄至少 50 岁。HRS。面板 A 为全分析集，B 为 BMI < 30，C 为年龄至少 60 岁。futime 固定 4 年。",
      paste(covars, collapse = ", "), format(nrow(data_s1), big.mark = ",")
    )
  ), fig_s1_md)

  moved <- .archive_non_pub(tab_dir, fig_dir, sr)
  stale <- .purge_stale_figures(fig_dir, index)
  if (length(stale)) moved <- c(moved, paste0("fig:", stale))
  ckm_stroke_kill_fig2_splits(fig_dir)
  # 二次四目录：清掉残留后保证仅 keep stems
  pub_figure_ensure_formats(
    fig_dir,
    meta = list(study = "HRS_cum_kmeans_cancer", index = index),
    config = config_stub, purge = FALSE
  )

  # ---- code bundle：写到同级 workspace，不进交付根白名单 ----
  message("  code/ (archive side) ...")
  .code_arch <- file.path(
    dirname(sr),
    paste0(basename(sr), "_delivery_workspace"),
    paste0("code_", format(Sys.time(), "%Y%m%d_%H%M%S"))
  )
  if (dir.exists(pp$unit_code)) {
    dir.create(.code_arch, recursive = TRUE, showWarnings = FALSE)
    .copy_dir_contents(pp$unit_code, .code_arch)
  } else {
    warning("unit code missing for ", index, ": ", pp$unit_code)
  }

  # 交付面：Methods md + 软件版本 txt + 白名单修剪（Figures/Tables/Methods/软件/中期）
  message("  finalize delivery whitelist...")
  .fin <- ckm_stroke_finalize_summary_delivery(
    summary_root = sr,
    index_lab = ix_lab,
    n_analytic = n_all,
    model3_covars = covars,
    unit_delta = .ud,
    min_age = 50L,
    database = "HRS",
    outcome_lab = "incident cancer",
    software_extra = c(
      class_disp$footnote,
      "Figure 3 / S1 panels: Overall | BMI < 30 | Age >= 60 (RCS, 3 knots).",
      sprintf("Junk archived before prune: %s",
              if (length(moved)) paste(moved, collapse = ", ") else "(none)")
    ),
    prune = TRUE
  )

  message(
    "  DONE ", index,
    " | Tables: ", paste(list.files(tab_dir, pattern = "\\.xlsx$"), collapse = " | "),
    " | methods=", file.exists(.fin$methods),
    " | software=", file.exists(.fin$software),
    " | pruned=", length(.fin$moved %||% character(0))
  )
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
