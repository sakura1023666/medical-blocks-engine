###############################################################################
#  multimorbidity_gee_trajectory — 联合轨迹组 × 结局 GEE + 森林图
#
#  register_block: "multimorbidity_gee_trajectory"
###############################################################################

.mm_gee_fit_models_traj <- function(data, outcome, exposure, time_col, id_col, cov_lists, family) {
  fam <- if (identical(family, "binomial")) stats::binomial() else stats::gaussian()
  rows <- list()
  for (nm in names(cov_lists)) {
    covs <- unique(c(exposure, time_col, cov_lists[[nm]]))
    covs <- covs[covs %in% names(data)]
    form <- stats::as.formula(paste(outcome, "~", paste(covs, collapse = " + ")))
    fit <- tryCatch(
      geepack::geeglm(form, data = data, id = data[[id_col]], family = fam, corstr = "exchangeable"),
      error = function(e) NULL
    )
    if (is.null(fit)) next
    sm <- summary(fit)$coefficients
    se <- sm[, "Std.err"]
    tab <- data.frame(
      model = nm,
      term = rownames(sm),
      beta = sm[, "Estimate"],
      se = se,
      lo95 = sm[, "Estimate"] - 1.96 * se,
      hi95 = sm[, "Estimate"] + 1.96 * se,
      p = sm[, "Pr(>|W|)"],
      stringsAsFactors = FALSE
    )
    rows[[nm]] <- tab
  }
  if (!length(rows)) return(NULL)
  do.call(rbind, rows)
}

block_multimorbidity_gee_trajectory <- function(ctx, ...) {
  bl <- ctx$config$multimorbidity_gee %||% list()
  mm <- ctx$config$multimorbidity %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("multimorbidity_gee_trajectory: 无数据", call. = FALSE)
  if (!requireNamespace("geepack", quietly = TRUE)) {
    utils::install.packages("geepack", repos = "https://cloud.r-project.org", quiet = TRUE)
  }
  suppressPackageStartupMessages(library(geepack))

  cl_col <- as.character(mm$trajectory_cluster_col %||% "trajectory_cluster")[1L]
  out_col <- as.character(bl$outcome_col %||% bl$cognition_col %||% "Cognition_z")[1L]
  time_col <- as.character(bl$time_col %||% "Followup_wave")[1L]
  id_col <- as.character(mm$id_col %||% ctx$config$data$id_column %||% "ID")[1L]
  fam <- as.character(bl$family %||% "gaussian")[1L]
  ref <- as.character(bl$ref_trajectory %||% NA_character_)[1L]

  if (!cl_col %in% names(data)) stop("缺轨迹列 ", cl_col, "；请先跑 kml3d", call. = FALSE)
  data <- data[!is.na(data[[cl_col]]), , drop = FALSE]
  data[[cl_col]] <- factor(as.character(data[[cl_col]]))
  if (!nzchar(ref) || is.na(ref) || !ref %in% levels(data[[cl_col]])) {
    ref <- levels(data[[cl_col]])[1L]
  }
  data[[cl_col]] <- stats::relevel(data[[cl_col]], ref = ref)

  cov_m1 <- as.character(bl$covariates_m1 %||% character(0))
  cov_m2 <- as.character(bl$covariates_m2 %||% c("Age", "Gender"))
  cov_m3 <- as.character(bl$covariates_m3 %||% c("Age", "Gender", "Education", "Hypertension", "Diabetes"))
  cov_lists <- list(
    Model1 = cov_m1,
    Model2 = unique(c(cov_m1, cov_m2)),
    Model3 = unique(c(cov_m1, cov_m2, cov_m3))
  )

  tab <- .mm_gee_fit_models_traj(data, out_col, cl_col, time_col, id_col, cov_lists, fam)
  if (is.null(tab)) stop("multimorbidity_gee_trajectory: GEE 失败", call. = FALSE)

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  fig <- file.path(ctx$config$project$output_dir %||% "Output", "Figures", "pdf")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, file.path(out_dir, "Table_GEE_Trajectory_Multimorbidity.csv"), row.names = FALSE)

  if (requireNamespace("ggplot2", quietly = TRUE)) {
    fd <- tab[tab$model == "Model3" & grepl(paste0("^", cl_col), tab$term), , drop = FALSE]
    if (nrow(fd)) {
      fd$label <- sub(paste0("^", cl_col), "", fd$term)
      p <- ggplot2::ggplot(fd, ggplot2::aes(x = beta, y = label)) +
        ggplot2::geom_vline(xintercept = 0, linetype = 2, color = "grey50") +
        ggplot2::geom_point(size = 2.5, color = "#2A73BA") +
        ggplot2::geom_errorbarh(ggplot2::aes(xmin = lo95, xmax = hi95), height = 0.2, color = "#2A73BA") +
        ggplot2::theme_bw(base_family = "serif") +
        ggplot2::labs(
          title = "Figure 4. Joint trajectory GEE (Model 3)",
          x = if (identical(fam, "binomial")) "log OR" else "Beta", y = NULL
        )
      ggplot2::ggsave(
        file.path(fig, "Figure 4. Trajectory GEE forest.pdf"), p,
        width = 8, height = max(3, 0.4 * nrow(fd) + 2)
      )
    }
  }

  ctx$results$multimorbidity_gee_trajectory <- list(table = tab, ref = ref)
  cli::cli_alert_success("轨迹组 GEE 完成（ref={ref}; n={nrow(data)}）")
  ctx
}

register_block(
  "multimorbidity_gee_trajectory",
  block_multimorbidity_gee_trajectory,
  "联合轨迹 GEE"
)
