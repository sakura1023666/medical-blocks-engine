###############################################################################
#  cftraj_lcmm_fit — LCMM/lcmm 拟合或 Python lcmm_trajectory 回退；轨迹 high/moderate/low
#  文献: Ma 2026 Alzheimers Dement
###############################################################################

block_cftraj_lcmm_fit <- function(ctx, ...) {
  bl <- ctx$config$cftraj %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_packages.R"), local = FALSE)
  source(file.path(root, "R/literature_data_utils.R"), local = FALSE)
  if (!exists("run_literature_python", mode = "function"))
    source(file.path(root, "R/python_literature.R"), local = FALSE)

  long <- (ctx$data$cftraj_long %||% list())$global
  if (is.null(long)) {
    source(file.path(root, "Blocks/64_causal_forest_trajectory_full/02block_cftraj_wide_to_long.R"), local = TRUE)
    ctx <- block_cftraj_wide_to_long(ctx)
    long <- (ctx$data$cftraj_long %||% list())$global
  }
  if (is.null(long)) stop("cftraj_lcmm_fit: 请先运行 cftraj_wide_to_long", call. = FALSE)

  id_col <- bl$id_column %||% ctx$config$data$id_column %||% "ID"
  if (!id_col %in% names(long)) long <- literature_ensure_id_column(long, id_col)

  n_classes <- as.integer(bl$n_classes %||% 3L)
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "CfTraj", "LCMM")
  model_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Models")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)

  d <- long
  names(d)[names(d) == "Value"] <- "cog_score"
  d$subject_id_num <- as.integer(factor(d[[id_col]]))
  d <- d[order(d$subject_id_num, d$Time), ]

  assign_df <- NULL
  best_model <- NULL
  best_ng <- n_classes

  if (requireNamespace("lcmm", quietly = TRUE)) {
    m1 <- tryCatch(
      lcmm::hlme(
        fixed = cog_score ~ splines::ns(Time, df = 2),
        random = ~ splines::ns(Time, df = 2),
        subject = "subject_id_num", ng = 1, data = d, verbose = FALSE
      ),
      error = function(e) NULL
    )
    if (!is.null(m1)) {
      best_model <- tryCatch(
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
      )
      if (!is.null(best_model)) {
        mod <- if (!is.null(best_model$best)) best_model$best else best_model
        best_model <- mod
      }
    }
    if (!is.null(best_model) && !is.null(best_model$pprob)) {
      pp <- as.data.frame(best_model$pprob)
      prob_cols <- grep("^prob", names(pp), value = TRUE)
      assign_df <- data.frame(
        ID = unique(d[[id_col]])[pp$subject_id_num],
        trajectory_class = pp$class - 1L,
        max_prob = apply(pp[, prob_cols, drop = FALSE], 1, max),
        stringsAsFactors = FALSE
      )
      names(assign_df)[1L] <- id_col
      saveRDS(best_model, file.path(model_dir, "cftraj_lcmm_model.rds"))
    }
  }

  if (is.null(assign_df)) {
    cli::cli_alert_warning("LCMM 未收敛，回退 Python lcmm_trajectory")
    long_csv <- file.path(out, "..", "_cftraj_global_long.csv")
    if (!file.exists(long_csv)) {
      tmp <- d
      names(tmp)[names(tmp) == "cog_score"] <- "Value"
      long_csv <- file.path(out, "_cftraj_lcmm_input.csv")
      utils::write.csv(tmp[, c(id_col, "Time", "Value")], long_csv, row.names = FALSE)
    }
    run_literature_python(root, "lcmm_trajectory", c(
      "--out-dir", out, "--long-path", long_csv,
      "--n-clusters", as.character(n_classes), "--id-col", id_col
    ))
    ap <- file.path(out, "Table_LCMM_Assignment.csv")
    if (file.exists(ap)) assign_df <- utils::read.csv(ap, stringsAsFactors = FALSE)
  }

  if (is.null(assign_df) || !nrow(assign_df)) stop("cftraj_lcmm_fit: 轨迹分类失败", call. = FALSE)

  .label_trajectory <- function(df, dlong) {
    cls <- sort(unique(df$trajectory_class))
    end_means <- vapply(cls, function(k) {
      ids <- df[[id_col]][df$trajectory_class == k]
      mean(dlong$cog_score[dlong[[id_col]] %in% ids & dlong$Time == max(dlong$Time, na.rm = TRUE)], na.rm = TRUE)
    }, numeric(1))
    ord <- order(end_means, decreasing = TRUE)
    lab_map <- stats::setNames(
      (bl$trajectory_class_labels %||% c("high", "moderate", "low"))[seq_along(cls)],
      cls[ord]
    )
    if (length(lab_map) < length(cls)) {
      extra <- paste0("class_", setdiff(cls, names(lab_map)))
      lab_map <- c(lab_map, stats::setNames(extra, setdiff(cls, names(lab_map))))
    }
    df$trajectory_class_label <- unname(lab_map[as.character(df$trajectory_class)])
    df
  }
  assign_df <- .label_trajectory(assign_df, d)
  assign_df$cognitive_domain <- "global"
  utils::write.csv(assign_df, file.path(out, "Table_CfTraj_LCMM_Assignment_global.csv"), row.names = FALSE)
  utils::write.csv(assign_df, file.path(out, "Table_CfTraj_LCMM_Assignment.csv"), row.names = FALSE)

  base <- ctx$data$imputed %||% ctx$data$cleaned
  merge_id <- intersect(c(id_col, "ID"), names(assign_df))[1L]
  if (!is.na(merge_id) && merge_id %in% names(base)) {
    sub <- assign_df[, c(merge_id, "trajectory_class", "trajectory_class_label"), drop = FALSE]
    names(sub)[2:3] <- c("trajectory_class_global", "trajectory_class_label_global")
    base <- merge(base, sub, by = merge_id, all.x = TRUE)
    base$trajectory_class <- base$trajectory_class_global
    base$trajectory_class_label <- base$trajectory_class_label_global
    ctx$data$imputed <- base
    ctx$data$cleaned <- base
  }

  ctx$results$cftraj_lcmm_fit <- list(
    output_dir = out, n_classes = n_classes,
    model_path = file.path(model_dir, "cftraj_lcmm_model.rds")
  )
  cli::cli_alert_success("LCMM 轨迹分类完成 (k={n_classes})")
  ctx
}

register_block("cftraj_lcmm_fit", block_cftraj_lcmm_fit, "LCMM 认知轨迹 high/moderate/low")
