###############################################################################
#  cftraj_lcmm_episodic — 情景记忆 LCMM（与全局认知分开建模，Ma 2026）
###############################################################################

.cftraj_lcmm_one_domain <- function(ctx, long, domain_label, id_col, bl, out_subdir) {
  root <- ctx$config$project$root %||% getwd()
  if (!exists("run_literature_python", mode = "function"))
    source(file.path(root, "R/python_literature.R"), local = FALSE)

  n_classes <- as.integer(bl$n_classes %||% 3L)
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "CfTraj", "LCMM", out_subdir)
  model_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Models", out_subdir)
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)

  d <- long
  names(d)[names(d) == "Value"] <- "cog_score"
  d$subject_id_num <- as.integer(factor(d[[id_col]]))
  d <- d[order(d$subject_id_num, d$Time), ]

  assign_df <- NULL
  if (requireNamespace("lcmm", quietly = TRUE)) {
    m1 <- tryCatch(
      lcmm::hlme(
        fixed = cog_score ~ splines::ns(Time, df = 2),
        random = ~ splines::ns(Time, df = 2),
        subject = "subject_id_num", ng = 1, data = d, verbose = FALSE
      ),
      error = function(e) NULL
    )
    best_model <- if (!is.null(m1)) tryCatch(
      lcmm::gridsearch(
        rep = as.integer(bl$gridsearch_rep %||% 5L),
        maxiter = as.integer(bl$gridsearch_maxiter %||% 5L),
        minit = m1,
        lcmm::hlme(
          fixed = cog_score ~ splines::ns(Time, df = 2),
          mixture = ~ splines::ns(Time, df = 2),
          random = ~ splines::ns(Time, df = 2),
          subject = "subject_id_num", ng = n_classes, data = d, verbose = FALSE
        )
      ),
      error = function(e) NULL
    ) else NULL
    if (!is.null(best_model)) {
      mod <- if (!is.null(best_model$best)) best_model$best else best_model
      if (!is.null(mod$pprob)) {
        pp <- as.data.frame(mod$pprob)
        prob_cols <- grep("^prob", names(pp), value = TRUE)
        assign_df <- data.frame(
          ID = unique(d[[id_col]])[pp$subject_id_num],
          trajectory_class = pp$class - 1L,
          max_prob = apply(pp[, prob_cols, drop = FALSE], 1, max),
          stringsAsFactors = FALSE
        )
        names(assign_df)[1L] <- id_col
        saveRDS(mod, file.path(model_dir, paste0("lcmm_", out_subdir, ".rds")))
      }
    }
  }

  if (is.null(assign_df)) {
    long_csv <- file.path(out, paste0("_lcmm_input_", out_subdir, ".csv"))
    tmp <- d; names(tmp)[names(tmp) == "cog_score"] <- "Value"
    utils::write.csv(tmp[, c(id_col, "Time", "Value")], long_csv, row.names = FALSE)
    run_literature_python(root, "lcmm_trajectory", c(
      "--out-dir", out, "--long-path", long_csv,
      "--n-clusters", as.character(n_classes), "--id-col", id_col
    ))
    ap <- file.path(out, "Table_LCMM_Assignment.csv")
    if (file.exists(ap)) assign_df <- utils::read.csv(ap, stringsAsFactors = FALSE)
  }
  if (is.null(assign_df) || !nrow(assign_df)) stop("cftraj_lcmm: ", domain_label, " 轨迹分类失败", call. = FALSE)

  cls <- sort(unique(assign_df$trajectory_class))
  end_means <- vapply(cls, function(k) {
    ids <- assign_df[[id_col]][assign_df$trajectory_class == k]
    mean(d$cog_score[d[[id_col]] %in% ids & d$Time == max(d$Time, na.rm = TRUE)], na.rm = TRUE)
  }, numeric(1))
  ord <- order(end_means, decreasing = TRUE)
  labels <- (bl$trajectory_class_labels %||% c("high", "moderate", "low"))[seq_along(cls)]
  lab_map <- stats::setNames(labels, cls[ord])
  assign_df$trajectory_class_label <- unname(lab_map[as.character(assign_df$trajectory_class)])
  assign_df$cognitive_domain <- domain_label
  utils::write.csv(assign_df, file.path(out, paste0("Table_CfTraj_LCMM_Assignment_", out_subdir, ".csv")), row.names = FALSE)
  assign_df
}

block_cftraj_lcmm_episodic <- function(ctx, ...) {
  bl <- ctx$config$cftraj %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_data_utils.R"), local = FALSE)

  long <- (ctx$data$cftraj_long %||% list())$episodic
  if (is.null(long)) {
    source(file.path(root, "Blocks/64_causal_forest_trajectory_full/02block_cftraj_wide_to_long.R"), local = TRUE)
    ctx <- block_cftraj_wide_to_long(ctx)
    long <- (ctx$data$cftraj_long %||% list())$episodic
  }
  if (is.null(long)) stop("cftraj_lcmm_episodic: 无情景记忆 long 数据", call. = FALSE)

  id_col <- bl$id_column %||% ctx$config$data$id_column %||% "ID"
  if (!id_col %in% names(long)) long <- literature_ensure_id_column(long, id_col)

  assign_df <- .cftraj_lcmm_one_domain(ctx, long, "episodic_memory", id_col, bl, "episodic")

  base <- ctx$data$imputed %||% ctx$data$cleaned
  if (id_col %in% names(base)) {
    sub <- assign_df[, c(id_col, "trajectory_class", "trajectory_class_label"), drop = FALSE]
    names(sub)[2:3] <- c("trajectory_class_episodic", "trajectory_class_label_episodic")
    base <- merge(base, sub, by = id_col, all.x = TRUE)
    ctx$data$imputed <- base
    ctx$data$cleaned <- base
  }
  ctx$results$cftraj_lcmm_episodic <- list(n = nrow(assign_df), output = "episodic")
  cli::cli_alert_success("情景记忆 LCMM 完成 (k={bl$n_classes %||% 3})")
  ctx
}

register_block("cftraj_lcmm_episodic", block_cftraj_lcmm_episodic, "情景记忆 LCMM 三轨迹")
