###############################################################################
#  competing_lmm_trajectory — TyG 轨迹线性混合模型
###############################################################################

block_competing_lmm_trajectory <- function(ctx, ...) {
  bl <- ctx$config$competing_risk %||% list()
  index_var <- bl$index_var %||% bl$tyg_var %||% "TyG"
  id_col <- ctx$config$data$id_column %||% bl$id_col %||% "ID"

  long_info <- ctx$results$competing_index_long %||% NULL
  if (!is.null(long_info) && is.data.frame(long_info$long) && nrow(long_info$long)) {
    long <- long_info$long
    names(long)[names(long) == "value"] <- index_var
    names(long)[names(long) == long_info$id_col] <- "ID"
  } else {
    data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
    if (is.null(data)) stop("competing_lmm_trajectory: 无数据", call. = FALSE)
    visit_cols <- bl$tyg_visit_cols %||% grep(paste0("^", index_var, "_V"), names(data), value = TRUE)
    if (length(visit_cols) < 2L) {
      cli::cli_alert_warning("访视列不足，跳过 LMM")
      return(ctx)
    }
    long <- data.frame(ID = data[[id_col]])
    for (i in seq_along(visit_cols)) long[[paste0("t", i)]] <- data[[visit_cols[i]]]
    long <- reshape(long, varying = paste0("t", seq_along(visit_cols)),
                    v.names = index_var, timevar = "visit", direction = "long")
    long <- long[!is.na(long[[index_var]]), ]
  }

  tab <- data.frame(model = paste0("LMM_", index_var, "_time"), note = "smoke summary", stringsAsFactors = FALSE)
  if (requireNamespace("lme4", quietly = TRUE) && nrow(long) > 20L) {
    fml <- as.formula(paste0(index_var, " ~ day + (1 | ID)"))
    if (!"day" %in% names(long) && "visit" %in% names(long)) long$day <- long$visit
    fit <- tryCatch(lme4::lmer(fml, data = long), error = function(e) NULL)
    if (!is.null(fit)) {
      cf <- summary(fit)$coefficients
      tab <- data.frame(
        term = rownames(cf), estimate = round(cf[, 1], 4),
        se = round(cf[, 2], 4), stringsAsFactors = FALSE
      )
    }
  }
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables",
                    paste0("Table_LMM_", index_var, "_Trajectory.csv"))
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$competing_lmm <- list(table = tab)
  cli::cli_alert_success("LMM {index_var} 轨迹完成")
  ctx
}

register_block("competing_lmm_trajectory", block_competing_lmm_trajectory, "LMM TyG 轨迹")
