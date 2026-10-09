###############################################################################
#  ml_nafld_score_compare — 最佳模型 vs HSI/ZJU/TyG（Table 6 / Figure 5）
#
#  register_block: "ml_nafld_score_compare"
###############################################################################

block_ml_nafld_score_compare <- function(ctx, ...) {
  cfg <- ctx$config
  common <- file.path(getwd(), "Blocks/73_ml_nafld_cm/00ml_nafld_cm_common.R")
  if (!file.exists(common)) {
    common <- file.path(
      cfg$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd()),
      "Blocks/73_ml_nafld_cm/00ml_nafld_cm_common.R"
    )
  }
  if (file.exists(common)) source(common, local = FALSE)
  polish <- file.path(
    cfg$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd()),
    "Blocks/73_ml_nafld_cm/05ml_nafld_cm_pub_polish.R"
  )
  if (!file.exists(polish)) polish <- file.path(getwd(), "Blocks/73_ml_nafld_cm/05ml_nafld_cm_pub_polish.R")
  if (file.exists(polish)) source(polish, local = FALSE)
  .nafld_cm_ensure_dirs(cfg)

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("ml_nafld_score_compare: 无数据", call. = FALSE)
  oc <- cfg$data$outcome_column %||% "Disease"
  pos <- cfg$project$analysis_group %||% "NAFLD"
  y <- .nafld_cm_outcome01(data[[oc]], pos)

  scores <- as.character((cfg$baseline_scores %||% list())$scores %||% c("HSI", "ZJU", "TyG"))
  scores <- intersect(scores, names(data))
  rows <- list()
  for (s in scores) {
    v <- as.numeric(data[[s]])
    ok <- is.finite(v) & !is.na(y)
    if (sum(ok) < 20L || length(unique(y[ok])) < 2L) next
    met <- .nafld_cm_youden_metrics(y[ok], v[ok])
    # 评分方向：HSI/ZJU/TyG 越高风险越大，与 roc direction="<"（高=阳性）一致
    rows[[length(rows) + 1L]] <- data.frame(
      model = s, type = "traditional_score",
      auc = met$auc, sens = met$sens, spec = met$spec, thr = met$thr,
      stringsAsFactors = FALSE
    )
  }
  best <- .nafld_cm_best_from_table4(cfg)
  if (is.null(best)) best <- ctx$results$nafld_nested_cv$best
  if (!is.null(best) && nrow(best)) {
    rows[[length(rows) + 1L]] <- data.frame(
      model = paste0(best$space, "+", best$algorithm),
      type = "nested_cv_best_mean_auc",
      auc = best$auc_mean, sens = NA_real_, spec = NA_real_, thr = NA_real_,
      stringsAsFactors = FALSE
    )
  }
  tab <- do.call(rbind, rows)
  out <- .nafld_cm_out_dirs(cfg)
  utils::write.csv(tab, file.path(out$tables, "Table 6. Best model vs HSI ZJU TyG.csv"),
                   row.names = FALSE, fileEncoding = "UTF-8")
  if (nrow(tab) && requireNamespace("ggplot2", quietly = TRUE)) {
    p <- ggplot2::ggplot(tab, ggplot2::aes(x = reorder(model, auc), y = auc, fill = type)) +
      ggplot2::geom_col() +
      ggplot2::coord_flip() +
      ggplot2::labs(title = NULL, x = NULL, y = "AUC") +
      ggplot2::theme_minimal(base_size = 12)
    # Figure 5 由 pub_finalize 写入 summary；此处仅保留 step 副本
    ggplot2::ggsave(file.path(out$figures, "_step_Figure 5. AUC vs traditional scores.pdf"),
                    p, width = 7, height = 4)
  }
  cli::cli_alert_success("Table 6 / Figure 5 已写出（n_models={nrow(tab)}）")
  ctx$results$nafld_score_compare <- tab
  ctx
}

if (exists("register_block", mode = "function")) {
  register_block(
    "ml_nafld_score_compare",
    block_ml_nafld_score_compare,
    "NAFLD 最佳模型 vs HSI/ZJU/TyG"
  )
}
