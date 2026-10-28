###############################################################################
# sensitivity_cox_mice_bundle — Table S1–S4 + Fig.S1（Cox RCS）
# 协变量：优先 ctx$results$ckm_model_sets（与 Table2 同源；可 uv_vif）
###############################################################################

block_sensitivity_cox_mice_bundle <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_ckm_cum_egdr.R"), local = FALSE)
  bl <- ctx$config$cum_egdr_kmeans %||% list()
  idx <- ctx$config$incidence$index_var %||% "eGDR"
  data <- ctx$data$imputed %||% ctx$data$cleaned
  outcome <- ctx$config$data$outcome_column %||% "Stroke"
  tab_dir <- file.path(ctx$config$project$output_dir %||% "Output", "by_index", idx, "Tables")
  fig_dir <- file.path(ctx$config$project$output_dir %||% "Output", "by_index", idx, "Figures")
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

  if (is.null(data) || !outcome %in% names(data)) {
    writeLines("sensitivity skipped: no data", file.path(tab_dir, "Sensitivity_bundle_README.txt"))
    return(ctx)
  }

  data <- ckm_stroke_add_futime(data)
  models <- ctx$results$ckm_model_sets %||%
    ckm_stroke_model_sets(bl, data, index_name = idx, outcome = outcome)
  note <- c(
    sprintf("Sensitivity bundle covariates [%s]:", bl$covariate_mode %||% "fixed"),
    paste0("Model2=", paste(models$Model2, collapse = "+")),
    paste0("Model3=", paste(models$Model3, collapse = "+"))
  )

  .bundle_rows <- function(fit_fun, data, models, blocks) {
    rows <- list()
    for (bn in names(blocks)) {
      expo <- blocks[[bn]]
      if (is.null(expo) || !expo %in% names(data)) next
      d <- data
      if (is.factor(d[[expo]]) || is.character(d[[expo]])) {
        if (identical(expo, "eGDR_Class")) {
          d[[expo]] <- stats::relevel(factor(d[[expo]]), ref = bl$class_ref %||% "Persistent_low")
        } else if (grepl("tertile", expo, ignore.case = TRUE)) {
          d[[expo]] <- stats::relevel(factor(d[[expo]]), ref = "T1")
        } else {
          d[[expo]] <- factor(d[[expo]])
        }
      }
      for (mn in c("Model1", "Model2", "Model3")) {
        rr <- fit_fun(d, expo, models[[mn]])
        if (!is.null(rr)) {
          rr$block <- bn
          rr$model <- mn
          rows[[length(rows) + 1L]] <- rr
        }
      }
    }
    if (!length(rows)) return(data.frame())
    out <- do.call(rbind, rows); rownames(out) <- NULL; out
  }

  blocks_expo <- list()
  if (ckm_stroke_is_full_depth(idx, bl) && "eGDR_Class" %in% names(data))
    blocks_expo$Class <- "eGDR_Class"
  cont_col <- if (ckm_stroke_is_full_depth(idx, bl) && "cum_eGDR" %in% names(data)) "cum_eGDR" else idx
  if (cont_col %in% names(data)) blocks_expo$Continuous <- cont_col
  tert_col <- if ("eGDR_tertile" %in% names(data)) "eGDR_tertile" else NULL
  if (!is.null(tert_col)) blocks_expo$Tertile <- tert_col

  # ---- Table S1 Cox complete-case ----
  cox_s1 <- .bundle_rows(
    function(d, expo, cov) ckm_stroke_fit_hr_row(d, expo, cov),
    data, models, blocks_expo
  )
  if (nrow(cox_s1)) {
    utils::write.csv(cox_s1, file.path(tab_dir, "Table S1. Cox Class Continuous Tertile.csv"),
                     row.names = FALSE)
    note <- c(note, sprintf("- Table S1 Cox rows=%d", nrow(cox_s1)))
  } else {
    note <- c(note, "- Table S1 Cox empty (check futime/status)")
  }

  # ---- Table S2 Cox subgroup (Class or continuous; Model3) ----
  data <- ckm_stroke_prepare_age_group(data, ctx$config$subgroup$age_cutoff %||% 60L)
  sub_vars <- intersect(
    as.character(ctx$config$subgroup$required_subgroup_vars %||%
                   c("Age_Group", "Gender", "Education", "Smoke", "Drink",
                     "Dyslipidemia", "Diabetes", "CKM_stage")),
    names(data)
  )
  if ("Age" %in% sub_vars && "Age_Group" %in% names(data)) {
    sub_vars <- unique(c(setdiff(sub_vars, "Age"), "Age_Group"))
  }
  expo_s2 <- if ("eGDR_Class" %in% names(data)) "eGDR_Class" else cont_col
  s2_rows <- list()
  if (expo_s2 %in% names(data) && length(sub_vars)) {
    d0 <- data
    if (identical(expo_s2, "eGDR_Class")) {
      d0[[expo_s2]] <- stats::relevel(factor(d0[[expo_s2]]),
                                        ref = bl$class_ref %||% "Persistent_low")
    }
    for (sv in sub_vars) {
      lv <- unique(stats::na.omit(as.character(d0[[sv]])))
      for (lev in lv) {
        dsub <- d0[as.character(d0[[sv]]) == lev, , drop = FALSE]
        rr <- ckm_stroke_fit_hr_row(dsub, expo_s2, models$Model3)
        if (!is.null(rr)) {
          rr$subgroup <- sv
          rr$level <- lev
          s2_rows[[length(s2_rows) + 1L]] <- rr
        }
      }
    }
  }
  if (length(s2_rows)) {
    s2 <- do.call(rbind, s2_rows); rownames(s2) <- NULL
    utils::write.csv(s2, file.path(tab_dir, "Table S2. Cox subgroup.csv"), row.names = FALSE)
    note <- c(note, sprintf("- Table S2 Cox subgroup rows=%d", nrow(s2)))
  }

  # ---- MICE: Table S3 Cox / Table S4 logistic ----
  # 发表 S3/S4 只由 rebuild 用 mice::pool（Rubin）写出。
  # 禁止在本 block 里把完整病例行复制成 “after MICE”，也禁止用几何均 OR 冒充 Rubin。
  note <- c(
    note,
    "- Publication Table S3/S4 are written by rebuild_publication (ckm_stroke_prepare_mice + mice::pool). This block does not emit them."
  )

  # ---- Fig.S1 Cox RCS (HR) ----
  if (requireNamespace("rms", quietly = TRUE) && cont_col %in% names(data) &&
      all(c("futime", "status") %in% names(data))) {
    if (!"package:rms" %in% search()) suppressPackageStartupMessages(library(rms))
    if (!"package:survival" %in% search()) suppressPackageStartupMessages(library(survival))
    covars <- models$Model3
    d <- data[, unique(c("futime", "status", cont_col, covars)), drop = FALSE]
    for (cv in covars) if (is.character(d[[cv]])) d[[cv]] <- factor(d[[cv]])
    d <- d[stats::complete.cases(d), , drop = FALSE]
    if (nrow(d) >= 80L && sum(d$status) >= 10L) {
      assign("dd_s1", rms::datadist(d), envir = .GlobalEnv)
      options(datadist = "dd_s1")
      rhs <- paste(c(sprintf("rcs(%s, 4)", cont_col), covars), collapse = " + ")
      fml <- stats::as.formula(paste("Surv(futime, status) ~", rhs))
      fit <- tryCatch(
        cph(fml, data = d, x = TRUE, y = TRUE, surv = TRUE),
        error = function(e) {
          cli::cli_alert_warning("Fig.S1 cph fail: {e$message}")
          NULL
        }
      )
      if (!is.null(fit)) {
        pp <- tryCatch(Predict(fit, name = cont_col, fun = exp), error = function(e) NULL)
        pdf(file.path(fig_dir, "Figure S1. RCS cumulative index Cox HR.pdf"),
            width = 5.5, height = 4.2)
        if (!is.null(pp)) {
          x <- pp[[1L]]; y <- pp$yhat; lo <- pp$lower; hi <- pp$upper
          plot(x, y, type = "n", ylim = range(c(lo, hi), na.rm = TRUE),
               xlab = cont_col, ylab = "HR", main = "Fig.S1 RCS (Cox)")
          polygon(c(x, rev(x)), c(lo, rev(hi)),
                  col = grDevices::adjustcolor("darkred", 0.25), border = NA)
          lines(x, y, col = "darkred", lwd = 2)
          abline(h = 1, lty = 2, col = "grey40")
        } else plot.new()
        dev.off()
        note <- c(note, "- Figure S1 Cox RCS written")
      }
    }
  }

  writeLines(note, file.path(tab_dir, "Sensitivity_bundle_README.txt"))
  ctx$results$sensitivity_cox_mice_bundle <- list(note = note, cox_s1 = cox_s1)
  cli::cli_alert_success("敏感性捆 S1–S4 / Fig.S1 已写出")
  ctx
}

register_block("sensitivity_cox_mice_bundle", block_sensitivity_cox_mice_bundle, "Cox/MICE敏感性捆")
