###############################################################################
#  modmed_simple_slopes — Yan2026 步8–9：简单斜率 + Fig.6 类图
#
#  register_block: "modmed_simple_slopes"
###############################################################################

block_modmed_simple_slopes <- function(ctx, ...) {
  root <- ctx$root %||% getwd()
  source(file.path(root, "R/moderated_mediation_process.R"), local = FALSE)
  modmed_ensure_pkgs("ggplot2")

  cfg <- ctx$config
  bl <- cfg$modmed_simple_slopes %||% cfg$modmed %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("modmed_simple_slopes: 无数据", call. = FALSE)

  sig <- ctx$results$modmed_moderation_significant
  if (is.null(sig) || !nrow(sig)) {
    cli::cli_alert_warning("无显著调节，跳过简单斜率")
    ctx$results$modmed_simple_slopes_table <- data.frame()
    return(ctx)
  }

  # 文献 Fig.6 针对 a 路径（X→M）的调节
  a_sig <- sig[sig$path == "a", , drop = FALSE]
  if (!nrow(a_sig)) {
    cli::cli_alert_info("无显著 a 路径交互，改用全部显著调节对做简单斜率")
    a_sig <- unique(sig[, c("exposure", "mediator", "moderator"), drop = FALSE])
    a_sig$path <- "a"
  } else {
    a_sig <- unique(a_sig[, c("exposure", "mediator", "moderator", "path"), drop = FALSE])
  }

  fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir %||% ".", "Figures")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

  rows <- list()
  for (i in seq_len(nrow(a_sig))) {
    x <- as.character(a_sig$exposure[i])
    m <- as.character(a_sig$mediator[i])
    w <- as.character(a_sig$moderator[i])
    if (!all(c(x, m, w) %in% names(data))) next
    one <- tryCatch(
      modmed_simple_slopes_table(data, x, m, w),
      error = function(e) NULL
    )
    if (is.null(one) || !nrow(one)) next
    rows[[length(rows) + 1L]] <- one
    outfile <- file.path(
      fig_dir,
      paste0("Fig6_simple_slopes_", x, "__", m, "__", w, ".pdf")
    )
    tryCatch(
      modmed_plot_simple_slopes(
        one,
        title = paste0("Fig.6-like: ", x, " -> ", m, " by ", w),
        outfile = outfile
      ),
      error = function(e) cli::cli_alert_warning("作图失败: {e$message}")
    )
  }

  tab <- if (length(rows)) do.call(rbind, rows) else data.frame()
  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir %||% ".", "Tables")
  modmed_write_csv(tab, file.path(tbl_dir, "Table_Simple_Slopes.csv"))
  ctx$results$modmed_simple_slopes_table <- tab
  cli::cli_alert_success("简单斜率: {nrow(tab)} 行；图已写入 Figures/")
  ctx
}

register_block("modmed_simple_slopes", block_modmed_simple_slopes, "OA Yan2026: 简单斜率与 Fig.6")
