###############################################################################
#  cftraj_circs_compute — CHARLS CircS 七组分计分 + 二分类 CircS>=4
#  文献: Ma 2026 Alzheimers Dement — CircS × 认知轨迹 × causal forest CATE
###############################################################################

block_cftraj_circs_compute <- function(ctx, ...) {
  bl <- ctx$config$cftraj %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_data_utils.R"), local = FALSE)
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("cftraj_circs_compute: 无数据", call. = FALSE)

  id_col <- bl$id_column %||% ctx$config$data$id_column %||% "ID"
  data <- literature_ensure_id_column(data, id_col)

  comp_map <- bl$circs_components %||% list(
    BMI = list(col = "BMI", rule = "ge", cut = 24),
    BP = list(col = "SBP", rule = "ge", cut = 140),
    Glucose = list(col = "Glucose", rule = "ge", cut = 5.6),
    Lipids = list(col = "TC", rule = "ge", cut = 5.2),
    Sleep = list(col = "Sleep_hours", rule = "le", cut = 6),
    Depression = list(col = "CESD10", rule = "ge", cut = 10),
    Waist = list(col = "Waist", rule = "ge", cut = 90)
  )

  .risk_flag <- function(x, rule, cut) {
    v <- suppressWarnings(as.numeric(x))
    if (rule == "le") as.integer(!is.na(v) & v <= cut)
    else as.integer(!is.na(v) & v >= cut)
  }

  risk_cols <- character(0)
  comp_rows <- list()
  for (nm in names(comp_map)) {
    spec <- comp_map[[nm]]
    col <- spec$col %||% nm
    if (!col %in% names(data)) {
      cli::cli_alert_warning("CircS 组分缺失: {col} ({nm})")
      next
    }
    rc <- paste0("CircS_risk_", nm)
    data[[rc]] <- .risk_flag(data[[col]], spec$rule %||% "ge", spec$cut %||% 1)
    risk_cols <- c(risk_cols, rc)
    comp_rows[[length(comp_rows) + 1L]] <- data.frame(
      component = nm, column = col, n_risk = sum(data[[rc]] == 1L, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }
  if (!length(risk_cols)) stop("cftraj_circs_compute: 无可用 CircS 组分列", call. = FALSE)

  score_col <- bl$circs_score_col %||% "CircS"
  data[[score_col]] <- rowSums(data[, risk_cols, drop = FALSE], na.rm = FALSE)
  thr <- as.integer(bl$circs_threshold %||% 4L)
  bin_col <- bl$circs_binary_col %||% "CircS_high"
  data[[bin_col]] <- as.integer(data[[score_col]] >= thr)

  ctx$data$imputed <- data
  ctx$data$cleaned <- data

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "CfTraj")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  comp_tab <- do.call(rbind, comp_rows)
  comp_tab$threshold_used <- thr
  utils::write.csv(comp_tab, file.path(out_dir, "Table_CircS_Component_Summary.csv"), row.names = FALSE)
  summ <- data.frame(
    variable = c(score_col, bin_col),
    mean = c(mean(data[[score_col]], na.rm = TRUE), mean(data[[bin_col]], na.rm = TRUE)),
    n = c(sum(!is.na(data[[score_col]])), sum(!is.na(data[[bin_col]]))),
    stringsAsFactors = FALSE
  )
  utils::write.csv(summ, file.path(out_dir, "Table_CircS_Descriptive.csv"), row.names = FALSE)

  ctx$results$cftraj_circs_compute <- list(
    score_col = score_col, binary_col = bin_col, threshold = thr,
    n_components = length(risk_cols), output_dir = out_dir
  )
  cli::cli_alert_success("CircS 计分完成 (threshold>={thr}, components={length(risk_cols)})")
  ctx
}

register_block("cftraj_circs_compute", block_cftraj_circs_compute, "CircS 七组分计分 CircS>=4")
