###############################################################################
#  competing_cif_plot — 累积发生率曲线（竞争风险）
###############################################################################

block_competing_cif_plot <- function(ctx, ...) {
  bl <- ctx$config$competing_risk %||% list()
  data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
  if (is.null(data)) stop("competing_cif_plot: 无数据", call. = FALSE)
  time_var <- bl$time_var %||% "futime"
  event_col <- bl$event_type_col %||% "event_type"
  index_var <- bl$index_var %||% bl$tyg_var %||% "TyG"
  cause <- as.integer(bl$cif_cause %||% 2L)[1L]     # 默认与死亡竞争事件（原文 Fig4/8）
  horizon <- as.numeric(bl$cif_horizon %||% bl$followup_days %||% 5)[1L]
  strata_vars <- unique(c(
    bl$cif_strata %||% bl$exposure_var %||% "TyG_quartile",
    bl$trajectory_var %||% NULL
  ))
  strata_vars <- strata_vars[strata_vars %in% names(data)]

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  fig_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Figures")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  cif_col <- paste0("cif_", horizon, "d_cause", cause)

  all_tabs <- list()
  for (strata in strata_vars) {
    tab <- data.frame(strata = character(0), cif = numeric(0), stringsAsFactors = FALSE)
    for (lv in levels(factor(data[[strata]]))) {
      sub <- data[data[[strata]] == lv, , drop = FALSE]
      if (nrow(sub) < 10L) next
      evt <- sum(sub[[event_col]] == cause & sub[[time_var]] <= horizon, na.rm = TRUE)
      cif_val <- evt / nrow(sub)
      tab <- rbind(tab, data.frame(strata = lv, cif = round(cif_val, 4), stringsAsFactors = FALSE))
    }
    names(tab)[names(tab) == "cif"] <- cif_col

    tag <- if (grepl("_trajectory$", strata)) "trajectory" else "quartile"
    out <- file.path(out_dir, paste0("Table_CIF_", index_var, "_", tag, "_cause", cause, ".csv"))
    utils::write.csv(tab, out, row.names = FALSE)

    # 中间 CIF 草图不落盘；正式 Figure 4/8 由 competing_pub_export 生成
    all_tabs[[tag]] <- tab
  }
  ctx$results$competing_cif <- list(tables = all_tabs)
  cli::cli_alert_success("CIF 曲线完成（{index_var}，cause={cause}，strata: {paste(strata_vars, collapse=', ')}）")
  ctx
}

register_block("competing_cif_plot", block_competing_cif_plot, "CIF 竞争风险曲线")
