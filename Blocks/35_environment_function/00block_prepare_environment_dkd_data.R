###############################################################################
#  prepare_environment_dkd_data — Step00 合并 D02 临床/环境 + baseline 调查权重
#
#  register_block: "prepare_environment_dkd_data"
#  典型流水线: 第一步（在 data_clean 之前）
#
#  输入 Data/nhanes/:
#    D02_data.RData, D02_environment_data.RData, D01_baseline_NHANES*.RData
#  写: ctx$data$raw = EnvResult; ctx$results$voc_columns; 可选落盘 D03_EnvResultData.RData
###############################################################################

block_prepare_environment_dkd_data <- function(ctx, ...) {
  cfg  <- ctx$config
  prep <- cfg$environment_prepare %||% list()
  if (!isTRUE(prep$enable %||% TRUE)) {
    cli::cli_alert_info("prepare_environment_dkd_data: enable=FALSE，跳过。")
    return(ctx)
  }

  root <- cfg$project$root %||% getwd()
  helper <- file.path(root, "R", "prepare_environment_dkd_data.R")
  if (!file.exists(helper)) {
    stop("prepare_environment_dkd_data: 未找到 ", helper, call. = FALSE)
  }
  source(helper, local = FALSE)

  res <- prepare_environment_dkd_merge(root, c(prep, list(
    project = cfg$project,
    data    = cfg$data
  )))

  ctx$data$raw <- res$EnvResult
  ctx$results$environment_dkd_prepared <- TRUE
  ctx$results$voc_columns <- res$voc_columns
  ctx$results$environment_prepare_meta <- list(
    baseline_path = res$baseline_path,
    out_path      = res$out_path,
    n             = nrow(res$EnvResult),
    n_voc         = length(res$voc_columns),
    cohort_filter = if (!is.null(res$cohort_filter)) basename(res$cohort_filter$path) else NULL
  )
  ctx$results$environment_raw_snapshot <- res$EnvResult
  if (!is.null(res$cohort_audit) && nrow(res$cohort_audit)) {
    ctx$results$cohort_id_audit <- res$cohort_audit
    audit_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir %||% ".", "Tables")
    dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)
    audit_path <- file.path(audit_dir, "Table_Cohort_ID_Audit.csv")
    tryCatch(
      utils::write.csv(res$cohort_audit, audit_path, row.names = FALSE, fileEncoding = "UTF-8"),
      error = function(e) cli::cli_alert_warning("cohort ID audit 导出失败: {e$message}")
    )
  }

  ctx$config$environment <- ctx$config$environment %||% list()
  ctx$config$environment$voc_columns <- res$voc_columns
  if (exists("environment_patch_voc_exclude", mode = "function")) {
    ctx$config <- environment_patch_voc_exclude(ctx$config, res$EnvResult)
  } else {
    ctx$config$incidence <- ctx$config$incidence %||% list()
    ctx$config$incidence$index_exclude_vars <- res$voc_columns
  }
  if (is.null(ctx$config$nhanes$cutoff_index_var) ||
      !nzchar(as.character(ctx$config$nhanes$cutoff_index_var %||% "")[1L])) {
    ctx$config$nhanes <- ctx$config$nhanes %||% list()
    ctx$config$nhanes$cutoff_index_var <- res$voc_columns[1L]
  }

  if (isTRUE(prep$save_merged %||% TRUE) && !is.null(res$out_path)) {
    ctx$config$data <- ctx$config$data %||% list()
    ctx$config$data$rawdata_path <- res$out_path
    ctx$config$data$rawdata_obj  <- prep$merged_obj %||% "EnvResult"
  }

  cli::cli_alert_success(
    "prepare_environment_dkd_data: n={nrow(res$EnvResult)}, VOC={length(res$voc_columns)}, baseline={basename(res$baseline_path)}"
  )
  if (!is.null(res$out_path)) {
    cli::cli_alert_info("已保存 {.file {res$out_path}}")
  }
  print(table(res$EnvResult$Source_File, useNA = "ifany"))

  ctx
}

register_block(
  "prepare_environment_dkd_data",
  block_prepare_environment_dkd_data,
  "合并 D02 临床+环境+baseline WTMEC/Source_File → EnvResult（标准 Data/nhanes 格式）"
)
