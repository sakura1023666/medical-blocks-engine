###############################################################################
#  ml_small_sample_table45.R — Table 4/5（内部 CV + hold-out，Bootstrap CI）
#
#  依赖：utils.R, competing_supp_xlsx.R, ml_small_sample_metrics.R
###############################################################################

#' 写 Table 4（内部验证）与 Table 5（hold-out）
#'
#' @param out_dir 含 ml_python_results.csv / ml_all_probs.csv 的目录
#' @param tab_dir Tables 输出目录
#' @param cfg 可选 config；读 ml_small_sample$bootstrap_B / model_order
#' @param split_col 训练/验证标记列名（在 d 中），如 "split"
#' @param event_col 结局列（在 d 中），如 "event"
#' @param feature_label 脚注用特征名向量
#' @param train_n train 样本量（脚注）；NULL 则从 d 推断
#' @param train_events train 事件数；NULL 则推断
ml_write_table45 <- function(out_dir,
                             tab_dir,
                             d = NULL,
                             cfg = list(),
                             split_col = "split",
                             event_col = "event",
                             feature_label = character(),
                             train_n = NULL,
                             train_events = NULL,
                             footnote_extra_t4 = character(),
                             footnote_extra_t5 = character()) {
  if (!exists("sci_xlsx_single_header_booktabs", mode = "function")) {
    stop("source utils.R and competing_supp_xlsx.R first", call. = FALSE)
  }
  if (!exists("ml_load_all_probs", mode = "function")) {
    stop("source ml_small_sample_metrics.R first", call. = FALSE)
  }

  B <- as.integer(ml_small_sample_cfg(cfg, "bootstrap_B", 1000L))
  ord <- ml_small_sample_model_order(cfg)
  thr_method <- ml_small_sample_cfg(cfg, "threshold_method", "youden")
  if (!identical(thr_method, "youden")) {
    warning("Only youden threshold is implemented; using youden.", call. = FALSE)
  }

  allp <- tryCatch(
    ml_load_all_probs(out_dir),
    error = function(e) {
      message("skip Table 4/5: ", conditionMessage(e))
      return(NULL)
    }
  )
  if (is.null(allp)) return(invisible(NULL))

  val_n <- val_events <- NA_integer_
  if (!is.null(d) && split_col %in% names(d)) {
    val_n <- sum(d[[split_col]] == "val", na.rm = TRUE)
    if (event_col %in% names(d)) {
      val_events <- sum(d[[split_col]] == "val" & d[[event_col]] == 1L, na.rm = TRUE)
    }
  }
  if (is.null(train_n) && !is.null(d) && split_col %in% names(d)) {
    train_n <- sum(d[[split_col]] == "train", na.rm = TRUE)
  }
  if (is.null(train_events) && !is.null(d) && all(c(split_col, event_col) %in% names(d))) {
    train_events <- sum(d[[split_col]] == "train" & d[[event_col]] == 1L, na.rm = TRUE)
  }

  t4 <- do.call(rbind, lapply(seq_along(ord), function(i) {
    nm <- ord[i]
    s <- allp[allp$model == nm & allp$split == "oof", , drop = FALSE]
    if (!nrow(s)) return(NULL)
    thr <- ml_youden_threshold(s$y, s$p)
    cbind(data.frame(Model = nm, stringsAsFactors = FALSE),
          ml_perf_row_bootstrap(s$y, s$p, thr, B = B, seed = 1000L + i))
  }))
  if (is.null(t4) || !nrow(t4)) {
    message("skip Table 4: no OOF rows")
    return(invisible(NULL))
  }

  fn_t4 <- c(
    if (!is.null(train_n) && !is.null(train_events)) {
      sprintf(
        "AUC from pooled cross-validation on the training set (n=%d, %d events; same predictions as Figure 4A).",
        train_n, train_events
      )
    } else {
      "AUC from pooled cross-validation on the training set (same predictions as Figure 4A)."
    },
    "Accuracy, sensitivity, specificity and F1 use the Youden cutoff from the same predictions (not 0.5).",
    sprintf("Values are point estimates with 95%% bootstrap CIs (%d resamples, percentile method).", B),
    if (length(feature_label)) paste0("Features: ", paste(feature_label, collapse = ", "), ".") else NULL,
    footnote_extra_t4
  )
  fn_t4 <- fn_t4[nzchar(fn_t4)]

  sci_xlsx_single_header_booktabs(
    file.path(tab_dir, "Table 4. ML performance internal validation.xlsx"),
    "Table 4. ML performance (internal validation)",
    t4,
    footnotes = fn_t4
  )
  if (exists(".competing_xlsx_fix_drawings", mode = "function")) {
    .competing_xlsx_fix_drawings(file.path(tab_dir, "Table 4. ML performance internal validation.xlsx"))
  }

  t5 <- do.call(rbind, lapply(seq_along(ord), function(i) {
    nm <- ord[i]
    so <- allp[allp$model == nm & allp$split == "oof", , drop = FALSE]
    sv <- allp[allp$model == nm & allp$split == "val", , drop = FALSE]
    if (!nrow(so) || !nrow(sv)) return(NULL)
    thr <- ml_youden_threshold(so$y, so$p)
    cbind(data.frame(Model = nm, stringsAsFactors = FALSE),
          ml_perf_row_bootstrap(sv$y, sv$p, thr, B = B, seed = 2000L + i))
  }))
  if (!is.null(t5) && nrow(t5)) {
    fn_t5 <- c(
      if (is.finite(val_n) && is.finite(val_events)) {
        sprintf(
          "Hold-out n=%d (%d events). Youden cutoff from training cross-validation; applied to validation.",
          val_n, val_events
        )
      } else {
        "Hold-out validation. Youden cutoff from training cross-validation; applied to validation."
      },
      sprintf(
        "Values are point estimates with 95%% bootstrap CIs (%d resamples). Rare events yield wide CIs.",
        B
      ),
      footnote_extra_t5
    )
    fn_t5 <- fn_t5[nzchar(fn_t5)]
    sci_xlsx_single_header_booktabs(
      file.path(tab_dir, "Table 5. ML performance validation.xlsx"),
      "Table 5. ML performance (validation hold-out)",
      t5,
      footnotes = fn_t5
    )
    if (exists(".competing_xlsx_fix_drawings", mode = "function")) {
      .competing_xlsx_fix_drawings(file.path(tab_dir, "Table 5. ML performance validation.xlsx"))
    }
  }
  message("Table 4/5 bootstrap CI (B=", B, ")")
  invisible(list(table4 = t4, table5 = t5))
}
