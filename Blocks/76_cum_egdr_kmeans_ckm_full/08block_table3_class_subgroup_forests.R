###############################################################################
# table3_class_subgroup_forests — unit 级 Table3 / 亚组森林草稿
# 发表 Table3（Class2 ref wide）→ ckm_stroke_build_table3_subgroup()
# 发表 Fig S2/S3 Free-Statistics → ckm_stroke_forest_free_stats()
# 定稿入口：run/cum_egdr_kmeans_ckm/rebuild_publication.R
###############################################################################

block_table3_class_subgroup_forests <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_ckm_cum_egdr.R"), local = FALSE)
  bl <- ctx$config$cum_egdr_kmeans %||% list()
  idx <- ctx$config$incidence$index_var %||% "eGDR"
  data <- ctx$data$imputed %||% ctx$data$cleaned
  outcome <- ctx$config$data$outcome_column %||% "Stroke"
  if (is.null(data) || !outcome %in% names(data)) return(ctx)

  tab_dir <- file.path(ctx$config$project$output_dir %||% "Output", "by_index", idx, "Tables")
  fig_dir <- file.path(ctx$config$project$output_dir %||% "Output", "by_index", idx, "Figures")
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

  data <- ckm_stroke_add_futime(data)
  data <- ckm_stroke_prepare_age_group(data, ctx$config$subgroup$age_cutoff %||% 60L)
  models <- ctx$results$ckm_model_sets %||%
    ckm_stroke_model_sets(bl, data, index_name = idx, outcome = outcome)
  cov3 <- models$Model3

  sub_vars <- as.character(ctx$config$subgroup$required_subgroup_vars %||%
    c("Age", "Gender", "Education", "Smoke", "Drink", "Dyslipidemia", "Diabetes", "CKM_stage"))
  # Age → Age_Group
  sub_vars <- unique(c(setdiff(sub_vars, "Age"), "Age_Group"))
  sub_vars <- intersect(sub_vars, names(data))
  if ("CKM_stage" %in% names(data) && !"CKM_stage" %in% sub_vars)
    sub_vars <- c(sub_vars, "CKM_stage")

  .subgroup_fit_table <- function(d, expo, fit_fun, measure = "OR") {
    rows <- list()
    # Overall
    rr0 <- fit_fun(d, expo, cov3)
    if (!is.null(rr0)) {
      rr0$subgroup <- "Overall"
      rr0$level <- "All"
      rows[[length(rows) + 1L]] <- rr0
    }
    for (sv in sub_vars) {
      lv <- unique(stats::na.omit(as.character(d[[sv]])))
      for (lev in lv) {
        dsub <- d[as.character(d[[sv]]) == lev, , drop = FALSE]
        if (nrow(dsub) < 30L) next
        rr <- fit_fun(dsub, expo, setdiff(cov3, sv))
        if (is.null(rr)) next
        rr$subgroup <- sv
        rr$level <- lev
        rows[[length(rows) + 1L]] <- rr
      }
    }
    if (!length(rows)) return(data.frame())
    out <- do.call(rbind, rows); rownames(out) <- NULL; out
  }

  .simple_forest <- function(tab, file, title, est_col, ci_lo, ci_hi, xlab) {
    if (!nrow(tab)) return(invisible(NULL))
    # 每亚组取首个非参照水平项（Class 多水平时取与 ref 对比的第一行之外的合并展示：取 abs(log) 最大）
    keep <- !grepl(paste0(bl$class_ref %||% "Persistent_low"), tab$term) |
      grepl("cum_|Continuous|eGDR$", tab$term)
    # 连续暴露 term 通常就是变量名
    if (all(grepl("^cum_|^eGDR$|Continuous", tab$term)) || mean(grepl("cum_|eGDR$", tab$term)) > 0.5) {
      plot_df <- tab
    } else {
      # Class: 每个 subgroup×level 选一个代表性对比（Stable_high 优先，否则第一非空）
      plot_df <- do.call(rbind, lapply(split(tab, paste(tab$subgroup, tab$level, sep = "||")), function(x) {
        hit <- grep("Stable_high|Rapid_decrease|Moderate", x$term)
        if (!length(hit)) hit <- seq_len(nrow(x))
        x[hit[1L], , drop = FALSE]
      }))
      rownames(plot_df) <- NULL
    }
    if (!nrow(plot_df)) return(invisible(NULL))
    labs <- paste0(plot_df$subgroup, ": ", plot_df$level)
    est <- plot_df[[est_col]]; lo <- plot_df[[ci_lo]]; hi <- plot_df[[ci_hi]]
    ok <- is.finite(est) & is.finite(lo) & is.finite(hi)
    labs <- labs[ok]; est <- est[ok]; lo <- lo[ok]; hi <- hi[ok]
    if (!length(est)) return(invisible(NULL))
    pdf(file, width = 7, height = max(4, 0.35 * length(est) + 1.5))
    op <- par(mar = c(4, 12, 3, 2))
    xlim <- range(c(lo, hi, 1), finite = TRUE)
    if (!all(is.finite(xlim)) || diff(xlim) == 0) xlim <- c(0.5, 2)
    plot(est, seq_along(est), pch = 16, xlim = xlim, ylim = c(0.5, length(est) + 0.5),
         xlab = xlab, ylab = "", yaxt = "n", main = title, log = "x")
    segments(lo, seq_along(est), hi, seq_along(est))
    abline(v = 1, lty = 2, col = "grey40")
    axis(2, at = seq_along(est), labels = labs, las = 1, cex.axis = 0.7)
    par(op)
    dev.off()
    invisible(NULL)
  }

  # ---- Table 3: Class logistic subgroup (Model3) ----
  if ("eGDR_Class" %in% names(data)) {
    d <- data
    d$eGDR_Class <- stats::relevel(factor(d$eGDR_Class), ref = bl$class_ref %||% "Persistent_low")
    t3 <- .subgroup_fit_table(
      d, "eGDR_Class",
      function(dd, expo, cov) ckm_stroke_fit_or_row(dd, expo, outcome, cov)
    )
    if (nrow(t3)) {
      utils::write.csv(t3, file.path(tab_dir, "Table 3. Subgroup Class logistic.csv"),
                       row.names = FALSE)
      .simple_forest(
        t3,
        file.path(fig_dir, "Figure. Table3 Class subgroup forest OR.pdf"),
        "Table 3 Class subgroup (OR)", "OR", "CI_low", "CI_high", "OR"
      )
    }
  }

  cont_col <- if ("cum_eGDR" %in% names(data)) "cum_eGDR" else idx
  # ---- Fig.S3: cum eGDR logistic subgroup OR ----
  if (cont_col %in% names(data)) {
    s3or <- .subgroup_fit_table(
      data, cont_col,
      function(dd, expo, cov) ckm_stroke_fit_or_row(dd, expo, outcome, cov)
    )
    if (nrow(s3or)) {
      utils::write.csv(s3or, file.path(tab_dir, "Table. FigS3 cum eGDR subgroup OR.csv"),
                       row.names = FALSE)
      .simple_forest(
        s3or,
        file.path(fig_dir, "Figure S3. Cumulative eGDR subgroup OR.pdf"),
        "Fig.S3 cum eGDR subgroup (OR)", "OR", "CI_low", "CI_high", "OR"
      )
    }
    # ---- Fig.S2: cum eGDR Cox subgroup HR ----
    if (all(c("futime", "status") %in% names(data))) {
      s2hr <- .subgroup_fit_table(
        data, cont_col,
        function(dd, expo, cov) ckm_stroke_fit_hr_row(dd, expo, cov)
      )
      if (nrow(s2hr)) {
        utils::write.csv(s2hr, file.path(tab_dir, "Table. FigS2 cum eGDR subgroup HR.csv"),
                         row.names = FALSE)
        .simple_forest(
          s2hr,
          file.path(fig_dir, "Figure S2. Cumulative eGDR subgroup HR.pdf"),
          "Fig.S2 cum eGDR subgroup (HR)", "HR", "CI_low", "CI_high", "HR"
        )
      }
    }
  }

  ctx$results$table3_class_subgroup_forests <- list(ok = TRUE)
  cli::cli_alert_success("Table 3 / Fig.S2 / Fig.S3 亚组已写出")
  ctx
}

register_block(
  "table3_class_subgroup_forests",
  block_table3_class_subgroup_forests,
  "Table3 Class与cum亚组森林"
)
