###############################################################################
#  R/cross_lagged_table1_harmonize.R
#  交叉滞后套路：强制三库 Table 1 同一 include 顺序与显示名。
#  由 run/cross_lagged/* 与 run/incidence/run_incidence_single.R 在 source(config) 后调用。
#  开关：config$cross_lagged$table1_harmonize = TRUE（模板默认开启）
###############################################################################

cross_lagged_apply_table1_harmonized <- function(config, root = getwd()) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
  cl <- config$cross_lagged %||% list()
  bl <- config$baseline_binary %||% list()
  pipe_name <- ""
  if (exists("pipeline", inherits = TRUE)) {
    pipe_name <- as.character((get("pipeline", inherits = TRUE)$name %||% ""))
  }
  if (isFALSE(cl$table1_harmonize)) return(config)
  # 兼容：显式开关，或 pipeline 名含 cross_lagged（交叉滞后一期 config）
  on <- isTRUE(cl$table1_harmonize %||% FALSE) ||
    isTRUE(bl$use_cross_lagged_table1_harmonized %||% FALSE) ||
    grepl("cross_lagged", pipe_name, ignore.case = TRUE) ||
    grepl("cross.?lag", as.character(config$project$name %||% ""), ignore.case = TRUE)
  if (!isTRUE(on)) return(config)

  f <- file.path(root, "configs/cross_lagged/table1_harmonized_vars.R")
  if (!file.exists(f)) {
    warning("cross_lagged Table1 统一文件缺失: ", f, call. = FALSE)
    return(config)
  }
  e <- new.env(parent = baseenv())
  sys.source(f, envir = e)
  if (is.null(config$baseline_binary)) config$baseline_binary <- list()
  t1_vars <- e$.CROSS_LAGGED_TABLE1_INCLUDE_VARS
  config$baseline_binary$include_vars <- t1_vars
  config$baseline_binary$exclude_vars <- unique(c(
    as.character(config$baseline_binary$exclude_vars %||% character(0)),
    as.character(e$.CROSS_LAGGED_TABLE1_EXCLUDE_VARS)
  ))
  config$baseline_binary$table1_label_overrides <- e$.CROSS_LAGGED_TABLE1_LABELS
  config$baseline_binary$table1_append_units_from_dictionary <- FALSE
  # 单因素 / VIF screen：仅基线表特征（与 Table 1 同一变量池）
  config$baseline_binary$univariate_from_baseline_table1 <- TRUE
  if (is.null(config$univariate_incidence_binary)) config$univariate_incidence_binary <- list()
  config$univariate_incidence_binary$include_predictors <- t1_vars
  config$univariate_incidence_binary$univariate_from_baseline_table1 <- TRUE
  config$univariate_incidence_binary$excluded_predictors <- unique(c(
    as.character(config$univariate_incidence_binary$excluded_predictors %||% character(0)),
    as.character(e$.CROSS_LAGGED_TABLE1_EXCLUDE_VARS)
  ))
  # 髋部等 FI 课题默认 Frailty Index。课题已写展示名，或暴露不是 FI 时，不覆盖成虚弱指数。
  preset <- as.character((config$incidence %||% list())$index_var_display_name %||% "")[1L]
  idx <- as.character((config$incidence %||% list())$index_var %||% "")[1L]
  disp <- if (nzchar(preset)) {
    preset
  } else if (idx %in% c("FI", "Frailty", "Frailty_Index", "frailty_index", "")) {
    e$.CROSS_LAGGED_INDEX_DISPLAY_NAME %||% "Frailty Index"
  } else if (identical(idx, "Leisure_score")) {
    "Leisure activity score"
  } else {
    gsub("_", " ", idx, fixed = TRUE)
  }
  if (is.null(config$incidence)) config$incidence <- list()
  config$incidence$index_var_display_name <- disp
  if (is.null(config$logistic)) config$logistic <- list()
  config$logistic$index_var_display_name <- disp
  if (is.null(config$cross_lagged)) config$cross_lagged <- list()
  config$cross_lagged$table1_harmonize <- TRUE
  config$cross_lagged$univariate_from_baseline_table1 <- TRUE
  if (requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_info(
      "交叉滞后 Table 1 已统一: {length(t1_vars)} vars; UV/VIF screen 仅 Table1; index display={disp}"
    )
  }
  config
}
