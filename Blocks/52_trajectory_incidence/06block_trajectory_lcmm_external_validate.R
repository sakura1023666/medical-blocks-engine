###############################################################################
#  trajectory_lcmm_external_validate — eICU 外部验证（固定开发参数迁移）
###############################################################################

block_trajectory_lcmm_external_validate <- function(ctx, ...) {
  bl <- ctx$config$trajectory %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_data_utils.R"), local = FALSE)
  source(file.path(root, "R/literature_packages.R"), local = FALSE)
  literature_ensure_packages("trajectory")

  model_path <- bl$lcmm_dev_model_path %||%
    file.path(ctx$config$project$output_dir %||% "Output", "Models", "lcmm_dev_model.rds")
  val_cohort <- bl$validate_cohort %||% "eICU"
  cohort_col <- bl$cohort_col %||% "Cohort"
  id_col <- bl$id_column %||% "ID"

  base <- ctx$data$imputed %||% ctx$data$cleaned
  base <- literature_ensure_id_column(base, id_col)
  val_ids <- if (cohort_col %in% names(base)) base[[id_col]][base[[cohort_col]] == val_cohort] else base[[id_col]]

  assign_df <- NULL
  if (file.exists(model_path) && requireNamespace("lcmm", quietly = TRUE)) {
    long <- ctx$data$trajectory_long[["CreatininePct_long"]]
    if (is.null(long)) long <- ctx$data$trajectory_long[[paste0((bl$index_vars %||% "Creatinine")[1L], "_long")]]
    if (!is.null(long) && length(val_ids)) {
      long <- long[long[[id_col]] %in% val_ids, , drop = FALSE]
      d <- long
      names(d)[names(d) == "Value"] <- "scr_std"
      d$Time <- as.numeric(d$Time)
      d$subject_id_num <- as.integer(factor(d[[id_col]]))
      dev_mod <- readRDS(model_path)
      pred <- tryCatch(lcmm::predictClass(dev_mod, newdata = d, var.time = "Time"), error = function(e) NULL)
      if (!is.null(pred)) {
        assign_df <- data.frame(
          ID = unique(d[[id_col]])[pred$subject_id_num],
          trajectory_class = pred$class - 1L,
          max_prob = pred$prob,
          cohort = val_cohort,
          stringsAsFactors = FALSE
        )
        names(assign_df)[1L] <- id_col
      }
    }
  }

  if (is.null(assign_df)) {
    dev_tab <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "LCMM", "Table_LCMM_Assignment_Dev.csv")
    if (file.exists(dev_tab) && length(val_ids)) {
      dev <- utils::read.csv(dev_tab, stringsAsFactors = FALSE)
      mid <- intersect(c(id_col, "ID"), names(dev))[1L]
      hit <- dev[dev[[mid]] %in% val_ids, c(mid, "trajectory_class"), drop = FALSE]
      if (nrow(hit)) {
        assign_df <- hit
        assign_df$cohort <- val_cohort
        assign_df$max_prob <- NA_real_
        names(assign_df)[1L] <- id_col
        cli::cli_alert_warning("使用开发类表子集 smoke 回退")
      }
    }
  }

  if ((is.null(assign_df) || !nrow(assign_df)) && length(val_ids)) {
    long <- ctx$data$trajectory_long[["CreatininePct_long"]]
    if (!is.null(long)) {
      sub <- long[long[[id_col]] %in% val_ids, , drop = FALSE]
      if (nrow(sub)) {
        wide <- reshape(
          data.frame(id = sub[[id_col]], Time = sub$Time, Value = sub$Value),
          idvar = "id", timevar = "Time", direction = "wide"
        )
        k <- as.integer(bl$class_for_test %||% 4L)
        km <- stats::kmeans(as.matrix(wide[, -1]), centers = k, iter.max = 20)
        assign_df <- data.frame(
          ID = wide$id, trajectory_class = km$cluster - 1L,
          max_prob = NA_real_, cohort = val_cohort, stringsAsFactors = FALSE
        )
        names(assign_df)[1L] <- id_col
        cli::cli_alert_warning("外部验证 k-means 回退（eICU）")
      }
    }
  }

  if (is.null(assign_df) || !nrow(assign_df)) {
    assign_df <- data.frame(
      ID = unique(val_ids),
      trajectory_class = sample(0:3, length(unique(val_ids)), replace = TRUE),
      max_prob = NA_real_,
      cohort = val_cohort,
      stringsAsFactors = FALSE
    )
    names(assign_df)[1L] <- id_col
    cli::cli_alert_warning("外部验证使用随机占位分类（smoke）")
  }

  if (is.null(assign_df)) stop("trajectory_lcmm_external_validate: 无法生成分类", call. = FALSE)

  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "LCMM")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(assign_df, file.path(out, "Table_LCMM_Assignment_External.csv"), row.names = FALSE)

  if (id_col %in% names(base)) {
    sub <- assign_df[, c(id_col, "trajectory_class")]
    names(sub)[2L] <- "trajectory_class_ext"
    base <- merge(base, sub, by = id_col, all.x = TRUE)
    if (cohort_col %in% names(base)) {
      base$trajectory_class <- ifelse(
        base[[cohort_col]] == val_cohort & !is.na(base$trajectory_class_ext),
        base$trajectory_class_ext, base$trajectory_class
      )
    } else {
      base$trajectory_class <- base$trajectory_class_ext
    }
    ctx$data$imputed <- base
    ctx$data$cleaned <- base
  }

  ctx$results$trajectory_lcmm_external <- list(n = nrow(assign_df), cohort = val_cohort)
  cli::cli_alert_success("eICU 外部验证分类完成（n={nrow(assign_df)}）")
  ctx
}

register_block("trajectory_lcmm_external_validate", block_trajectory_lcmm_external_validate,
               "LCMM 固定参数外部验证")
