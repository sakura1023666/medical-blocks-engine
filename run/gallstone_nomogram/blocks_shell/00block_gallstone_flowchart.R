###############################################################################
# gallstone_flowchart — Figure 1 纳排（文献 CONSORT：白底直角、右侧 Exclude、训练/验证分叉）
###############################################################################

block_gallstone_flowchart <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_gallstone_nomogram.R"), local = FALSE)
  d <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$raw
  n <- if (is.null(d)) 0L else as.integer(nrow(d))
  bl <- ctx$config$gallstone_nomogram %||% list()
  n_train <- as.integer(ctx$results$gallstone_train_split$n_train %||% NA_integer_)
  n_val <- as.integer(ctx$results$gallstone_train_split$n_val %||% NA_integer_)
  if (!is.finite(n_train) || !is.finite(n_val)) {
    ratio <- as.numeric(bl$train_ratio %||% 0.7)
    n_train <- as.integer(round(n * ratio))
    n_val <- as.integer(n - n_train)
  }

  steps_csv <- data.frame(
    step = c("N0", "N_analysis", "N_train", "N_val"),
    label = c(
      "Total eligible gallstone lithotripsy records",
      "Final participants included (complete case)",
      "Training set",
      "Validation set"
    ),
    n_remain = c(n, n, n_train, n_val),
    n_exclude = c(NA_integer_, 0L, NA_integer_, NA_integer_),
    exclude_label = c(NA_character_, "Missing modeling covariates (n = 0)",
                      NA_character_, NA_character_),
    stringsAsFactors = FALSE
  )

  dirs <- gallstone_nomogram_out_dirs(ctx, "ALL")
  gallstone_nomogram_ensure_dirs(list(dirs$shared_tables, dirs$shared_figures))
  fig_name <- "Figure 1. Inclusion exclusion flowchart.pdf"

  for (tab_dir in unique(c(dirs$shared_tables, file.path(dirs$project, "Tables")))) {
    dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(steps_csv, file.path(tab_dir, "Flowchart_attrition.csv"), row.names = FALSE)
  }

  for (fig_dir in unique(c(dirs$shared_figures, file.path(dirs$project, "Figures")))) {
    dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
    tryCatch(
      gallstone_draw_fig1_lit(
        file.path(fig_dir, fig_name),
        n_total = n, n_final = n, n_exclude = 0L,
        exclude_label = "missing modeling covariates",
        n_train = n_train, n_val = n_val
      ),
      error = function(e) cli::cli_alert_warning("Fig1 draw: {conditionMessage(e)}")
    )
  }

  ctx$results$gallstone_flowchart <- list(
    steps = steps_csv, n = n, n_train = n_train, n_val = n_val
  )
  cli::cli_alert_success("Figure 1 lit CONSORT: n={n}; train={n_train}; val={n_val}")
  ctx
}

register_block("gallstone_flowchart", block_gallstone_flowchart, "胆结石Fig1纳排图")
