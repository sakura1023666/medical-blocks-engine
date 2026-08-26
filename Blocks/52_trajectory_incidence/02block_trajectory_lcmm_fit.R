###############################################################################
#  trajectory_lcmm_fit — LCMM BIC 2–10 选模 + MPCMP（MIMIC 开发队列）
#  文献: Takkavatakarn 2024 Critical Care
###############################################################################

block_trajectory_lcmm_fit <- function(ctx, ...) {
  bl <- ctx$config$trajectory %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_packages.R"), local = FALSE)
  source(file.path(root, "R/literature_data_utils.R"), local = FALSE)
  literature_ensure_packages("trajectory")

  use_pct <- isTRUE(bl$use_creatinine_pct %||% TRUE)
  idx <- if (use_pct) "CreatininePct" else (bl$index_vars %||% c("Creatinine"))[1L]
  key_long <- paste0(idx, "_long")
  long <- ctx$data$trajectory_long[[key_long]]
  if (is.null(long) && use_pct) {
    bl2 <- bl
    bl2$index_vars <- "CreatininePct"
    bl2$time_col_prefix <- "CrePct_"
    ctx$config$trajectory <- bl2
    source(file.path(root, "Blocks/52_trajectory_incidence/01block_trajectory_wide_to_long.R"), local = TRUE)
    ctx <- block_trajectory_wide_to_long(ctx)
    long <- ctx$data$trajectory_long[[key_long]]
  }
  if (is.null(long)) stop("trajectory_lcmm_fit: 请先运行 trajectory_wide_to_long / creatinine_pct", call. = FALSE)

  id_col <- bl$id_column %||% ctx$config$data$id_column %||% "ID"
  if (!id_col %in% names(long)) long <- literature_ensure_id_column(long, id_col)

  dev_cohort <- bl$dev_cohort %||% "MIMIC"
  cohort_col <- bl$cohort_col %||% "Cohort"
  if (cohort_col %in% names(long)) {
    long <- long[long[[cohort_col]] == dev_cohort, , drop = FALSE]
  } else if (cohort_col %in% names(ctx$data$imputed %||% list())) {
    ids <- (ctx$data$imputed %||% ctx$data$cleaned)[[id_col]]
    ids <- ids[ (ctx$data$imputed %||% ctx$data$cleaned)[[cohort_col]] == dev_cohort ]
    long <- long[long[[id_col]] %in% ids, , drop = FALSE]
  }
  if (nrow(long) < 40L) cli::cli_alert_warning("开发队列样本较少: n={nrow(long)}")

  ng_min <- as.integer(bl$lcmm_ng_min %||% 2L)
  ng_max <- as.integer(bl$lcmm_ng_max %||% 10L)
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "LCMM")
  model_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Models")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)

  d <- long
  names(d)[names(d) == "Value"] <- "scr_std"
  d$subject_id_num <- as.integer(factor(d[[id_col]]))
  d <- d[order(d$subject_id_num, d$Time), ]

  bic_rows <- list()
  best_ng <- as.integer(bl$class_for_test %||% 4L)
  best_bic <- Inf
  best_model <- NULL

  if (requireNamespace("lcmm", quietly = TRUE)) {
    m1 <- tryCatch(
      lcmm::hlme(
        fixed = scr_std ~ splines::ns(Time, df = 2),
        random = ~ splines::ns(Time, df = 2),
        subject = "subject_id_num", ng = 1, data = d, verbose = FALSE
      ),
      error = function(e) NULL
    )
    if (!is.null(m1)) {
      for (ng in seq.int(ng_min, ng_max)) {
        fit <- tryCatch({
          if (ng == 1L) m1 else {
            lcmm::gridsearch(
              rep = as.integer(bl$gridsearch_rep %||% 5L),
              maxiter = as.integer(bl$gridsearch_maxiter %||% 5L),
              minit = m1,
              lcmm::hlme(
                fixed = scr_std ~ splines::ns(Time, df = 2),
                mixture = ~ splines::ns(Time, df = 2),
                random = ~ splines::ns(Time, df = 2),
                subject = "subject_id_num", ng = ng, data = d, verbose = FALSE
              )
            )
          }
        }, error = function(e) NULL)
        if (is.null(fit)) next
        mod <- if (!is.null(fit$best)) fit$best else fit
        bic_val <- tryCatch(stats::BIC(mod), error = function(e) NA_real_)
        bic_rows[[length(bic_rows) + 1L]] <- data.frame(ng = ng, BIC = bic_val, stringsAsFactors = FALSE)
        if (!is.na(bic_val) && bic_val < best_bic) {
          best_bic <- bic_val
          best_ng <- ng
          best_model <- mod
        }
      }
    }
  }

  bic_tab <- if (length(bic_rows)) do.call(rbind, bic_rows) else data.frame(ng = best_ng, BIC = NA)
  utils::write.csv(bic_tab, file.path(out, "Table_LCMM_BIC_Selection.csv"), row.names = FALSE)

  if (is.null(best_model) && requireNamespace("lcmm", quietly = TRUE)) {
    cli::cli_alert_warning("BIC 选模失败，回退固定 ng={best_ng}")
    best_model <- tryCatch(
      lcmm::hlme(
        fixed = scr_std ~ splines::ns(Time, df = 2),
        mixture = ~ splines::ns(Time, df = 2),
        random = ~ splines::ns(Time, df = 2),
        subject = "subject_id_num", ng = best_ng, data = d, verbose = FALSE
      ),
      error = function(e) NULL
    )
  }

  mpcmp_rows <- list()
  assign_df <- NULL

  if (is.null(best_model) || is.null(best_model$pprob)) {
    cli::cli_alert_warning("LCMM 未收敛，使用 k-means 回退分类")
    wide <- reshape(d[, c("subject_id_num", "Time", "scr_std")], idvar = "subject_id_num",
                    timevar = "Time", direction = "wide")
    mat <- as.matrix(wide[, -1])
    km <- stats::kmeans(mat, centers = best_ng, iter.max = 20)
    assign_df <- data.frame(
      ID = unique(d[[id_col]])[sort(unique(d$subject_id_num))],
      trajectory_class = km$cluster - 1L,
      max_prob = NA_real_,
      stringsAsFactors = FALSE
    )
    names(assign_df)[1L] <- id_col
    utils::write.csv(assign_df, file.path(out, "Table_LCMM_Assignment_Dev.csv"), row.names = FALSE)
    mpcmp_tab <- data.frame(
      class = 0:(best_ng - 1L), MPCMP = NA_real_,
      n = as.integer(table(km$cluster)), stringsAsFactors = FALSE
    )
    utils::write.csv(mpcmp_tab, file.path(out, "Table_LCMM_MPCMP.csv"), row.names = FALSE)
  }

  if (!is.null(best_model) && !is.null(best_model$pprob)) {
  pp <- as.data.frame(best_model$pprob)
  prob_cols <- grep("^prob", names(pp), value = TRUE)
  cls <- pp$class
  for (k in sort(unique(cls))) {
    idx_k <- which(cls == k)
    mpcmp_rows[[length(mpcmp_rows) + 1L]] <- data.frame(
      class = k - 1L,
      MPCMP = mean(apply(pp[idx_k, prob_cols, drop = FALSE], 1, max), na.rm = TRUE),
      n = length(idx_k),
      stringsAsFactors = FALSE
    )
  }
  assign_df <- data.frame(
    ID = unique(d[[id_col]])[pp$subject_id_num],
    trajectory_class = pp$class - 1L,
    max_prob = apply(pp[, prob_cols, drop = FALSE], 1, max),
    stringsAsFactors = FALSE
  )
  names(assign_df)[1L] <- id_col
  utils::write.csv(assign_df, file.path(out, "Table_LCMM_Assignment_Dev.csv"), row.names = FALSE)
  saveRDS(best_model, file.path(model_dir, "lcmm_dev_model.rds"))
  mpcmp_tab <- do.call(rbind, mpcmp_rows)
  utils::write.csv(mpcmp_tab, file.path(out, "Table_LCMM_MPCMP.csv"), row.names = FALSE)
  }

  if (!is.null(assign_df)) {
    base <- ctx$data$imputed %||% ctx$data$cleaned
    merge_id <- intersect(c(id_col, "ID"), names(assign_df))[1L]
    if (!is.na(merge_id) && merge_id %in% names(base)) {
      sub <- assign_df[, c(merge_id, "trajectory_class")]
      names(sub)[2L] <- "trajectory_class_dev"
      base <- merge(base, sub, by = merge_id, all.x = TRUE)
      base$trajectory_class <- ifelse(is.na(base$trajectory_class_dev), base$trajectory_class, base$trajectory_class_dev)
      ctx$data$imputed <- base
      ctx$data$cleaned <- base
    }
  }

  ctx$results$trajectory_lcmm <- list(
    output_dir = out, best_ng = best_ng, best_bic = best_bic,
    dev_cohort = dev_cohort, model_path = file.path(model_dir, "lcmm_dev_model.rds")
  )
  cli::cli_alert_success("LCMM BIC 选模完成（ng={best_ng}, dev={dev_cohort}）")
  ctx
}

register_block("trajectory_lcmm_fit", block_trajectory_lcmm_fit, "LCMM BIC 2-10 开发拟合")
