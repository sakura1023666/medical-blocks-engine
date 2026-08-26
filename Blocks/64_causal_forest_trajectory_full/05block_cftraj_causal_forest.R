###############################################################################
#  cftraj_causal_forest — grf causal forest CATE（轨迹类 low vs 其他，分 global/episodic）
#  文献: Ma 2026 Alzheimers Dement
###############################################################################

block_cftraj_causal_forest <- function(ctx, ...) {
  bl <- ctx$config$cftraj %||% list()
  root <- ctx$config$project$root %||% getwd()
  if (!exists("run_literature_python", mode = "function"))
    source(file.path(root, "R/python_literature.R"), local = FALSE)

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("cftraj_causal_forest: 无数据", call. = FALSE)

  treat_col <- bl$treatment_col %||% bl$circs_binary_col %||% "CircS_high"
  if (!treat_col %in% names(data)) stop("cftraj_causal_forest: 缺少治疗/暴露列", call. = FALSE)

  covars <- intersect(bl$cate_covariates %||% bl$covariates %||% c("Age", "Sex", "Education", "BMI", "Anemia"), names(data))
  domains <- bl$cate_domains %||% c("global", "episodic")
  all_summ <- list()

  for (dom in domains) {
    y_label <- if (dom == "episodic") "trajectory_class_label_episodic" else "trajectory_class_label_global"
    if (!y_label %in% names(data) && "trajectory_class_label" %in% names(data))
      y_label <- "trajectory_class_label"
    if (!y_label %in% names(data)) next

    out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "CfTraj", "CATE", dom)
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

    d <- data[!is.na(data[[treat_col]]) & !is.na(data[[y_label]]), , drop = FALSE]
    outcome_col <- paste0("y_low_", dom)
    d[[outcome_col]] <- as.integer(d[[y_label]] == (bl$trajectory_low_label %||% "low"))
    if (nrow(d) < 50L) cli::cli_alert_warning("CATE [{dom}] 样本较少: n={nrow(d)}")

    cate_df <- NULL
    ate <- NA_real_

    if (requireNamespace("grf", quietly = TRUE) && length(covars) >= 1L) {
      X <- as.matrix(d[, covars, drop = FALSE])
      for (j in seq_len(ncol(X))) {
        if (is.character(X[, j]) || is.factor(d[[covars[j]]])) X[, j] <- as.numeric(factor(d[[covars[j]]]))
      }
      W <- as.numeric(d[[treat_col]])
      Y <- as.numeric(d[[outcome_col]])
      cf <- tryCatch(
        grf::causal_forest(X, Y, W, num.trees = as.integer(bl$cate_num_trees %||% 2000L)),
        error = function(e) NULL
      )
      if (!is.null(cf)) {
        cate <- grf::predict(cf)$predictions
        ate <- mean(cate, na.rm = TRUE)
        id_col <- bl$id_column %||% ctx$config$data$id_column %||% "ID"
        cate_df <- data.frame(CATE = as.numeric(cate), treatment = W, outcome = Y, stringsAsFactors = FALSE)
        if (id_col %in% names(d)) cate_df[[id_col]] <- d[[id_col]]
        utils::write.csv(cate_df, file.path(out_dir, "Table_CfTraj_CATE_Subject.csv"), row.names = FALSE)
        var_imp <- tryCatch(grf::variable_importance(cf), error = function(e) NULL)
        if (!is.null(var_imp)) {
          imp_df <- data.frame(feature = covars, importance = as.numeric(var_imp), stringsAsFactors = FALSE)
          utils::write.csv(imp_df, file.path(out_dir, "Table_CfTraj_CATE_VariableImportance.csv"), row.names = FALSE)
        }
      }
    }

    if (is.null(cate_df)) {
      cli::cli_alert_warning("grf 不可用 [{dom}]，回退 Python causal_forest_cate")
      csv_in <- file.path(out_dir, "_cftraj_cate_input.csv")
      id_col <- bl$id_column %||% ctx$config$data$id_column %||% "ID"
      export_cols <- unique(c(id_col, treat_col, outcome_col, covars))
      utils::write.csv(d[, export_cols, drop = FALSE], csv_in, row.names = FALSE)
      run_literature_python(root, "causal_forest_cate", c(
        "--out-dir", out_dir, "--data-path", csv_in,
        "--outcome-col", outcome_col, "--treatment-col", treat_col, "--id-col", id_col
      ))
      ap <- file.path(out_dir, "Table_CfTraj_CATE_Subject.csv")
      if (file.exists(ap)) cate_df <- utils::read.csv(ap, stringsAsFactors = FALSE)
      mp <- file.path(out_dir, "Table_CfTraj_CATE_Summary.csv")
      if (file.exists(mp)) {
        sm <- utils::read.csv(mp, stringsAsFactors = FALSE)
        if ("ATE" %in% names(sm)) ate <- sm$ATE[1L]
      }
    }

    if (!is.null(cate_df) && "CATE" %in% names(cate_df)) {
      summ <- data.frame(
        cognitive_domain = dom,
        ATE = if (is.na(ate)) mean(cate_df$CATE, na.rm = TRUE) else ate,
        median_CATE = stats::median(cate_df$CATE, na.rm = TRUE),
        sd_CATE = stats::sd(cate_df$CATE, na.rm = TRUE),
        n = nrow(cate_df),
        stringsAsFactors = FALSE
      )
      all_summ[[dom]] <- summ
      utils::write.csv(summ, file.path(out_dir, "Table_CfTraj_CATE_Summary.csv"), row.names = FALSE)
    }
  }

  tab_all <- if (length(all_summ)) do.call(rbind, all_summ) else data.frame(note = "no CATE")
  out_root <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "CfTraj", "CATE")
  dir.create(out_root, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab_all, file.path(out_root, "Table_CfTraj_CATE_Summary_AllDomains.csv"), row.names = FALSE)

  ctx$results$cftraj_causal_forest <- list(table = tab_all, output_dir = out_root)
  cli::cli_alert_success("Causal forest CATE 完成 ({length(all_summ)} 域)")
  ctx
}

register_block("cftraj_causal_forest", block_cftraj_causal_forest, "CircS CATE causal forest")
