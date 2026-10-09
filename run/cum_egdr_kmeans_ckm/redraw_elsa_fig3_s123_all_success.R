#!/usr/bin/env Rscript
# 同步全部 【success】：Fig3 (Model3+RCS3结) / S1(访视月futime) / S2–S3(格式统一)
# Usage:
#   Rscript run/cum_egdr_kmeans_ckm/redraw_elsa_fig3_s123_all_success.R
#   Rscript run/cum_egdr_kmeans_ckm/redraw_elsa_fig3_s123_all_success.R --index WWI,AIP

args <- commandArgs(trailingOnly = TRUE)
.is_linux <- identical(.Platform$OS.type, "unix")
root <- if (.is_linux) "/mnt/e/01block/01Block-new-Final" else "E:/01block/01Block-new-Final"
res <- if (.is_linux) "/mnt/g/02block_result" else "G:/02block_result"
# Windows R 跑本脚本时强制 Win 路径
if (!identical(.Platform$OS.type, "unix")) {
  root <- "E:/01block/01Block-new-Final"
  res <- "G:/02block_result"
}
Sys.setenv(MEDICAL_BLOCKS_ROOT = root, BLOCK_RESULT_ROOT = res, SMOKE_NO_FEISHU = "1")
setwd(root)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pub_figure_export.R"))
source(file.path(root, "R/literature_ckm_cum_egdr.R"))
source(file.path(root, "R/cum_egdr_kmeans_pub.R"))

suppressPackageStartupMessages({
  library(ggplot2); library(gridExtra); library(survival); library(rms)
  library(grid); library(forestploter); library(data.table)
})

.proj <- file.path(res, "10_osteoporosis", "cum_egdr_kmeans_41654871")
.probe <- file.path(.proj, "reports", "elsa_r6_r8_interview_futime_probe.csv")
.stopifnot_file <- function(p) if (!file.exists(p)) stop("missing: ", p)
.stopifnot_file(.probe)

.default <- {
  roots <- list.dirs(file.path(.proj, "by_index"), recursive = FALSE, full.names = FALSE)
  roots <- roots[grepl("^\u3010success\u3011", roots)]
  sc <- sort(sub("^\u3010success\u3011", "", roots))
  if (length(sc)) sc else c("WWI", "AIP", "AIP_BMI", "AIP_WC", "AIP_WHtR")
}
.idx_arg <- {
  i <- match("--index", args)
  if (!is.na(i) && i < length(args)) strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1]] else .default
}
.indices <- trimws(.idx_arg)

