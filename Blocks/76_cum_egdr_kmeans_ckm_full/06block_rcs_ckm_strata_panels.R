###############################################################################
# rcs_ckm_strata_panels — Fig.3 全体 + CKM0-2 / 3-4 RCS（OR）
###############################################################################

block_rcs_ckm_strata_panels <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_ckm_cum_egdr.R"), local = FALSE)
  bl <- ctx$config$cum_egdr_kmeans %||% list()
  idx <- ctx$config$incidence$index_var %||% "eGDR"
  data <- ctx$data$imputed %||% ctx$data$cleaned
  outcome <- ctx$config$data$outcome_column %||% "Stroke"
  if (is.null(data)) return(ctx)

  xcol <- if (ckm_stroke_is_full_depth(idx, bl) && "cum_eGDR" %in% names(data)) "cum_eGDR" else idx
  if (!all(c(xcol, outcome) %in% names(data))) {
    cli::cli_alert_warning("rcs panels: 缺 {xcol}/{outcome}")
    return(ctx)
  }
  if (!requireNamespace("rms", quietly = TRUE)) {
    cli::cli_alert_warning("未安装 rms，跳过 RCS 面板")
    return(ctx)
  }
  if (!"package:rms" %in% search()) suppressPackageStartupMessages(library(rms))
  if (!"package:survival" %in% search()) suppressPackageStartupMessages(library(survival))

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "by_index", idx, "Figures")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  models <- ctx$results$ckm_model_sets %||%
    ckm_stroke_model_sets(bl, data, index_name = idx, outcome = outcome)
  covars <- intersect(as.character(models$Model3 %||% bl$model3 %||% c("Age", "Gender")), names(data))

  .plot_pred <- function(pp, title, ylab = "OR") {
    x <- pp[[1L]]; y <- pp$yhat; lo <- pp$lower; hi <- pp$upper
    plot(x, y, type = "n", ylim = range(c(lo, hi), na.rm = TRUE),
         xlab = xcol, ylab = ylab, main = title)
    polygon(c(x, rev(x)), c(lo, rev(hi)),
            col = grDevices::adjustcolor("steelblue", 0.25), border = NA)
    lines(x, y, col = "steelblue", lwd = 2)
    abline(h = 1, lty = 2, col = "grey40")
  }

  .fit_panel <- function(d, title) {
    keep <- unique(c(outcome, xcol, covars))
    d <- d[, keep, drop = FALSE]
    for (cv in covars) if (is.character(d[[cv]])) d[[cv]] <- factor(d[[cv]])
    d <- d[stats::complete.cases(d), , drop = FALSE]
    if (nrow(d) < 80L || length(unique(d[[outcome]])) < 2L) {
      plot.new(); title(main = paste0(title, " (n low)")); return(invisible(NULL))
    }
    ddist_name <- paste0("dd_", gsub("[^A-Za-z0-9]", "_", title))
    assign(ddist_name, rms::datadist(d), envir = .GlobalEnv)
    options(datadist = ddist_name)
    rhs <- paste(c(sprintf("rcs(%s, 4)", xcol), covars), collapse = " + ")
    fml <- stats::as.formula(paste(outcome, "~", rhs))
    fit <- tryCatch(lrm(fml, data = d, x = TRUE, y = TRUE), error = function(e) {
      cli::cli_alert_warning("RCS lrm fail [{title}]: {e$message}"); NULL
    })
    if (is.null(fit)) { plot.new(); title(main = paste0(title, " (fit fail)")); return(invisible(NULL)) }
    pp <- tryCatch(Predict(fit, name = xcol, fun = exp), error = function(e) NULL)
    if (is.null(pp)) { plot.new(); title(main = title); return(invisible(NULL)) }
    .plot_pred(pp, title, "OR")
    invisible(fit)
  }

  pdf(file.path(out_dir, "Figure 3. RCS cumulative index by CKM strata.pdf"), width = 11, height = 3.8)
  op <- par(mfrow = c(1, 3))
  .fit_panel(data, "All CKM 0-4")
  if ("CKM_stage" %in% names(data)) {
    .fit_panel(data[data$CKM_stage %in% c(0L, 1L, 2L), , drop = FALSE], "CKM 0-2")
    .fit_panel(data[data$CKM_stage %in% c(3L, 4L), , drop = FALSE], "CKM 3-4")
  } else {
    plot.new(); title("CKM 0-2 (no stage)")
    plot.new(); title("CKM 3-4 (no stage)")
  }
  par(op)
  dev.off()
  ctx$results$rcs_ckm_strata_panels <- list(x = xcol, ok = TRUE)
  cli::cli_alert_success("Fig.3 RCS panels written")
  ctx
}

register_block("rcs_ckm_strata_panels", block_rcs_ckm_strata_panels, "RCS CKM分层三面板")
