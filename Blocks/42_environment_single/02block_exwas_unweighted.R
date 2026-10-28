###############################################################################
#  exwas_unweighted — 不加权暴露组关联（逐暴露 logistic + BH-FDR）
#
#  register_block: "exwas_unweighted"
#  对标文献：ExWAS 报告 unweighted，避免与人口学协变量过调整。
#  描述、ERS、RCS、亚组、中介不在本块加权。
#
#  config$exwas_unweighted = list(
#    covariates = c("RIDAGEYR", "RIAGENDR"),
#    seed_impute = 123456L,
#    mice_m = 5L,
#    mice_maxit = 5L
#  )
###############################################################################

block_exwas_unweighted <- function(ctx, ...) {
  root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  source(file.path(root, "R/environment_exwas_core.R"), local = FALSE)
  cfg <- ctx$config$exwas_unweighted %||% list()
  df <- ctx$data$cleaned
  y <- ctx$results$exwas_outcome %||% "DN"
  covars <- cfg$covariates %||% intersect(c("RIDAGEYR", "RIAGENDR"), names(df))
  if (identical(ctx$results$exwas_mode, "nutrition")) {
    exposure_cols <- ctx$results$exwas_exposure_cols
    screened <- exwas_screen_nutrition(df, exposure_cols)
  } else {
    exposure_cols <- names(df)[vapply(names(df), exwas_is_environmental_col, logical(1))]
    exposure_cols <- exwas_dedupe_units(exposure_cols)
    screened <- exwas_screen_transform(df, exposure_cols)
  }
  df <- screened$data
  keep <- screened$keep
  if (!length(keep)) stop("没有通过检出限/缺失筛的环境暴露列", call. = FALSE)
  # 各毒物来自不同子样本。不对「未抽中」的人做全库 mice。
  ctx$data$imputed <- df
  ctx$results$exwas_exposures <- keep
  ctx$results$exwas_screen <- screened$notes
  only <- cfg$only_exposures
  run_x <- if (length(only)) intersect(keep, only) else keep
  tab <- exwas_run_unweighted(df, y, run_x, covars)
  ctx$results$exwas_table <- tab
  out <- ctx$config$project$output_dir %||% "Output/exwas"
  exwas_ensure_dir(out)
  utils::write.csv(screened$notes, file.path(out, "Table_S1_exposure_screen.csv"), row.names = FALSE)
  utils::write.csv(tab, file.path(out, "Table_2_ExWAS_unweighted.csv"), row.names = FALSE)
  if (requireNamespace("ggplot2", quietly = TRUE)) {
    plot_df <- tab[is.finite(tab$p), , drop = FALSE]
    if (nrow(plot_df)) {
      plot_df$logp <- -log10(pmax(plot_df$p, 1e-300))
      plot_df$hit <- ifelse(!is.na(plot_df$q) & plot_df$q < 0.05, "FDR<0.05", "other")
      p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = log(OR), y = logp, color = hit)) +
        ggplot2::geom_point() +
        ggplot2::theme_bw() +
        ggplot2::labs(x = "log(OR per IQR or detectable)", y = "-log10(p)", title = "ExWAS")
      ggplot2::ggsave(file.path(out, "Figure_2_ExWAS_volcano.pdf"), p, width = 7, height = 5)
    }
  }
  exwas_log("ExWAS 完成，暴露数=", nrow(tab),
            " FDR<0.05=", sum(tab$q < 0.05, na.rm = TRUE))
  ctx
}

register_block(
  "exwas_unweighted",
  block_exwas_unweighted,
  "不加权 ExWAS：逐暴露 logistic 与 BH-FDR"
)