.redraw_one <- function(index) {
  message("========== ", index, " ==========")
  .unit <- file.path(.proj, "by_unit", paste0("\u3010success\u3011", index))
  .sr <- file.path(.proj, "by_index", paste0("\u3010success\u3011", index), "summary_results")
  .fig <- file.path(.sr, "Figures")
  .tab <- file.path(.sr, "Tables")
  .ck <- file.path(.unit, "checkpoints", "table1_by_class_ckm.rds")
  .stopifnot_file(.ck)
  dir.create(.fig, recursive = TRUE, showWarnings = FALSE)
  dir.create(.tab, recursive = TRUE, showWarnings = FALSE)

  data <- ckm_stroke_harmonize_columns(readRDS(.ck)$ctx$data$cleaned)
  if (!"Hypertension" %in% names(data) && "Hypertension_w4" %in% names(data)) {
    data$Hypertension <- data$Hypertension_w4
  }
  data$Gender <- factor(as.character(data$Gender), levels = c("Female", "Male"))
  mv <- as.character(data$Marital)
  mv[mv %in% c("Other", "Unmarried", "Single", "Divorced", "Widowed")] <- "Single"
  mv[mv %in% c("Married", "Partnered")] <- "Married"
  data$Marital <- factor(mv, levels = c("Single", "Married"))
  for (cv in c("Dyslipidemia", "Hypertension", "Education", "Smoke", "Drink", "Diabetes")) {
    if (cv %in% names(data) && !is.factor(data[[cv]])) data[[cv]] <- factor(as.character(data[[cv]]))
  }

  n_analytic <- nrow(data)
  pr <- data.table::fread(.probe)[, .(ID, futime_iw)]
  data$ID <- as.integer(data$ID)
  data <- merge(data, pr, by = "ID", all.x = TRUE)
  data$futime <- as.numeric(data$futime_iw)
  data$status <- as.integer(as.numeric(data$Osteoporosis) == 1L)
  n_drop <- sum(!(is.finite(data$futime) & data$futime > 0))
  data <- data[is.finite(data$futime) & data$futime > 0, , drop = FALSE]
  message("  analytic N=", n_analytic, " | with futime n=", nrow(data),
          " (dropped ", n_drop, ")")

  bl <- list(
    covariate_mode = "uv_vif",
    model2 = c("Age", "Gender", "Marital"),
    model3 = c("Age", "Gender", "Marital", "BMI", "Education", "Smoke", "Drink",
               "Dyslipidemia", "Diabetes", "Hypertension"),
    current_index = index
  )
  models <- ckm_stroke_model_sets(bl, data, index_name = index, outcome = "Osteoporosis")
  covars <- intersect(models$Model3, names(data))
  message("  Model3: ", paste(covars, collapse = "+"))

  outcome <- "Osteoporosis"
  xlab_cum <- sprintf("Cumulative %s", index)
  .nk <- 3L
  data_age <- ckm_stroke_prepare_age_group(data, 60L)
  age_hi <- !is.na(data_age$Age_Group) &
    grepl("60", as.character(data_age$Age_Group)) &
    grepl("\u2265|>=|\u2265", as.character(data_age$Age_Group))
  .bmi_lt30 <- is.finite(as.numeric(data$BMI)) & as.numeric(data$BMI) < 30

  # Fig3 logistic RCS
  p3a <- ckm_stroke_rcs_one_panel(
    data, "cum_eGDR", TRUE, "A", "Odds Ratio of Osteoporosis", covars,
    outcome = outcome, xlab = xlab_cum, nknots = .nk
  )
  p3b <- ckm_stroke_rcs_one_panel(
    data[.bmi_lt30, , drop = FALSE], "cum_eGDR", TRUE, "B", "Odds Ratio of Osteoporosis",
    covars, outcome = outcome, xlab = xlab_cum, nknots = .nk
  )
  p3c <- ckm_stroke_rcs_one_panel(
    data_age[age_hi, , drop = FALSE], "cum_eGDR", TRUE, "C", "Odds Ratio of Osteoporosis",
    setdiff(covars, "Age"), outcome = outcome, xlab = xlab_cum, nknots = .nk
  )
  pdf(file.path(.fig, sprintf("Figure 3. RCS of cumulative %s and osteoporosis.pdf", index)),
      width = 12.8, height = 4.2, useDingbats = FALSE)
  gridExtra::grid.arrange(p3a, p3b, p3c, ncol = 3)
  dev.off()

  # S1 Cox RCS + interview futime
  pS1a <- ckm_stroke_rcs_one_panel(
    data, "cum_eGDR", FALSE, "A", "Hazard Ratio of Osteoporosis", covars,
    outcome = outcome, xlab = xlab_cum, nknots = .nk
  )
  pS1b <- ckm_stroke_rcs_one_panel(
    data[.bmi_lt30, , drop = FALSE], "cum_eGDR", FALSE, "B", "Hazard Ratio of Osteoporosis",
    covars, outcome = outcome, xlab = xlab_cum, nknots = .nk
  )
  pS1c <- ckm_stroke_rcs_one_panel(
    data_age[age_hi, , drop = FALSE], "cum_eGDR", FALSE, "C", "Hazard Ratio of Osteoporosis",
    setdiff(covars, "Age"), outcome = outcome, xlab = xlab_cum, nknots = .nk
  )
  pdf(file.path(.fig, sprintf("Figure S1. RCS cumulative %s Cox HR.pdf", index)),
      width = 12.8, height = 4.2, useDingbats = FALSE)
  gridExtra::grid.arrange(pS1a, pS1b, pS1c, ncol = 3)
  dev.off()

  # S2 / S3 forests
  s2 <- ckm_stroke_forest_free_stats(
    data, "cum_eGDR", TRUE,
    file.path(.fig, sprintf("Figure S2. Cumulative %s subgroup HR.pdf", index)),
    title = sprintf("Fig. S2  Subgroup analysis (Cox, per 1-SD cum-%s)", index),
    outcome = outcome, expo_lab = sprintf("cumulative %s", index), model3 = covars
  )
  s3 <- ckm_stroke_forest_free_stats(
    data, "cum_eGDR", FALSE,
    file.path(.fig, sprintf("Figure S3. Cumulative %s subgroup OR.pdf", index)),
    title = sprintf("Fig. S3  Subgroup analysis (Logistic, per 1-SD cum-%s)", index),
    outcome = outcome, expo_lab = sprintf("cumulative %s", index), model3 = covars
  )
  .internal <- file.path(dirname(.tab), "_internal")
  dir.create(.internal, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(s2, file.path(.internal, "Figure_S2_forest_rows.csv"), row.names = FALSE)
  utils::write.csv(s3, file.path(.internal, "Figure_S3_forest_rows.csv"), row.names = FALSE)

  cfg <- list(project = list(root = root, output_dir = .proj, database = "ELSA"))
  pub_figure_ensure_formats(.fig, meta = list(study = "ELSA_cum_kmeans", index = index),
                            config = cfg, purge = FALSE)

  imd <- file.path(.fig, "image_information")
  dir.create(imd, recursive = TRUE, showWarnings = FALSE)
  writeLines(c(
    sprintf("# Figure 3. RCS of cumulative %s and osteoporosis", index), "",
    "## 图面说明",
    "三面板 RCS（3 knots）+ Model3（uv_vif，与 Table2 同协变量）。A Overall；B BMI < 30；C Age ≥60。",
    "纵轴 OR；图上标注 P for overall / P for non-linearity。",
    "",
    "## 分析上下文",
    sprintf("暴露：cum_%s。结局：Osteoporosis。Model3=%s。N=%s。ELSA。",
            index, paste(covars, collapse = "+"), format(nrow(data), big.mark = ","))
  ), file.path(imd, sprintf("Figure 3. RCS of cumulative %s and osteoporosis.md", index)))

  writeLines(c(
    sprintf("# Figure S1. RCS cumulative %s Cox HR", index), "",
    "## 图面说明",
    "面板同 Fig3；Cox HR；futime = W8−W6 访视年月（Harmonized ELSA）。结局仍为 Wave8 二分类骨质疏松。",
    "",
    "## 分析上下文",
    sprintf("Model3=%s。N=%s。ELSA。", paste(covars, collapse = "+"), format(nrow(data), big.mark = ","))
  ), file.path(imd, sprintf("Figure S1. RCS cumulative %s Cox HR.md", index)))

  writeLines(c(
    sprintf("# Figure S2. Cumulative %s subgroup HR", index), "",
    "## 图面说明",
    "亚组森林（Cox，per 1-SD）。Smoke/Drink 水平为 Never/Ever；CI 用 en-dash，与主表一致。",
    "",
    "## 分析上下文",
    sprintf("Model3=%s。Overall n 为 Model3 完整病例。ELSA。", paste(covars, collapse = "+"))
  ), file.path(imd, sprintf("Figure S2. Cumulative %s subgroup HR.md", index)))

  writeLines(c(
    sprintf("# Figure S3. Cumulative %s subgroup OR", index), "",
    "## 图面说明",
    "亚组森林（Logistic，per 1-SD）。标签/CI 格式与 Table3 / Fig S2 对齐。",
    "",
    "## 分析上下文",
    sprintf("Model3=%s。与 Table2 连续行（per 1-unit）量纲不同。ELSA。", paste(covars, collapse = "+"))
  ), file.path(imd, sprintf("Figure S3. Cumulative %s subgroup OR.md", index)))

  # Table2 footnote surgical: RCS note + CC n（若表存在）
  t2 <- file.path(.tab, sprintf(
    "Table 2. Associations of %s patterns and cumulative %s with osteoporosis.xlsx", index, index
  ))
  if (file.exists(t2)) {
    tryCatch({
      suppressPackageStartupMessages(library(openxlsx))
      d <- openxlsx::read.xlsx(t2, colNames = FALSE)
      # replace eGDR labels if any
      wb <- openxlsx::loadWorkbook(t2)
      sh <- names(wb)[1]
      for (i in seq_len(nrow(d))) {
        v <- as.character(d[i, 1])
        if (is.na(v)) next
        if (identical(v, "eGDR change patterns")) {
          openxlsx::writeData(wb, sh, "WWI change patterns", startCol = 1, startRow = i, colNames = FALSE)
          if (!identical(index, "WWI")) {
            openxlsx::writeData(wb, sh, sprintf("%s change patterns", index),
                                startCol = 1, startRow = i, colNames = FALSE)
          }
        }
        if (identical(v, "Cumulative eGDR")) {
          openxlsx::writeData(wb, sh, sprintf("Cumulative %s", index),
                              startCol = 1, startRow = i, colNames = FALSE)
        }
        if (identical(v, "Tertiles of cumulative eGDR")) {
          openxlsx::writeData(wb, sh, sprintf("Tertiles of cumulative %s", index),
                              startCol = 1, startRow = i, colNames = FALSE)
        }
      }
      m3_cols <- unique(c("Osteoporosis", "cum_eGDR", covars))
      m3_ok <- stats::complete.cases(data[, intersect(m3_cols, names(data)), drop = FALSE])
      note_cc <- sprintf(
        "Analytic N = %s. Model 3 complete-case N = %s (events = %s) for adjusted estimates.",
        format(n_analytic, big.mark = ","),
        format(sum(m3_ok), big.mark = ","),
        format(sum(as.integer(as.numeric(data$Osteoporosis[m3_ok]) == 1L), na.rm = TRUE), big.mark = ",")
      )
      # Prefer analytic from class table if available — use nrow before futime filter stored
      # find Analytic N row or append（不改 Fig3 RCS vs 线性 P 口径）
      hit <- which(grepl("^Analytic N", as.character(d[[1]])))
      if (length(hit)) {
        openxlsx::writeData(wb, sh, note_cc, startCol = 1, startRow = hit[1], colNames = FALSE)
      } else {
        openxlsx::writeData(wb, sh, note_cc,
                            startCol = 1, startRow = nrow(d) + 1L, colNames = FALSE)
      }
      openxlsx::saveWorkbook(wb, t2, overwrite = TRUE)
      message("  Table2 footnotes updated")
    }, error = function(e) message("  Table2 footnote skip: ", conditionMessage(e)))
  }

  invisible(TRUE)
}

for (ix in .indices) {
  ok <- tryCatch(.redraw_one(ix), error = function(e) {
    message("FAIL ", ix, ": ", conditionMessage(e)); FALSE
  })
  if (!isTRUE(ok)) message("… continued")
}
message("ALL DONE")
