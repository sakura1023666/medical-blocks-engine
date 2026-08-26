###############################################################################
#  modmed_spearman — Yan2026 步1：暴露 / 中介 / 结局 Spearman
#
#  register_block: "modmed_spearman"
###############################################################################

block_modmed_spearman <- function(ctx, ...) {
  root <- ctx$root %||% getwd()
  source(file.path(root, "R/moderated_mediation_process.R"), local = FALSE)
  modmed_ensure_pkgs(c("corrplot", "ggplot2"))

  cfg <- ctx$config
  bl <- cfg$modmed_spearman %||% cfg$modmed %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("modmed_spearman: 无数据", call. = FALSE)

  exposures <- bl$exposures %||% cfg$modmed$exposures
  mediators <- bl$mediators %||% cfg$modmed$mediators
  outcome <- bl$outcome %||% cfg$modmed$outcome %||% "Group_bin"
  if (is.null(exposures) || is.null(mediators)) {
    stop("modmed_spearman: 需配置 exposures / mediators", call. = FALSE)
  }

  vars <- unique(c(exposures, mediators, outcome))
  vars <- vars[vars %in% names(data)]
  if (length(vars) < 2L) stop("modmed_spearman: 可用变量不足", call. = FALSE)

  num <- data[, vars, drop = FALSE]
  for (v in vars) {
    if (!is.numeric(num[[v]])) num[[v]] <- suppressWarnings(as.numeric(num[[v]]))
  }

  cor_mat <- stats::cor(num, use = "pairwise.complete.obs", method = "spearman")
  p_mat <- matrix(NA_real_, length(vars), length(vars), dimnames = list(vars, vars))
  for (i in seq_along(vars)) {
    for (j in seq_along(vars)) {
      if (i == j) {
        p_mat[i, j] <- 0
      } else if (i < j) {
        tt <- tryCatch(
          stats::cor.test(num[[i]], num[[j]], method = "spearman", exact = FALSE),
          error = function(e) NULL
        )
        p_mat[i, j] <- p_mat[j, i] <- if (is.null(tt)) NA_real_ else tt$p.value
      }
    }
  }

  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir %||% ".", "Tables")
  fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir %||% ".", "Figures")
  dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

  modmed_write_csv(as.data.frame(cor_mat), file.path(tbl_dir, "Table_Spearman_r.csv"))
  modmed_write_csv(as.data.frame(p_mat), file.path(tbl_dir, "Table_Spearman_p.csv"))

  pdf(file.path(fig_dir, "Fig_Spearman_heatmap.pdf"), width = 10, height = 10)
  corrplot::corrplot(
    cor_mat, method = "color", type = "upper",
    tl.col = "black", tl.cex = 0.7, p.mat = p_mat,
    sig.level = 0.05, insig = "blank", diag = FALSE
  )
  grDevices::dev.off()

  ctx$results$modmed_spearman <- list(r = cor_mat, p = p_mat, vars = vars)
  cli::cli_alert_success("modmed_spearman: {length(vars)} 变量 Spearman 完成")
  ctx
}

register_block("modmed_spearman", block_modmed_spearman, "OA Yan2026: Spearman 相关")
